-- jit.off(true, true)

local ctp = require "lctp2"
local ffi = ctp.ffi
local uv = require "luv"

-- ctp.log_set_level("LOG_ERROR")
ctp.log_set_level("LOG_DEBUG")

local server = ctp.servers.trader["openctp"] 

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

function update_position_info()

trader:query_position()

local finished = false
while not finished do 
    local rsp = trader:recv()
    if rsp.last == 1 then finished = true end

    -- check NULL pointer 
    if rsp.field ~= nil then 
        local pos = ffi.new("struct CThostFtdcInvestorPositionField *", rsp.field)
        ctp.ctpc.ctp_position_keeper_update(pk, pos, rsp.last)

        -- print(
        --     "entry:",
        --     ffi.string(pos.TradingDay),
        --     ffi.string(pos.InvestorID),
        --     ffi.string(pos.ExchangeID),
        --     ffi.string(pos.InstrumentID),
        --     pos.PosiDirection,
        --     pos.YdPosition,
        --     pos.Position - pos.YdPosition,
        --     pos.Position
        -- )
    end
end

end

update_position_info()

print("try local copy")

function positions()
    local pos = ctp.ctpc.ctp_position_keeper_localcopy(pk)
    local p = pos
    while p ~= nil do 
        print(ffi.string(p.field.TradingDay), 
        ffi.string(p.field.InstrumentID), 
        p.field.YdPosition,
        p.field.Position - p.field.YdPosition,
        p.field.Position,
        p.field.PosiDirection)
        p = p.nxt
    end
end

positions()

-- 
print("try order insert")

-- ctp.ctpc.ctp_trader_order_insert(trader.trader, "cu2406", 0, 1, 1)
-- ctp.ctpc.ctp_trader_order_insert(trader.trader, "cu2406", 0, -1, -1)
ctp.ctpc.ctp_trader_order_insert(trader.trader, "au2406", 0, 1, -1)
ctp.ctpc.ctp_trader_order_insert(trader.trader, "au2406", 0, -1, -1)


while true do 
    -- update_position_info()
    uv.sleep(1000)    
end


os.exit(1)