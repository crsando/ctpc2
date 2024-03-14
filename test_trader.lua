local ctp = require "lctp2"
local ffi = ctp.ffi
local uv = require "luv"

local server = {
            front_addr = "tcp://180.169.75.18:61205",
            broker = "7090", 
            user = "85194065", 
            app_id = "client_tara_060315", 
            auth_code = '20221011TARA0001',
        }


-- prompt
io.write("user: ", server.user, "\n")
io.write("password: ")
server.pass = io.read("*line")

local trader = ctp.new_trader(server):start()

print("---")

for i = 1, 1 do
    trader:query_account()
    local rsp = trader:recv()
    local act = ffi.cast("struct CThostFtdcTradingAccountField *", rsp.field)
    print(act.Balance)
end


trader:query_position()


local finished = false
while not finished do 
    local rsp = trader:recv()
    if rsp.last == 1 then finished = true end

    local pos = ffi.cast("struct CThostFtdcInvestorPositionField *", rsp.field)

    print(
        ffi.string(pos.TradingDay),
        ffi.string(pos.InvestorID),
        ffi.string(pos.ExchangeID),
        ffi.string(pos.InstrumentID),
        pos.Position
    )
end