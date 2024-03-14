local ctp = require "lctp2"
local ffi = ctp.ffi

local trader = ctp.new_trader(ctp.servers.trader["openctp"]):start()

print("---")

for i = 1, 10 do
    trader:query_account()
    local rsp = trader:recv()
    local act = ffi.cast("struct CThostFtdcTradingAccountField *", rsp.field)
    print(act.Balance)
end