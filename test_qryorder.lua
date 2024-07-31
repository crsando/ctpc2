local inspect = require "inspect"

local ctp = require "lctp2"
local ffi = ctp.ffi

-- ctp.log_set_level("LOG_ERROR")
ctp.log_set_level("LOG_DEBUG")

local server = ctp.servers.trader["openctp-7x24"] 
local trader = ctp.new_trader(server):start(true)

--[[
struct CThostFtdcQryOrderField
{
	///经纪公司代码
	TThostFtdcBrokerIDType	BrokerID;
	///投资者代码
	TThostFtdcInvestorIDType	InvestorID;
	///保留的无效字段
	TThostFtdcOldInstrumentIDType	reserve1;
	///交易所代码
	TThostFtdcExchangeIDType	ExchangeID;
	///报单编号
	TThostFtdcOrderSysIDType	OrderSysID;
	///开始时间
	TThostFtdcTimeType	InsertTimeStart;
	///结束时间
	TThostFtdcTimeType	InsertTimeEnd;
	///投资单元代码
	TThostFtdcInvestUnitIDType	InvestUnitID;
	///合约代码
	TThostFtdcInstrumentIDType	InstrumentID;
};
]]
ctp.ctpc.ctp_trader_query_order(trader.trader)

function process_until(hit)
    while true do 
        local rsp = trader:recv(true)
        rsp = ctp.cast_trader_rsp(rsp)
        if ffi.string(rsp.func_name) == hit then 
            print(inspect(rsp.field))

            if rsp.is_last == true then
                break 
            end
        end
    end

--[[
///查询报单操作
struct CThostFtdcQryOrderActionField
{
	///经纪公司代码
	TThostFtdcBrokerIDType	BrokerID;
	///投资者代码
	TThostFtdcInvestorIDType	InvestorID;
	///交易所代码
	TThostFtdcExchangeIDType	ExchangeID;
};]]


-- infinite loop
local uv = require "luv"

uv.new_signal():start("sigint", function(signal)
        print("on sigint, exit")
        uv.walk(function (handle) if not handle:is_closing() then handle:close() end end)
        os.exit(1)
    end)

uv.run()