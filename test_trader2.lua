-- jit.off(true, true)

local inspect = require "inspect"

local ctp = require "lctp2"
local ffi = ctp.ffi
local uv = require "luv"

-- ctp.log_set_level("LOG_ERROR")
ctp.log_set_level("LOG_DEBUG")

local server = ctp.servers.trader["openctp-7x24"] 

-- prompt
if not server.pass then 
    io.write("user: ", server.user, "\n")
    io.write("password: ")
    server.pass = io.read("*line")
end

local trader = ctp.new_trader(server):start()

print("---")

for i = 1, 1 do
    trader:query_account()
    local rsp = trader:recv()
    local act = ffi.new("struct CThostFtdcTradingAccountField *", rsp.field)
    print("Balance", act.Balance)
end

local pk = ctp.position_keeper()

trader:query_position()

local finished = false
while not finished do 
    local rsp = trader:recv()
    finished = pk:update(rsp)
end

local t = pk:table()

print(inspect(t))

os.exit(1)