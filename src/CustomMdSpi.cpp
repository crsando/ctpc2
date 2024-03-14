#include <iostream>
#include <fstream>
#include "malloc.h"
#include "string.h"
#include "time.h"
#include "CustomMdSpi.h"

extern "C" {
	#include "log.h"
}
// 连接成功应答
void CustomMdSpi::OnFrontConnected()
{
	log_info("OnFrontConnected | %s", this->_md->front_addr);
	this->_md->connected = 1;
	// 开始登录
	CThostFtdcReqUserLoginField loginReq;
	memset(&loginReq, 0, sizeof(loginReq));
	strcpy(loginReq.BrokerID, this->_md->broker);
	strcpy(loginReq.UserID, this->_md->user);
	// strcpy(loginReq.Password, this->_md->password);
	static int requestID = 0; // 请求编号
	int rt = g_pMdUserApi->ReqUserLogin(&loginReq, requestID);
    // int rt = ((CThostFtdcMdApi *)(this->_md->_api))->ReqUserLogin(&loginReq, 0);
}

// 断开连接通知
void CustomMdSpi::OnFrontDisconnected(int nReason)
{
	this->_md->connected = 0;
	log_info("OnFrontDisconnected | Error: %d", nReason);
}

// 心跳超时警告
void CustomMdSpi::OnHeartBeatWarning(int nTimeLapse)
{
	this->_md->connected = 0;
	log_info("OnHeartBeatWarning | nTimeLapse: %d", nTimeLapse);
}

// 登录应答
void CustomMdSpi::OnRspUserLogin(
	CThostFtdcRspUserLoginField *pRspUserLogin, 
	CThostFtdcRspInfoField *pRspInfo, 
	int nRequestID, 
	bool bIsLast)
{
	bool bResult = pRspInfo && (pRspInfo->ErrorID != 0);
	if (!bResult)
	{
		this->_md->connected = 2;
		log_info("OnRspUserLogin | Success | BrokerID:%s | UserID:%s", this->_md->broker, this->_md->user);
		// 开始订阅行情
		// int rt = g_pMdUserApi->SubscribeMarketData(g_pInstrumentID, instrumentNum);
        int i;
        log_debug("OnRspUserLogin | SubscribeMarketData | symbols_num %d", this->_md->symbols_num);
        for(i = 0; i < this->_md->symbols_num; i++) {
            log_debug("OnRspUserLogin | SubscribeMarketData | %2i | %s", i, (this->_md->symbols)[i]);
        }
		int rt = g_pMdUserApi->SubscribeMarketData(this->_md->symbols, this->_md->symbols_num);

		if (!rt)
		{
			this->_md->connected = 3;
			log_info("OnRspUserLogin | SubscribeMarketData | Success");
		}
	}
	else
		log_info("OnRspUserLogin | Fail | ErrorID:%d", pRspInfo->ErrorID);
}

// 登出应答
void CustomMdSpi::OnRspUserLogout(
	CThostFtdcUserLogoutField *pUserLogout,
	CThostFtdcRspInfoField *pRspInfo, 
	int nRequestID, 
	bool bIsLast)
{
	bool bResult = pRspInfo && (pRspInfo->ErrorID != 0);
	if (!bResult)
	{
		log_info("OnRspUserLogout | Success");
	}
	else
		log_info("OnRspUserLogout | Fail | ErrorID:%d", pRspInfo->ErrorID);
}

// 错误通知
void CustomMdSpi::OnRspError(CThostFtdcRspInfoField *pRspInfo, int nRequestID, bool bIsLast)
{
	bool bResult = pRspInfo && (pRspInfo->ErrorID != 0);
	if (bResult)
		log_info("OnRspError | ErrorID:%d | ErrorMsg", pRspInfo->ErrorID, pRspInfo->ErrorMsg);
}

// 订阅行情应答
void CustomMdSpi::OnRspSubMarketData(
	CThostFtdcSpecificInstrumentField *pSpecificInstrument, 
	CThostFtdcRspInfoField *pRspInfo, 
	int nRequestID, 
	bool bIsLast)
{
    log_debug("OnRspSubMarketData | %s", pSpecificInstrument->InstrumentID);
	bool bResult = pRspInfo && (pRspInfo->ErrorID != 0);
	if (bResult)
		log_info("OnRspError | ErrorID:%d | ErrorMsg", pRspInfo->ErrorID, pRspInfo->ErrorMsg);
}

// 取消订阅行情应答
void CustomMdSpi::OnRspUnSubMarketData(
	CThostFtdcSpecificInstrumentField *pSpecificInstrument, 
	CThostFtdcRspInfoField *pRspInfo,
	int nRequestID, 
	bool bIsLast)
{
}

// 订阅询价应答
void CustomMdSpi::OnRspSubForQuoteRsp(
	CThostFtdcSpecificInstrumentField *pSpecificInstrument,
	CThostFtdcRspInfoField *pRspInfo,
	int nRequestID,
	bool bIsLast)
{
	bool bResult = pRspInfo && (pRspInfo->ErrorID != 0);
	if (!bResult)
	{
		log_info("OnRspSubForQuoteRsp | Success | InstrumentID:%s", pSpecificInstrument->InstrumentID);
	}
	else
		log_info("OnRspSubForQuoteRsp | Fail | ErrorID:%d", pRspInfo->ErrorID);
}

// 取消订阅询价应答
void CustomMdSpi::OnRspUnSubForQuoteRsp(CThostFtdcSpecificInstrumentField *pSpecificInstrument, CThostFtdcRspInfoField *pRspInfo, int nRequestID, bool bIsLast)
{
	bool bResult = pRspInfo && (pRspInfo->ErrorID != 0);
	if (!bResult)
	{
		log_info("OnRspUnSubForQuoteRsp | Success | InstrumentID:%s", pSpecificInstrument->InstrumentID);
	}
	else
		log_info("OnRspUnSubForQuoteRsp | Fail | ErrorID:%d", pRspInfo->ErrorID);
}

// 行情详情通知
void CustomMdSpi::OnRtnDepthMarketData(CThostFtdcDepthMarketDataField *pDepthMarketData)
{
	log_debug("OnRtnDepthMarketData | InstrumentID:%s | LastPrice:%lf", pDepthMarketData->InstrumentID, pDepthMarketData->LastPrice);
	// clock_t start, end;

	// start = clock();
	// if(this->_md->_on_tick) {
	// 	(*(this->_md->_on_tick))(pDepthMarketData);
	// }

	CThostFtdcDepthMarketDataField * data = (CThostFtdcDepthMarketDataField *)malloc(sizeof(CThostFtdcDepthMarketDataField));
	memcpy(data, pDepthMarketData, sizeof(CThostFtdcDepthMarketDataField));

	ctp_md_send(this->_md, (void*)data);

	// end = clock();

	// double time_taken = 1000 * double(end - start) / double(CLOCKS_PER_SEC); // milliseconds
	// log_info("OnRtnDepthMarketData | time_taken: %lf millisecs", time_taken);
}

// 询价详情通知
void CustomMdSpi::OnRtnForQuoteRsp(CThostFtdcForQuoteRspField *pForQuoteRsp)
{
}