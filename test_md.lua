local ctp = require "lctp2"
local ffi = ctp.ffi

local collector = ctp.new_collector(ctp.servers.md["openctp"])
    :subscribe({ "cu2403" })
    :start()

print("---")

while true do 
    local tick = collector:recv()
    print(ffi.string(tick.ActionDay), tick.LastPrice)
end