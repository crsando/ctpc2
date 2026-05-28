local inspect = require "inspect"
local service = require "lservice3".input(...)
local config = service.config
local ctp = require "lctp2"

local trader_id = nil

-- local server = {
--     front_addr = "tcp://trading.openctp.cn:30001",
--     broker = "9999", 
--     user = "7572", 
--     pass = "123456", 
--     app_id = "client_tara_231031", 
--     auth_code = '20231101ZHOUYH01',
-- }

local function boot()
    ctp.log_debug("booting root")
    assert(config.symbol, "no symbol provided")
    trader_id = service.spawn { name = "trader", source = "@services/ctp_trader.lua", config = { account = server } }
    local rsp = service.call(trader_id, "start") -- blocking, until trader starts

    ctp.log_debug("start result", rsp)
end


local function test_trader_query_queue()
    assert(trader_id)
    service.send(trader_id, "query_account")
    service.send(trader_id, "query_account")
    service.send(trader_id, "query_instrument", "IF2607")
    service.send(trader_id, "query_account")
end

local function test() 
    service.call(trader_id, "test")
end

local S = {}

function S.boot()
    boot()
    test()
    service.send(0, "quit")
end

function S.quit()
    ctp.log_debug("root is quiting")
    service.send(trader_id, "quit")
    service.quit()
end

return service.dispatch(S)