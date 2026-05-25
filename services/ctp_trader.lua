local inspect = require "inspect"
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
}


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

--
-- internal procedure management
--
local R = {} -- handle trader response
local S = {} -- handle service request/response

--
-- global(per-service) variables
--
local server, trader; S.start = function ()  
    server = assert(config.account or server_list["gtja-sim"])
    print("trader account", inspect(server))

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
                -- print("query enqueued at", self.last_index, inspect(self[self.last_index]))
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
    print("query account: ", ok, inspect(rst))
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

    -- print(inspect(rst))

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
    return slice(rst, "field")
end

function S.query_instrument_margin_rate(symbol)
    local ok, rst = query:request("query_instrument_margin_rate", symbol)
    print("query instrument margin rate", ok, inspect(rst))
    return rst
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
        (trim(o2.OrderSysID) == trim(o2.OrderSysID)) then 
        return true 
    else 
        return false 
    end
end

-- order book
local order = {
    cache = { },

    -- methods
    
    insert = function (self, symbol, price, volume, flag)
            local o = trader:order_insert(symbol, price, volume, flag)
            local key = make_order_hashkey(o)
            print("order inserted", key)
            self.cache[key] = o
            return o
        end,
    cancel = function (self)
        end,
    update = function (self, rsp)
            local function merge(dst, src)
                local o = dst or {}
                for k, v in pairs(o) do 
                    o[k] = src[k] or o[k]
                end
                return dst
            end 

            local count = 0
            local key = make_order_hashkey(rsp.field)

            -- update entry, create new if needed
            if key then 
                -- Translation
                do 
                    if rsp.field.OrderStatus == ctp.THOST_FTDC_OST_Canceled then 
                        print("order update: status : cancel", key)
                    elseif rsp.field.OrderStatus == ctp.THOST_FTDC_OST_AllTraded then 
                        print("order update: status : all traded", key)
                    end
                end 


                self.cache[key] = merge(self.cache[key], rsp.field)
                count = count + 1
            end 

            -- OnRtnTrade has no OrderRef, using ExchangeID and OrderSysID
            if not key then 
                for k, entry in pairs(self.cache) do 
                    if match_order_sysid(entry, rsp.field) then 
                        self.cache[k] = merge(entry, rsp.field)
                        count = count + 1
                    end
                end
            end

            print("get order ", rsp.func_name, key, "number of entries updated : ", count)

            return count
        end,
}

function S.query_order()
    local ok, rst = query:request("query_order")
    return rst
end

function R.OnRtnOrder(rsp)
    -- print("OnRtnOrder", inspect(rsp))
    order:update(rsp)
end

function R.OnRtnTrade(rsp)
    -- print("OnRtnTrade", inspect(rsp))
    order:update(rsp)
    -- print(inspect(order.cache))
end

function R.OnRspOrderAction(rsp)
    order:update(rsp)
end

--
-- Fundemental Stuffs
--

function S.quit()
    print("trader is quitting")
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
            local handler = R[rsp.func_name] 
                                or function (rsp) query:update(rsp) end 
            handler( rsp )
        else 
            -- exit idle status when there is no remaing messages
            return 
        end
    end
end

-- close all positions one by one
function S.nuke_all()
    while true do 
        local pt = service.call(service.get_id(), "query_position")

        local found = false
        local symbol, long, short
        while not found do 
            local n = 0
            for s, entry in pairs(pt) do 
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
            order:insert(entry.InstrumentID, 0, volume, ctp.THOST_FTDC_OF_Close)
        end
    end
end

function S.test()
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

    print("begin trader order insert test")
    order:insert("IF2607", 0, 1, ctp.THOST_FTDC_OFEN_Open)
    return 1
end

service.dispatch(S)