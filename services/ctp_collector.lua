local inspect = require "inspect"
local ctp = require "lctp2"
ctp.log_set_level("LOG_DEBUG")

local service = require "lservice3" .input(...)
local config = service.config; do 
        -- config.server = { front_addr =  "tcp://180.169.75.18:61213", broker = "7090", user = "85506493" }
        assert(config.server, "no config.server")
        config.auto_disconnect = true
    end

if config.auto_disconnect then 
    local myid = service.get_id()
    scheduler:daily("08:45:00", function() service.send(myid, "start") end)
    scheduler:daily("17:00:00", function() service.send(myid, "stop") end)
    scheduler:daily("20:45:00", function() service.send(myid, "start") end)
    scheduler:daily("04:00:00", function() service.send(myid, "stop") end)
end

local S = {}
local collector = ctp.new_collector(config.server)

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
        service.sleep(50)
    end

    -- 这个地方我们不做subscribe
    return 1
end

function S.stop()
    ctp.log_debug("S.stop | is_ready: %s", collector:is_ready() and "true" or "false")
    collector:stop()
end

function S.quit()
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

local function on_tick(tick)
    quotes[tick.InstrumentID] = tick.LastPrice
    -- ctp.log_debug("on_tick | %s | %f", tick.InstrumentID, tick.LastPrice)
    -- print("on_tick", inspect(tick))
end

function S.get_quotes()
    return quotes
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