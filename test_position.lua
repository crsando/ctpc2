-- jit.off(true, true)
local inspect = require "inspect"
local seri = require "lseri"
local service = require "lservice"
service.serializer = seri
local ffi = service.ffi

local name, config, pool = service.input(seri.unpack_remove, ...)

local ctp = require "lctp2"
local ffi = ctp.ffi


ctp.log_set_level("LOG_DEBUG")

local pk = ctp.position_keeper()
local account = {}

local server = {
            front_addr = "tcp://180.169.75.18:61205",
            broker = "7090", 
            user = "85194065", 
            pass = nil, 
            app_id = "client_tara_060315", 
            auth_code = '20221011TARA0001',
        }

function cast_field(rsp)
    if rsp.field == nil then return nil end
    assert(rsp.desc ~= nil)
    local ptr_type = "struct " .. ffi.string(rsp.desc) .. " * "
    local ptr = assert(ffi.cast(ptr_type, rsp.field))
    if ptr ~= nil then 
        ffi.gc(ptr, ffi.C.free)
    end
    return ptr
end


-- handle trader response
local handler = {}

function handler.CThostFtdcTradingAccountField(rsp)
    local field = cast_field(rsp)
    local cols = { "Balance", "Available", "PositionProfit" }
    for _, k in ipairs(cols) do 
        account[k] = tonumber(field[k])
    end
end
function handler.CThostFtdcInvestorPositionField(rsp)
    pk:update(rsp)
end


function process_message(trader, criterion)
    local flg = false
    while not flg do 
        local rsp = trader:recv()
        print("process message | desc ", ffi.string(rsp.desc), "islast", rsp.last)
        local h = handler[ffi.string(rsp.desc)] or function() print("no handler for ", ffi.string(rsp.desc)) end
        h(rsp) 

        flg = criterion(rsp)
        ctp.ctpc.ctp_rsp_free(rsp)
    end
    print("end of process message")
end

-- local server = ctp.servers.trader["openctp-7x24"] 

-- prompt
if not server.pass then 
    io.write("user: ", server.user, "\n")
    io.write("password: ")
    server.pass = io.read("*line")
end

local trader = ctp.new_trader(server):start()

-- remove 

print("---")
print "testing start"
print("---")

-- local u, o = pcall(function () return trader.trader.session_id end)
-- print(u, o)

-- os.exit(1)

function balance()
    trader:query_account()
    process_message(trader, function(rsp)
            return ffi.string(rsp.desc) == "CThostFtdcTradingAccountField"
        end)

    print("account", inspect(account))

    pool:send("bot", {
        label = "account",
        body = {
            user = server.user,
            info = account,
        }
    })
end


function position()
    trader:query_position()
    process_message(trader, function(rsp) 
            return (ffi.string(rsp.desc) == "CThostFtdcInvestorPositionField") and 
                (rsp.last == 1)
        end)
    local t = pk:table()

    pool:send("bot", {
        label = "position", 
        body = {
            user = server.user,        
            info = t
        } 
    })

    print("position", inspect(t))
end

balance()
position()