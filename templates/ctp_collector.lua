local inspect = require "inspect"
local ctp = require "lctp2"
-- ctp.log_set_level("LOG_DEBUG")

local service = require "service"
local config = service.config; do 
        assert(config.server, "no config.server")
        config.auto_disconnect = true
    end

local S = {}
local collector = ctp.new_collector(config.server)
S._collector = collector -- expose

local quotes = {}

function S.start()
    ctp.log_debug("S.start | is_ready: %s", collector:is_ready() and "true" or "false")
    collector:async(service.get_async())
    collector:start()

    --
    -- wait for the collector to be ready
    --
    local ready = false
    while not ready do  
        ready = collector:is_ready()
        ctp.log_debug("is_ready: %s", ready and "true" or "false")
        service.sleep(500)
    end

    -- 这个地方我们不做subscribe
    return 1
end

function S.stop()
    ctp.log_debug("S.stop | is_ready: %s", collector:is_ready() and "true" or "false")
    collector:stop()
end

function S.quit()
    if collector then 
        collector:stop()
        collector = nil
    end
    service.quit()
end

function S.subscribe(symbols)
    if (type(symbols) == "string") then 
        symbols = { symbols }
    end

    collector:subscribe(symbols)
    return 1
end

function S.unsubscribe(symbols)
    if (type(symbols) == "string") then 
        symbols = { symbols }
    end

    collector:unsubscribe(symbols)
    return 1
end

function S.get_quotes()
    return quotes
end

-- default implementation, needs reload
function S.on_tick(tick)
    quotes[tick.InstrumentID] = tick.LastPrice
end

function service.on_idle()
    local tick
    while true do 
        tick = collector:recv(false) -- non-blocking
        if tick == nil then 
            break 
        end
        S.on_tick(tick)
    end
end

return S