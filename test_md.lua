local ctp = require "lctp2"
local ffi = ctp.ffi
local inspect = require "inspect"

local servers = {
    md = {
        ["sim"] = { front_addr =  'tcp://121.37.80.177:20004', broker = "7090", user = "7572" },
        ["openctp"] = { front_addr =  'tcp://121.37.80.177:20004', broker = "7090", user = "7572" },
        ["gtja-1"] = { front_addr =  "tcp://180.169.75.18:61213", broker = "7090", user = "85194065" }
    },
    trader = {
        ["openctp-7x24"] = {
            front_addr = "tcp://121.37.80.177:20002", 
            broker = "7090", 
            user = "7572", 
            pass = "123456", 
            app_id = "client_tara_060315", 
            auth_code = "20221011TARA000",
        },
        ["openctp"] = {
            front_addr = "tcp://121.37.90.193:20002", 
            broker = "7090", 
            user = "7572", 
            pass = "123456", 
            app_id = "client_tara_060315", 
            auth_code = "20221011TARA000",
        }
    }
}

local collector = ctp.new_collector(ctp.servers.md["gtja-1"])
-- print("cond", collector.md.c)
-- -- test conditional signaling
-- collector:cond(collector.md.c)
collector:subscribe({ "IF2501" })
collector:start()

print("---")

local i = 0

local accum_time = 0

while true do 
    local tick = collector:recv()

    local t0 = os.clock()
    tick = ctp.totable(tick)
    local t1 = os.clock()
    accum_time = accum_time + (t1 - t0)
    print(accum_time)

    -- print(inspect(tick))

    i = i + 1

    if i > 100 then 
        break 
    end
    -- print(ffi.string(tick.ActionDay), tick.LastPrice)
end

print("avg", accum_time / i)