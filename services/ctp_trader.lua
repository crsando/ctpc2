-- ctp trader

local inspect = require "inspect"
local ctp = require "lctp2"
ctp.log_set_level("LOG_DEBUG")

local service = require "lservice2" .input(...)
local config = service.config

local server_list = {
        ["gtja-sim"] = {
            front_addr = "tcp://180.169.50.131:42205",
            broker = "2071", 
            user = "0061831885", 
            pass = "zhy19930311", 
            app_id = "client_tara_231031", 
            auth_code = '20231101ZHOUYH01',
        },
        ["hy-sim"] = {
            front_addr = "tcp://101.230.79.235:33205",
            broker = "3070", 
            user = "333307126", 
            pass = "930706", 
            app_id = "client_tara_241201", 
            auth_code = 'CY2LFL92CISEEKVM',
        },
        ["openctp"] = {
            front_addr = "tcp://trading.openctp.cn:30001",
            broker = "9999", 
            user = "7572", 
            pass = "123456", 
            app_id = "client_tara_231031", 
            auth_code = '20231101ZHOUYH01',
        },
        ["simnow"]=  {
            front_addr = "tcp://182.254.243.31:40001",
            broker = "9999", 
            user = "264530", 
            pass = "bE@453162948", 
            app_id = "simnow_client_test", 
            auth_code = '0000000000000000',
        },
    }


local function slice(t, k)
    local o = {}
    for i, e in ipairs(t) do 
        o[i] = e[k]
    end
    return o
end

--
-- internal procedure management
--
local R = {} -- handle trader response
local S = {} -- handle service request/response

--
-- global(per-service) variables
--
local server, trader; S.start = function ()  
    -- server = assert(config.account or server_list["gtja-sim"])
    server = assert(config.account or server_list["simnow"])
    ctp.log_debug("trader account %s", inspect(server, {newline = " "}))

    trader = ctp.new_trader(server)
        :cond( service.get_cond() )
        :start( true ) -- blocking thread until settlement
    return true
end

--
-- warp query request/response
-- hard rule: one query at a time, a queue is used to ensure this
--
local query = {
    start_index = 1,
    last_index = 0,
    max_length = 100,
    
    reorder = function(self)
            local s, e = self.start_index, self.last_index
            local n = self.last_index - self.start_index + 1

            local i = 1 
            while i <= n do 
                local tmp = self[self.start_index + i - 1]
                self[self.start_index + i - 1] = nil
                self[i] = tmp
            end

            self.start_index = 1 
            self.last_index = n
        end,

    -- entry point
    request = function(self, name, ...)
            local entity = {
                    session = service.get_session(),
                    req_id = nil,
                    name = name,
                    body = {...},
                    cache = {},
                }

            self:enqueue(entity)
            self:process()

            local ok, rst = coroutine.yield() -- wait for response
            return ok, rst
        end,
    -- exit point
    response = function(self)
            local q = self:first()
            if q then 
                if q.session then 
                    service.resume_session(q.session, 1, q.cache)
                end
                self:dequeue()
            end
        end,

    enqueue = function(self, entity)
            -- check
            if self.start_index == 1 and self.last_index >= self.max_length then 
                return 0, "too many queries"
            end 

            if self.last_index >= self.max_length then 
                self:reorder()
            end

            -- enqueue first, then process on idle
            do 
                self.last_index = self.last_index + 1
                self[self.last_index] = entity
            end
        end,
    dequeue = function(self)
            self[self.start_index] = nil 
            self.start_index = self.start_index + 1
        end,
    first = function(self)
            if self.last_index >= self.start_index then 
                return self[self.start_index]
            else 
                return nil
            end
        end,

    -- send the real ctp request/query by trader
    process = function(self)
            local q = self:first()
            if q and (not q.req_id) then 
                local f = trader[q.name]

                if not f then 
                    return 0, "no matched query name"
                end

                local req_id = f(trader, unpack(q.body))
                q.req_id = req_id

                return 1 -- did something
            else 
                return 0 -- did nothing
            end
        end,

    update = function (self, rsp)
            local q = self:first()

            if not q then return end

            -- check request id for a match, ignore if not matched
            if not ( q.req_id == rsp.req_id ) then 
                io.stderr:write("req_id not match, ignore reponse | req_id : " .. rsp.req_id .. "\n")
                return 
            end

            -- cache rst
            do 
                q.cache[#(q.cache) + 1] = rsp
            end

            -- finish query
            if rsp.is_last == true then 
                self:response()
                self:process() -- process next request
            end
        end,
} -- end query object definitions

--
-- query interfaces
--

function S.query_account()
    local ok, rst = query:request("query_account")
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
    local ok, rst = query:request("query_position")

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

    return slice(rst, "field")
end

function S.query_instrument_margin_rate(symbol)
    local ok, rst = query:request("query_instrument_margin_rate", symbol)
    return ok, rst
end

function S.query_instrument(symbol)
    local ok, rst = query:request("query_instrument", symbol)
    print("query instrument", ok, inspect(rst))


    if rst[1] and type(rst[1] == "table") then 
        return rst[1]
    else 
        return {}
    end
end

function S.query_order()
    local ok, rst = query:request("query_order")
    return rst
end

--
-- Order Related Stuffs
-- 

local function trim(s)
    if s == nil then
        return nil
    end
    return s:match("^%s*(.-)%s*$")
end

local function make_order_hashkey(o)
    if o and 
        (o.BrokerID ~= nil) and 
         (o.InvestorID ~= nil) and 
         (o.FrontID ~= nil) and 
         (o.SessionID ~= nil) and 
         (o.OrderRef ~= nil) then  

        local key = string.format("%s+%s+%s+%s+%s",
            trim(o.BrokerID),
            trim(o.InvestorID),
            tostring(o.FrontID),
            tostring(o.SessionID),
            trim(o.OrderRef)
        )

        return key
    else 
        return nil
    end 
end

local function match_order_sysid(o1, o2)
    if (trim(o1.ExchangeID) == trim(o2.ExchangeID)) and 
        (trim(o1.OrderSysID) == trim(o2.OrderSysID)) then 
        return true 
    else 
        return false 
    end
end

-- order book
local order = {
    --
    -- cache 的作用是存放提交中、未交易完成的订单，追踪状态更新
    -- 理论上全部成交后就可以清楚了
    --
    cache = { },

    --
    -- methods
    --
    
    -- 单纯的插入订单，不等待
    insert = function (self, symbol, price, volume, flag)
            local o = trader:order_insert(symbol, price, volume, flag)
            local key = make_order_hashkey(o)
            do 
                o._key = key
                o._symbol = symbol
                o._price = price
                o._volume = volume
                o._flag = flag
            end 
            self.cache[key] = o
            ctp.log_debug("order inserted %s | %s", key, inspect(o, {newline =""}))
            return o
        end,


    --
    -- 正常交易执行的链路：发起发调用trade/cancel（对应coroutine挂起），结束收到消息后调用finish（coroutine继续）
    --

    -- 执行交易，等待交易完成
    -- return: msg, entry
    trade = function (self, ...)
            local symbol, price, volume, flag
            local n_args = select("#", ...)
            local args = {...}

            if (n_args == 1) and (type(args[1]) == "table") then 
                symbol, price, volume, flag = args.symbol, args.price, args.volume, args.flag
            elseif n_args == 4 then 
                symbol, price, volume, flag = ...
            end

            if not symbol then 
                return 0, "no symbol"
            elseif not volume then 
                return 0, "no volume"
            end

            -- defaults
            price = price or 0.0
            flag = flag or ctp.THOST_FTDC_OFEN_Open

            local o = self:insert(symbol, price, volume, flag)

            if o and o._key then 
                self.cache[o._key]._session = service.get_session()
                -- wait for order to trade
                local msg, entry = coroutine.yield()
                return msg, entry
            else 
                    return 0, "order insertion failed"
            end 
        end,

    -- 主动取消一个挂单
    cancel = function (self, ...)
        end,

    -- 订单结束有几种情况
    -- Time-out: 暂时未实现
    -- Traded: OnRtnTrade + Volume 满足条件
    -- Canceled: 订单被取消
    -- 这个函数不校验（校验在update中进行），而是直接结束这个订单，清理cache
    -- return: ok, error_msg
    finish = function (self, key, msg)
            if not key then return 0, "no key provied" end 

            local entry = self.cache[key]
            if not entry then return 0, "no entry provied" end 

            self.cache[key] = nil  -- release cache

            if entry._session then 
                local co = entry._session
                entry._session = nil -- release session
                service.resume_session( co, msg, entry )
                -- success
                return 1, nil
            else 
                return 0, "no coroutine found"
            end 
        end,

    -- 跟新cache信息，同时判断这个订单是否需要被结束
    update = function (self, rsp)
            local function _merge_entry(dst, src)
                dst = dst or {}
                for k, v in pairs(src) do 
                    dst[k] = src[k] or dst[k]
                end
                return dst
            end 

            local count = 0
            local key = make_order_hashkey(rsp.field)

            -- update entry, create new if needed
            if key then 
                -- Translation
                self.cache[key] = _merge_entry(self.cache[key], rsp.field)
                count = count + 1
            else -- OnRtnTrade has no OrderRef, using ExchangeID and OrderSysID
                for k, entry in pairs(self.cache) do 
                    if match_order_sysid(entry, rsp.field) then 
                        key = k 
                        self.cache[k] = _merge_entry(entry, rsp.field)
                        count = count + 1
                        break
                    end
                end
            end

            if not key then 
                return count, "key match error on update"
            else 
                -- print("update cached ok", key, inspect(self.cache[key]))
            end

            local entry = self.cache[key]
            -- 判断是否需要结束这个订单

            -- 一般是报单阶段产生错误，来自OnRspOrderInsert
            if (trim(rsp.func_name) == "OnRspOrderInsert") and rsp.rsp_info and rsp.rsp_info.ErrorID then 
                ctp.log_debug("finish order %s | %s", key, "on *insert error*")
                self:finish(key, "invalid: (" .. rsp.rsp_info.ErrorID ..")" )
            -- 仅在OnRtnTrade，且Volume达标（不在OnRtnOrder时结束订单）
            elseif (trim(rsp.func_name) == "OnRtnTrade") and (entry.OrderStatus == ctp.THOST_FTDC_OST_AllTraded) then 
                ctp.log_debug("finish order %s | %s", key, "all-traded")
                self:finish(key, "complete")
            elseif entry.OrderStatus == ctp.THOST_FTDC_OST_Canceled then 
                local error_msg = rsp and rsp.rsp_info and rsp.rsp_info.ErrorMsg or ""
                ctp.log_debug("finish order %s | %s", key, error_msg)
                self:finish(key, "canceled")
            end 

            return count
        end,
}


function R.OnRtnOrder(rsp) order:update(rsp) end
function R.OnRtnTrade(rsp) order:update(rsp) end
function R.OnRspOrderAction(rsp) order:update(rsp) end

-- 这只在报单异常时才会出现
function R.OnRspOrderInsert(rsp)
    -- 这个巨坑，我们手动补几个字段 
    for k, v in pairs(trader:session_info()) do 
        rsp.field[k] = v
    end

    order:update(rsp)
end

--
-- Fundemental Stuffs
--

function S.quit()
    ctp.log_debug("trader is quitting")
    service.call(0, "notify", service.get_id(), "quit")
    service.quit()
end

-- main loop
-- process trader internal messages
function service.on_idle()
    while true do 
        local rsp = trader:recv(false) -- non-blocking
        if rsp then 
            -- process trader messages
            local handler = R[rsp.func_name] or function (rsp) query:update(rsp) end 
            handler( rsp )
        else 
            -- exit idle status when there is no remaing messages
            return 
        end
    end
end

-- Nuke Every Existing Positions
function S.nuke()
    local rst = service.call(service.get_id(), "query_position")

    for _, entry in ipairs(rst) do 
        local volume; do 
                volume = entry.Position
                if entry.PosiDirection == ctp.THOST_FTDC_PD_Long then 
                    volume = (-1) * volume
                end
            end
        if volume ~= 0 then 
            -- order:insert(entry.InstrumentID, 0, volume, ctp.THOST_FTDC_OF_Close)
            service.call(service.get_id(), "trade", entry.InstrumentID, 0, volume, ctp.THOST_FTDC_OF_Close)
        end
    end
end

function S.trade(...)
    return order:trade(...)
end

function S.test()
    ctp.log_debug("begin trader test sequence")
    do  
        return 1
    end

    print("begin trader insider test")

    local rst = service.call(service.get_id(), "query_position")
    print("positions", inspect(rst))

    local rst = service.call(service.get_id(), "nuke")

    -- local rst = service.call(service.get_id(), "query_account")
    -- print(inspect(rst))

    -- local rst = service.call(service.get_id(), "query_order")
    -- print(inspect(rst))


    -- local rst = service.call(service.get_id(), "query_instrument_margin_rate", "IF2507")
    -- print(inspect(rst))

    print("------")
    print("begin trader order insert test")
    print("------")

    -- 测试无效单（价格过高）
    do 
        local msg, rst = service.call(service.get_id(), "trade", "IF2607", -100, 1, ctp.THOST_FTDC_OFEN_Open)
        print("trade result", msg, rst.VolumeTraded or 0)
    end

    -- 市价单，成交后平仓
    --[[
    do 
        local msg, rst = service.call(service.get_id(), "trade", "IF2607", 0, 1, ctp.THOST_FTDC_OFEN_Open)
        print("trade result", msg, rst.VolumeTraded or 0)
        local msg, rst = service.call(service.get_id(), "trade", "IF2607", 0, -1, ctp.THOST_FTDC_OFEN_Close)
        print("trade result", msg, rst.VolumeTraded or 0)
    end 
    ]]

    
    -- order:insert("IF2607", 0, 1, ctp.THOST_FTDC_OFEN_Open)
    return 1
end

service.dispatch(S)