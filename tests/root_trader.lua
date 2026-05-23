local inspect = require "inspect"
local service = require "lservice2".input(...)
local config = service.config
local ctp = require "lctp2"

local trader_id = nil

local server = {
    front_addr = "tcp://trading.openctp.cn:30001",
    broker = "9999", 
    user = "7572", 
    pass = "123456", 
    app_id = "client_tara_231031", 
    auth_code = '20231101ZHOUYH01',
}

local trader_id = nil

local function boot()
    print("root booting")
    assert(config.symbol, "no symbol provided")

    print("start ctp trader")
    trader_id = service.spawn { source = "@tests/ctp_trader.lua", config = { account = server } }
    local rsp = service.call(trader_id, "start") -- blocking, until trader starts

    print("start result", rsp)
end

local function test() 
    print("begin test", trader_id)
    local rst = service.call(trader_id, "query_position")
    print("position info", inspect(rst))

    local rst = service.call(trader_id, "query_account")
    print("account info", inspect(rst))
    

    local rst = service.call(trader_id, "query_instrument", "IF2607")
    print("instrument info", inspect(rst))

    -- local rst = service.call(trader_id, "order_insert", "BTC", 99999999, 1, nil)
    -- local rst = service.send(trader_id, "trade", "BTC", 1, 1, nil)
    -- local rst = service.call(trader_id, "trade", "cu2409", 0, 1, nil)
    -- print("traded", inspect(rst))
    -- local rst = service.call(trader_id, "start")

    -- local rst = service.send(trader_id, "query_order")
    -- local rst = service.send(trader_id, "query_account")
    -- print(inspect(rst))
end

local function test_cancel()
    local rst = service.call(trader_id, "query_order")
    print("Num of orders", #rst)
    for _, order in ipairs(rst) do 
        if order and order.InstrumentID then
            print("order: ", order.ExchangeID, order.OrderSysID, order.OrderStatus, order.LimitPrice, order.VolumeTraded)
            if (order.OrderStatus ~= ctp.THOST_FTDC_OST_Canceled) and (order.OrderStatus ~= ctp.THOST_FTDC_OST_AllTraded) then 
                -- print("order: ", order.FrontID, order.SessionID, order.OrderRef, order.InstrumentID, order.OrderStatus, order.InsertDate, order.InsertTime)
                print("to cancel", order.OrderSysID)
                service.call(trader_id, "cancel", order)
                return 0
            end

            -- if (order.OrderStatus ~= ctp.THOST_FTDC_OST_Canceled) and (order.OrderStatus ~= ctp.THOST_FTDC_OST_AllTraded) then 
            --     service.call(trader_id, "cancel", order)
            -- end
        end
    end
    -- print("query_order", inspect(rst))
end

local S = {}

function S.boot()
    boot()
    test()
end

function S.quit()
    for _, id in ipairs{collector_id, trader_id, bot_id} do 
        service.send(id, "quit")
    end
end

service.dispatch(S)