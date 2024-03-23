-- jit.off(true, true)

local inspect = require "inspect"

local ctp = require "lctp2"
local ffi = ctp.ffi

-- ctp.log_set_level("LOG_ERROR")
ctp.log_set_level("LOG_INFO")
-- ctp.log_set_level("LOG_DEBUG")

local pk = ctp.position_keeper()

local order_book = {}
local _mt_order_book = {}

_mt_order_book.query = function (self, t)
    if t == nil then return nil end
    -- t : table or cdata (CThostFtdcOrderField)
    local tostr = (type(t) == "table") and tostring or ffi.string
    local isempty = function (s) return (s==nil) or (string.match(tostr(s), "^%s*$") ~= nil) end


    for _, order in ipairs(order_book) do 
        print("check order: ", inspect(order))
        local criterion = true

        if 
            ((type(t) == "table") and (t.OrderRef)) or 
            ((ffi.istype("struct CThostFtdcOrderField *", t)) and (not isempty(t.OrderRef)))
            then 
            criterion = criterion and (tostr(t.OrderRef) == order.OrderRef)

            -- no need the compare these
            -- criterion = criterion and (tostr(t.FrontID) == order.FrontID)
            -- criterion = criterion and (tostr(t.SessionID) == order.SessionID)
            if criterion then return order end
        end

        if not isempty(t.OrderSysID) then 
            criterion = criterion and (tostr(t.ExchangeID) == order.ExchangeID)
            criterion = criterion and (tostr(t.OrderSysID) == order.OrderSysID)
            if criterion then return order end
        end
    end -- end for
    return nil
end

_mt_order_book.update_trade = function(self, t)
        local tostr = (type(t) == "table") and tostring or ffi.string
        local o = self:query(t)
        if not o then return nil end
        local cols_str = { "TradeDate", "TradeTime" }
        local cols_num = { "OffsetFlag", "Direction", "Volume", "Price" }
        for _, k in ipairs(cols_str) do o[k] = (t[k] ~= nil) and tostr(t[k]) end
        for _, k in ipairs(cols_num) do o[k] = (t[k] ~= nil) and tonumber(t[k]) end
        return o
    end

-- flag: true for insert or update, false for update only
_mt_order_book.update_or_insert = function(self, t, flag)
    local order = self:query(t)
    if (not flag) then
        if (not order) then return nil end
    end

    local tostr = (type(t) == "table") and tostring or ffi.string
    local isempty = function (s) return (s~=nil) and (string.match(tostr(s), "^%s*$") ~= nil) end

            -- insert new order
        local cols_str = { 
                    "OrderRef", "OrderSysID", "ExchangeID", "InstrumentID",
                 }

        local cols_num = {
                "OrderSubmitStatus", "OrderStatus", -- char type
                "LimitPrice", "VolumeTotal", "VolumeTraded",  -- double type
                -- from OnRtnTrade, final results
            }


    local o = order or {} -- reference, not copy
    for _, k in ipairs(cols_str) do o[k] = (t[k] ~= nil) and tostr(t[k]) end
    for _, k in ipairs(cols_num) do o[k] = (t[k] ~= nil) and tonumber(t[k]) end

    if not order then
        self[#self + 1] = o
    end
    return o
end

_mt_order_book.update = function(self, t) self:update_or_insert(t, false) end
_mt_order_book.insert = function(self, t) self:update_or_insert(t, true) end


_mt_order_book.__index = _mt_order_book
setmetatable(order_book, _mt_order_book)

function cast_field(rsp)
    if rsp.field == nil then return nil end
    assert(rsp.desc ~= nil)
    local ptr_type = "struct " .. ffi.string(rsp.desc) .. " * "
    local ptr = assert(ffi.cast(ptr_type, rsp.field))
    if ptr ~= nil then 
        ffi.gc(ptr, ffi.C.free)
    end
    return ptr
end


-- handle trader response
local handler = {}

function handler.CThostFtdcOrderField(rsp)
    local ptr = cast_field(rsp)
    order_book:update(ptr)
end
-- OnRtnOrder
function handler.CThostFtdcTradeField(rsp)
    local ptr = cast_field(rsp)
    order_book:update_trade(ptr)
end

function handler.CThostFtdcInvestorPositionField(rsp)
    pk:update(rsp)
end


function process_message(trader, criterion)
    local flg = false
    while not flg do 
        local rsp = trader:recv()
        print("process message | desc ", ffi.string(rsp.desc), "islast", rsp.last)
        local h = handler[ffi.string(rsp.desc)] or function() print("no handler for ", ffi.string(rsp.desc)) end
        h(rsp) 

        flg = criterion(rsp)
        ctp.ctpc.ctp_rsp_free(rsp)
    end
    print("end of process message")
end

local server = ctp.servers.trader["openctp-7x24"] 

-- prompt
if not server.pass then 
    io.write("user: ", server.user, "\n")
    io.write("password: ")
    server.pass = io.read("*line")
end

local trader = ctp.new_trader(server):start()

-- remove 

print("---")
print "testing start"
print("---")

-- local u, o = pcall(function () return trader.trader.session_id end)
-- print(u, o)

-- os.exit(1)


function position()
    trader:query_position()
    process_message(trader, function(rsp) 
            return (ffi.string(rsp.desc) == "CThostFtdcInvestorPositionField") and 
                (rsp.last == 1)
        end)
    local t = pk:table()
    print(inspect(t))
end

position()


print("---")
print "testing order insert"
print("---")

-- #define THOST_FTDC_OFEN_Open '0'
-- #define THOST_FTDC_OFEN_Close '1'
-- #define THOST_FTDC_OFEN_ForceClose '2'
-- #define THOST_FTDC_OFEN_CloseToday '3'
-- #define THOST_FTDC_OFEN_CloseYesterday '4'
-- #define THOST_FTDC_OFEN_ForceOff '5'
-- #define THOST_FTDC_OFEN_LocalForceClose '6'

local op_flg = {
    Open = 48 + 0,
    Close = 48 + 1,
    CloseYesterday = 48 + 3
}

function order_insert(symbol, volume, flag)
    print(">>> lctpc2 order_insert", symbol, volume, flag)

    local flag = flag
    if not flag then 
        local u = {}
        for _, p in ipairs(pk:table()) do 
            if p.symbol == symbol then 
                u[p.direction] = (u[p.direction] or 0) + p.num
            end
        end

        if volume > 0 then 
            if u["short"] > 0 then 
                flag = op_flg.Close
            end
        elseif volume < 0 then 
            if u["long"] > 0 then 
                flag = op_flg.Close 
            end
        end
        flag = flag or op_flg.Open
    end
    print("flag", flag)

    ctp.ctpc.ctp_trader_order_insert(trader.trader, symbol, 0, volume, flag)
    local order = {}
    order.FrontID = tonumber(trader.trader.front_id)
    order.SessionID = tonumber(trader.trader.session_id)
    order.OrderRef = ffi.string(trader.trader.lst_order_ref)
    order_book:insert(order)

    process_message(trader, function (rsp) 
            return ffi.string(rsp.desc) == "CThostFtdcTradeField" 
        end)

    local order = order_book:query(order)
    print("order book", inspect(order_book))
    print("Order Traded", inspect(order))

    position()
end

-- order_insert("i2406", 1, op_flg.Open)
-- order_insert("i2406", -1, op_flg.Close)


-- order_insert("IF2406", 1, op_flg.Open)
-- order_insert("IF2406", -1, op_flg.Close)

-- order_insert("cu2406", 1, op_flg.Open)
-- order_insert("cu2406", -1, op_flg.Close)

for i = 1, 50 do
    position()
    order_insert("i2406", -1)
end

os.exit(1)