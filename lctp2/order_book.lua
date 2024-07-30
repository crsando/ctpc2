-- local inspect = require "inspect"
local isempty = function (s) return (s==nil) or (string.match(s, "^%s*$") ~= nil) end

local _mt_order_book = {}

_mt_order_book.query = function (self, t)
    if t == nil then return nil end
    -- t : table or cdata (CThostFtdcOrderField)


    for _, order in ipairs(self) do 
        -- print("check order: ", inspect(order))
        local criterion = true

        if not isempty(t.OrderRef) then 
            criterion = criterion and (t.OrderRef == order.OrderRef)
            if criterion then return order end
        end

        if not isempty(t.OrderSysID) then 
            criterion = criterion and (t.ExchangeID == order.ExchangeID)
            criterion = criterion and (t.OrderSysID == order.OrderSysID)
            if criterion then return order end
        end
    end -- end for
    return nil
end

_mt_order_book.update_trade = function(self, t)
        local o = self:query(t)
        if not o then return nil end

        for k, v in pairs(t) do 
            o[k] = t[k] or o[k]
        end
        return o
    end

-- flag: true for insert or update, false for update only
_mt_order_book.update_or_insert = function(self, t, flag)
    local order = self:query(t)

    if (not flag) and (not order) then
        return nil
    end

    local o = order or {} -- reference, not copy
    for k, v in pairs(t) do 
        o[k] = t[k] or o[k]
    end

    if not order then
        self[#self + 1] = o
    end
    return o
end

_mt_order_book.update = function(self, t) return self:update_or_insert(t, false) end
_mt_order_book.insert = function(self, t) return self:update_or_insert(t, true) end

_mt_order_book.__index = _mt_order_book

local function new_order_book()
    local o = {}
    setmetatable(o, _mt_order_book)
    return o
end

return { new = new_order_book }