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

while true do 
    local rsp = trader:recv()
end



os.exit(1)