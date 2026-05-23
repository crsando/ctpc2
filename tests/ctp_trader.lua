local inspect = require "inspect"
local service = require "lservice2" .input(...)
local config = service.config

assert(config.account)

local ctp = require "lctp2"
local ffi = ctp.ffi
ctp.log_set_level("LOG_DEBUG")

local function slice(t, k)
    local o = {}
    for i, e in ipairs(t) do 
        o[i] = e[k]
    end
    return o
end

--[[
/////////////////////////////////////////////////////////////////////////
///TFtdcOrderStatusType是一个报单状态类型
/////////////////////////////////////////////////////////////////////////
///全部成交
#define THOST_FTDC_OST_AllTraded '0'
///部分成交还在队列中
#define THOST_FTDC_OST_PartTradedQueueing '1'
///部分成交不在队列中
#define THOST_FTDC_OST_PartTradedNotQueueing '2'
///未成交还在队列中
#define THOST_FTDC_OST_NoTradeQueueing '3'
///未成交不在队列中
#define THOST_FTDC_OST_NoTradeNotQueueing '4'
///撤单
#define THOST_FTDC_OST_Canceled '5'
///未知
#define THOST_FTDC_OST_Unknown 'a'
///尚未触发
#define THOST_FTDC_OST_NotTouched 'b'
///已触发
#define THOST_FTDC_OST_Touched 'c']]

--
-- internal procedure management
--
local R = {} -- handle trader response
local S = {} -- handle service request/response
local internal_suspend_lookup = {}
local rsp_cache = {}

local function resume_session_by_lookup(key, ...)
    local co = internal_suspend_lookup[key]
    if co then 
        service.resume_session(co, ...)
    end
end



-- CTP Traffic Limit, Only One Querying at a Time
local ctp_querying = false
local internal_suspend_query = {}

--
-- global(per-service) variables
--
local order_book = ctp.order_book.new()
local position_table = {}

local server, trader; local start_trader = function ()  
    server = config.account
    assert(server)
    print("trader account", inspect(server))

    trader = ctp.new_trader(server)
        :cond( service.get_cond() )
        :start( true ) -- blocking thread until settlement
end

--
-- fundamental routines
--
local function collect_rsp(rsp)
    -- io.stderr:write("collect_rsp: ", rsp.func_name, "\t", rsp.field_name, ":", rsp.req_id, "\n")
    local req_id = tonumber(rsp.req_id)
    if not req_id then return nil end
    local T = rsp_cache[req_id]

    if T then 
        T[#T+1] = rsp
    end

    if rsp.is_last == true then 
        local co = internal_suspend_lookup[rsp.req_id]
        -- print("is_last hit for req_id:", req_id, "resume_session", co)
        if co then 
            service.resume_session(co, T)
            internal_suspend_lookup[rsp.req_id] = nil
        end
    end
end

local function one_query_limit_begin()
    local running_thread = service.get_session()
    internal_suspend_query[running_thread] = true
    while ctp_querying do 
        coroutine.yield()
    end
    internal_suspend_query[running_thread] = nil
    
    ctp_querying = true
end

local function one_query_limit_end()
    ctp_querying = false
end

local function wait_trader_request(req_id)
    local running_thread = service.get_session()
    internal_suspend_lookup[req_id] = running_thread
    rsp_cache[req_id] = {} -- store results
    local T = rsp_cache[req_id]
    while true do
        local is_last = (T[#T] or {}).is_last or false
        if is_last then break end
        coroutine.yield()
    end
    internal_suspend_lookup[req_id] = nil
    rsp_cache[req_id] = nil
    return T
end

local function request_and_receive_ctp_query(query_name, ...)
    -- print("begin request: ", query_name)
    local f = assert(trader[query_name])
    one_query_limit_begin()
    local req_id = f(trader, ...)
    local rst = wait_trader_request(req_id)
    one_query_limit_end()
    -- print("end request: ", query_name)
    return slice(rst, "field")
end

local function ref_id(order)
    assert(order.FrontID and order.SessionID and order.OrderRef)
    return string.format("%d+%d+%012d", order.FrontID, order.SessionID, order.OrderRef)
end

local function wait_order_to_execute(order, req_id)
    local running_thread = service.get_session()
    -- internal_suspend_lookup[order.OrderRef] = running_thread
    -- local key = req_id and req_id or (order and ref_id(order)) or nil
    local key = assert(order and ref_id(order), "invalid order to wait")
    internal_suspend_lookup[key] = running_thread

    local info = nil
    while true do 
        local info = coroutine.yield() -- we expect to get the most up-to-date order info from S.OnRtnOrder
        local info = info or order_book:query(order) -- otherwise, check from database

        if info then 
            -- if Order is Canceled, return
            if info.OrderStatus == ctp.THOST_FTDC_OST_Canceled then 
                break
            elseif info._Traded and (info.OrderStatus == ctp.THOST_FTDC_OST_AllTraded) then -- return from OnRtnTrade
                break
            end
        end

        -- <TODO: TimeOut>
    end

    -- clean lookup
    internal_suspend_lookup[key] = nil

    return info
end

local wait_order_to_trade = function (order) return wait_order_to_execute(order, nil) end
local wait_order_to_cancel = wait_order_to_execute

-- #define THOST_FTDC_OFEN_Open '0'
-- #define THOST_FTDC_OFEN_Close '1'
-- #define THOST_FTDC_OFEN_ForceClose '2'
-- #define THOST_FTDC_OFEN_CloseToday '3'
-- #define THOST_FTDC_OFEN_CloseYesterday '4'
-- #define THOST_FTDC_OFEN_ForceOff '5'
-- #define THOST_FTDC_OFEN_LocalForceClose '6'
local function determine_order_flag(symbol, volume)
    assert(symbol and volume)
    service.call(service.get_id(), "query_position") -- update global position_table
    local long, short = unpack(position_table and position_table[symbol] or {})
    long = long or 0
    short = short or 0

    if volume > 0 and short > 0 then 
        return ctp.THOST_FTDC_OFEN_Close
    elseif volume < 0 and long > 0 then
        return ctp.THOST_FTDC_OFEN_Close
    else 
        return ctp.THOST_FTDC_OFEN_Open 
    end
end


local function order_insert(symbol, price, volume, flag)
    if not flag then 
        flag = determine_order_flag(symbol, volume)
    end
    -- ctp.ctpc.ctp_trader_order_insert(trader.trader, symbol, price, volume, flag)
    trader:order_insert(symbol, price, volume, flag)
    local order = {}
    order.FrontID = tonumber(trader.trader.front_id)
    order.SessionID = tonumber(trader.trader.session_id)
    order.OrderRef = ffi.string(trader.trader.lst_order_ref)
    order_book:insert(order)
    return order
end

-- we only support one type or order cancellation : through ExchangeID + OrderSysID
local function order_cancel(...)
    return trader:order_cancel(...)
end

-- @@@
-- process trader internal messages
function service.on_idle()
    while true do 
        do 
            local rsp = trader:recv(false) -- non-blocking
            if rsp == nil then break end -- exit idle
            local func_name = rsp.func_name
            local handler = R[func_name] or collect_rsp
            handler( rsp )
        end

        do 
            -- because we limit to only one ctp query at a time
            -- some session may be waiting for other ctp query to finish
            -- here we try to resume suspend ctp query session
            -- if not ctp_querying then 
                for co, _ in pairs(internal_suspend_query) do 
                    service.resume_session(co)
                    break -- take just on co
                end
            -- end
        end

    end -- end while
end

-- trader logic



function R.OnRtnOrder(rsp)
    local field = rsp.field
    local order = order_book:insert(field) -- update or insert
    resume_session_by_lookup(order and ref_id(order), order)
end

function R.OnRtnTrade(rsp)
    local field = rsp.field
    -- Custom Field Label
    field._Traded = true
    local order = order_book:insert(field)
    resume_session_by_lookup(order and ref_id(order), order)
end

function R.OnRspOrderAction(rsp)
    local req_id = assert(rsp.req_id, "no valid req_id")
    resume_session_by_lookup(ref_id, rsp)
end

function S.query_account()
    local rst = request_and_receive_ctp_query("query_account")
    return rst[1]
end


--[[
/////////////////////////////////////////////////////////////////////////
///TFtdcPosiDirectionType是一个持仓多空方向类型
/////////////////////////////////////////////////////////////////////////
///净
#define THOST_FTDC_PD_Net '1'
///多头
#define THOST_FTDC_PD_Long '2'
///空头
#define THOST_FTDC_PD_Short '3'
]]
function S.query_position()
    local rst = request_and_receive_ctp_query("query_position")

    local pt = {}
    for _, field in ipairs(rst) do 
        if (field ~= nil) and (field.InstrumentID) then 
            local symbol = field.InstrumentID
            pt[symbol] = pt[symbol] or {}
            entry = pt[symbol]
            direction = field.PosiDirection - 49 -- an hack
            entry[direction] = (entry[direction] or 0) + field.Position

            print(symbol, direction, field.Position)
        end
    end

    position_table = pt -- update global variable

    -- return slice(T,"field")
    return position_table
end

function S.query_instrument(symbol)
    local rst = request_and_receive_ctp_query("query_instrument", symbol)
    if rst[1] and type(rst[1] == "table") then 
        return rst[1]
    else 
        return {}
    end
end

function S.query_order()
    local rst = request_and_receive_ctp_query("query_order")
    return rst
end

-- insert order and wait for order to fill
function S.trade(symbol, price, volume)
    assert(symbol ~= nil, "no symbol")
    local order = order_insert(symbol, price, volume, nil)
    order = wait_order_to_trade(order)
    return order
end

function S.cancel(order)
    local req_id = order_cancel(order)
    order = wait_order_to_cancel(order, req_id)
    return order
end

-- close all positions one by one
function S.nuke_all()
    while true do 
        service.call(service.get_id(), "query_position")

        print(inspect(position_table))

        local found = false
        local symbol, long, short
        while not found do 
            local n = 0
            for s, entry in pairs(position_table) do 
                symbol = s
                long, short = unpack(entry)
                n = n + (long or 0) + (short or 0)
                if n > 0 then
                    found = true 
                    break
                end
            end

            if n == 0 then 
                return
            end
        end

        if long > 0 then
            local rst = service.call(service.get_id(), "trade", symbol, 0, -1)
            -- print("short", rst.InstrumentID, rst.VolumeTraded)
        elseif short > 0 then
            local rst = service.call(service.get_id(), "trade", symbol, 0, 1)
            -- print("long", rst.InstrumentID, rst.VolumeTraded)
        else
            break
        end
    end -- end while true
end

-- #define THOST_FTDC_OFEN_Open '0'
-- #define THOST_FTDC_OFEN_Close '1'
-- #define THOST_FTDC_OFEN_ForceClose '2'
-- #define THOST_FTDC_OFEN_CloseToday '3'
-- #define THOST_FTDC_OFEN_CloseYesterday '4'
-- #define THOST_FTDC_OFEN_ForceOff '5'
-- #define THOST_FTDC_OFEN_LocalForceClose '6'
function S.test_order()
    service.call(service.get_id(), "query_position")

    while true do 

        local finished = true
        for symbol, posi in pairs(position_table) do 
            if posi[0] > 0 then 
            end
        end
    end


    order_insert("IF2409", 0, 1, ctp.THOST_FTDC_OFEN_Open)
    order_insert("IF2409", 0, -1, ctp.THOST_FTDC_OFEN_Open)
    service.call(service.get_id(), "query_position")
    print(inspect(position_table))

    order_insert("IF2409", 0, 1, ctp.THOST_FTDC_OFEN_Open)
    order_insert("IF2409", 0, -1, ctp.THOST_FTDC_OFEN_Open)
    service.call(service.get_id(), "query_position")
    print(inspect(position_table))
    return true
end

function S.start()
    start_trader()
    return true
end

function S.quit()
    print("trader is quitting")
    service.call(0, "notify", service.get_id(), "quit")
    service.quit()
end

service.dispatch(S)