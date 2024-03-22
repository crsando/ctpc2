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
print "testing start"
print("---")

local pk = ctp.position_keeper()

function position()
    trader:query_position()
    local finished = false
    while not finished do 
        local rsp = trader:recv()
        finished = pk:update(rsp)
    end
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

ctp.ctpc.ctp_trader_order_insert(trader.trader, "i2406", 0, 1, op_flg.Open)

while true do 
    local ptr, rsp = trader:fetch()
    print(ptr, rsp, ffi.string(rsp.desc))
    if ffi.string(rsp.desc) == "CThostFtdcTradeField" then 
        position()
        break 
    end
end



os.exit(1)