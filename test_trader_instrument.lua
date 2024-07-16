-- jit.off(true, true)

local inspect = require "inspect"

local ctp = require "lctp2"
local ffi = ctp.ffi

-- ctp.log_set_level("LOG_ERROR")
ctp.log_set_level("LOG_INFO")
-- ctp.log_set_level("LOG_DEBUG")

local server = ctp.servers.trader["openctp-7x24"] 

-- prompt
if not server.pass then 
    io.write("user: ", server.user, "\n")
    io.write("password: ")
    server.pass = io.read("*line")
end

local trader = ctp.new_trader(server):start()

print("---")
print "testing start"
print("---")

trader:query_instrument()

local futures = {}

while true do 
    local rsp = trader:recv()
    local field = ffi.cast( "struct " .. ffi.string(rsp.field_name) .. "*", rsp.field)

    if tonumber(field.ProductClass) == 49 then -- Futures
        local c = { 
                symbol = ffi.string(field.InstrumentID),
                exchange_id = ffi.string(field.ExchangeID),
                product = ffi.string(field.ProductID),
                expire_date = ffi.string(field.ExpireDate),
            }

        print("future", inspect(c))
        futures[#futures + 1] = c
    end

    if rsp.last == 1 then 
        break 
    end
end