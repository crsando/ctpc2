local inspect = require "inspect"
local ctp = require "lctp2"
ctp.log_set_level("LOG_DEBUG")

local service = require "lservice3" .input(...)
local config = service.config; do 
        config.server = { front_addr =  "tcp://180.169.75.18:61213", broker = "7090", user = "85506493" }
        assert(config.server, "no config.server")
        config.symbol = "sc2609"
        assert(config.symbol, "no config.symbol")
    end

local S = {}
local collector = ctp.new_collector(config.server)

function S.start()
    collector:subscribe({ config.symbol })
    collector:async(service.get_async())
    collector:start()
end

local function on_tick(tick)
    print("on_tick", inspect(tick))
end

function service.on_idle()
    local tick
    while true do 
        tick = collector:recv(false) -- non-blocking
        if tick == nil then 
            break 
        end
        if tick ~= nil then 
            on_tick(tick)
        end
    end
end

return service.dispatch(S)