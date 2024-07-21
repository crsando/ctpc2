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

while true do 
    local tick = collector:recv()

    local o = ctp.totable(tick)
    print(inspect(o))

    print(ffi.string(tick.ActionDay), tick.LastPrice)
end