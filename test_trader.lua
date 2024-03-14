-- jit.off(true, true)

local ctp = require "lctp2"
local ffi = ctp.ffi
local uv = require "luv"

-- ctp.log_set_level("LOG_ERROR")
ctp.log_set_level("LOG_DEBUG")

local server = {
            front_addr = "tcp://180.169.75.18:61205",
            broker = "7090", 
            user = "85194065", 
            pass = "bE19930706",
            app_id = "client_tara_060315", 
            auth_code = '20221011TARA0001',
        }

-- openctp
-- local server = ctp.servers.trader["openctp"] 

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


local pk = ctp.ctpc.ctp_position_keeper_new()

trader:query_position()

local finished = false
while not finished do 
    local rsp = trader:recv()
    print(rsp.last, rsp.last == 1)
    if rsp.last == 1 then finished = true end

    -- check NULL pointer 
    if rsp.field ~= nil then 
        local pos = ffi.new("struct CThostFtdcInvestorPositionField *", rsp.field)
        ctp.ctpc.ctp_position_keeper_update(pk, pos, rsp.last)

        print(
            ffi.string(pos.TradingDay),
            ffi.string(pos.InvestorID),
            ffi.string(pos.ExchangeID),
            ffi.string(pos.InstrumentID),
            pos.Position
        )
    end
end

print("try local copy")

local pos = ctp.ctpc.ctp_position_keeper_localcopy(pk)
local p = pos
while p ~= nil do 
    print(ffi.string(p.field.TradingDay), ffi.string(p.field.InstrumentID), p.field.Position)
    p = p.nxt
end


os.exit(1)