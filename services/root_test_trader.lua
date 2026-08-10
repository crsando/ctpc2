local inspect = require "inspect"
local service = require "lservice3".input(...)
local config = service.config
local ctp = require "lctp2"

local trader_id = nil

local function boot()
    ctp.log_debug("booting root")
    assert(config.symbol, "no symbol provided")
    service.spawn { name = "collector", source = "@services/ctp_collector.lua", config = { symbol = config.symbol } }
    service.call("collector", "start")

    
    --[[
    service.spawn { name = "trader", source = "@services/ctp_trader.lua", config = config }
    local rsp = service.call("trader", "start") -- blocking, until trader starts

    ctp.log_debug("start result", rsp)
    test_trader_query()
    ]]
end


local function test_trader_query()
    local err, rst = service.call("trader", "query_account")
    ctp.log_info("query_account: %s", inspect(rst))
    local err, rst = service.call("trader", "query_instrument", "IM2703")
    ctp.log_info("query_instrument: %s", inspect(rst))
    local err, rst = service.call("trader", "query_position")
    ctp.log_info("query_position: %s", inspect(rst))
end

local function test() 
    -- service.call(trader_id, "test")
    service.call(trader_id, "test_1")
end

local S = {}

function S.boot()
    boot()
    -- test()
    -- service.send(0, "quit")
end

function S.quit()
    ctp.log_debug("root is quiting")
    service.send("trader", "quit")
    service.quit()
end

return service.dispatch(S)