local inspect = require "inspect"
local ctp = require "lctp2"
ctp.log_set_level("LOG_DEBUG")

local service = require "service"
local config = service.config; do 
        -- do nothing
    end

local S = {}

local uv = require "luv"

uv.new_timer():start(0, 5000, function()
        service.send(service.get_id(), "heartbeat")
    end)


local function make_pos_table(ctp_fields)
    local pt = {}
    for _, field in ipairs(ctp_fields) do 
        if (field ~= nil) and (field.InstrumentID) then 
            local symbol = field.InstrumentID
            pt[symbol] = pt[symbol] or {}

            if field.PosiDirection == ctp.THOST_FTDC_PD_Long then 
                direction = 1 
            elseif field.PosiDirection == ctp.THOST_FTDC_PD_Short then 
                direction = -1
            else 
                direction = 0 
                ctp.log_debug("unidentified PosiDirection %s : %d", field.InstrumentID, field.PosiDirection)
            end

            pt[symbol].net_position = (pt[symbol].net_position or 0) + (direction * field.Position)
        end
    end

    return pt
end


function S.heartbeat()
    ctp.log_debug("bot heartbeat")
    local quotes = service.call("collector", "get_quotes")
    local act = service.call("trader", "query_account")
    local pos = service.call("trader", "query_position")

    local pt = make_pos_table(pos)
    for symbol, entry in pairs(pt) do 
        entry.last_price = quotes[symbol]
        if not quotes[symbol] then 
            service.call("collector", "subscribe", symbol)
        end
    end

    print(">>>Balance", act.Balance)
    print(">>>", inspect(pt))
end

return service.dispatch(S)