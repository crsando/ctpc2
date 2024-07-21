local ctp = require "lctp2"
local ffi = ctp.ffi
local inspect = require "inspect"

local collector = ctp.new_collector(ctp.servers.md["openctp"])
print("cond", collector.md.c)
-- test conditional signaling
collector:cond(collector.md.c)
collector:subscribe({ "cu2409" })
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