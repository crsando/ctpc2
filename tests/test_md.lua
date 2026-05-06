local ctp = require "lctp2"
local ffi = ctp.ffi
local inspect = require "inspect"

local servers = {
    md = {
        ["sim"] = { front_addr =  'tcp://121.37.80.177:20004', broker = "7090", user = "7572" },
        ["openctp"] = { front_addr =  'tcp://121.37.80.177:20004', broker = "7090", user = "7572" },
        ["gtja-1"] = { front_addr =  "tcp://180.169.75.18:61213", broker = "7090", user = "85194065" },
        ["hy"] = {
            front_addr = "tcp://180.169.112.52:42213",
            broker = "1080", 
            user = "333307126", 
        },
        ["hy-sim"] = {
            front_addr = "tcp://101.230.79.235:32213"
            broker = "3070", 
            user = "333307126", 
        },
    },
}

local collector = ctp.new_collector(
    servers.md["hy-sim"]
)
collector:subscribe({ "IF2505" })
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