#include <iostream>
#include <time.h>
#include <thread>
#include <chrono>
#include "string.h"
#include "malloc.h"
#include "CustomTradeSpi.h"

extern "C" {
	#include "log.h"
	#include "position.h"
}

#define _trader_api ((CThostFtdcTraderApi *)(this->_trader->_api))
#define _trader_spi ((CThostFtdcTraderApi *)(this->_trader->_spi))

void CustomTradeSpi::OnFrontConnected()
{
	log_info("OnFrontConnected | FrontAddr:%s", this->_trader->front_addr);
	this->_trader->connected = 1;
	this->reqAuthenticate();
}

int CustomTradeSpi::reqAuthenticate() {
	CThostFtdcReqAuthenticateField field;
	memset(&field, 0, sizeof(field));
	strcpy(field.BrokerID, this->_trader->broker);
	strcpy(field.UserID, this->_trader->user);
	strcpy(field.AppID, this->_trader->app_id);
	strcpy(field.AuthCode, this->_trader->auth_code);
	CTP_TRADER_REQ(this->_trader, Authenticate, &field);
}

void CustomTradeSpi::OnRspAuthenticate(CThostFtdcRspAuthenticateField *pRspAuthenticateField, CThostFtdcRspInfoField *pRspInfo, int nRequestID, bool bIsLast)
{
	if (!isErrorRspInfo(pRspInfo)) {
		log_info("OnRspAuthenticate | Success | AppID:%s | AuthCode:%s", this->_trader->app_id, this->_trader->auth_code);
		this->_trader->connected = 2;
		reqUserLogin();
	}
	else
		log_info("OnRspAuthenticate | Fail | AppID:%s | AuthCode:%s", this->_trader->app_id, this->_trader->auth_code);
}

void CustomTradeSpi::OnRspUserLogin(
	CThostFtdcRspUserLoginField *pRspUserLogin,
	CThostFtdcRspInfoField *pRspInfo,
	int nRequestID,
	bool bIsLast)
{
	if (!isErrorRspInfo(pRspInfo))
	{
		this->_trader->connected = 3;
		this->loginFlag = true;
		log_info("OnRspUserLogin | Success | BrokerID:%s | UserID:%s", pRspUserLogin->BrokerID, pRspUserLogin->UserID);
		log_info("OnRspUserLogin | FrontID: %d | SessionID: %d | MaxOrderRef: %s",
			pRspUserLogin->FrontID, pRspUserLogin->SessionID, pRspUserLogin->MaxOrderRef);


		// session info
		this->_trader->front_id = pRspUserLogin->FrontID;
		this->_trader->session_id = pRspUserLogin->SessionID;
		strcpy(this->_trader->max_order_ref, pRspUserLogin->MaxOrderRef);
		strcpy(this->_trader->lst_order_ref, pRspUserLogin->MaxOrderRef);

		// 投资者结算结果确认
		reqSettlementInfoConfirm();
	}
	else
		log_info("OnRspUserLogin | Fail | BrokerID:%s | UserID:%s", this->_trader->broker, this->_trader->user);
}

void CustomTradeSpi::OnRspError(CThostFtdcRspInfoField *pRspInfo, int nRequestID, bool bIsLast)
{
	log_info("OnRspError | %d | %s", pRspInfo->ErrorID, pRspInfo->ErrorMsg);
}

void CustomTradeSpi::OnFrontDisconnected(int nReason)
{
	log_info("OnFrontDisconnected | FrontAddr:%s | nReason:%d", this->_trader->front_addr, nReason);
}

void CustomTradeSpi::OnHeartBeatWarning(int nTimeLapse)
{
	log_info("OnHeartBeatWarning");
}

void CustomTradeSpi::OnRspUserLogout(
	CThostFtdcUserLogoutField *pUserLogout,
	CThostFtdcRspInfoField *pRspInfo,
	int nRequestID,
	bool bIsLast)
{
	if (!isErrorRspInfo(pRspInfo))
	{
		loginFlag = false; // 登出就不能再交易了 
		log_info("OnRspUserLogout | Success | BrokerID:%s | UserID:%s", this->_trader->broker, this->_trader->user);
	}
}


#define ON_RSP_THEN_SEND_SIMPLE(tp) \
	do { \
		ctp_rsp_t * rsp = (ctp_rsp_t*)malloc(sizeof(ctp_rsp_t)); \
		memset(rsp, 0, sizeof(ctp_rsp_t)); \
		if(pField) { \
			strcpy(rsp->desc, #tp); \
			rsp->field = (void *)malloc(sizeof(tp)); \
			memcpy(rsp->field, pField, sizeof(tp)); \
			rsp->size = sizeof(tp); \
		} \
		else { \
			log_debug("pField == NULL"); \
			strcpy(rsp->desc, "empty"); \
			rsp->field = NULL; \
			rsp->size = 0; \
		} \
		rsp->req_id = -1; \
		rsp->last = 1; \
		log_debug("ON_RSP_THEN_SEND : struct %s | last %d", rsp->desc, rsp->last); \
		ctp_trader_send(this->_trader, rsp); \
	} while(0)

#define ON_RSP_THEN_SEND(tp) \
	do { \
		ctp_rsp_t * rsp = (ctp_rsp_t*)malloc(sizeof(ctp_rsp_t)); \
		memset(rsp, 0, sizeof(ctp_rsp_t)); \
        strcpy(rsp->desc, #tp); \
		if(pField) { \
			rsp->field = (void *)malloc(sizeof(tp)); \
			memcpy(rsp->field, pField, sizeof(tp)); \
			rsp->size = sizeof(tp); \
		} \
		else { \
			log_debug("pField == NULL"); \
			rsp->field = NULL; \
			rsp->size = 0; \
		} \
        rsp->rsp_info = (void *)malloc(sizeof(CThostFtdcRspInfoField)); \
        memcpy(rsp->rsp_info, pRspInfo, sizeof(CThostFtdcRspInfoField)); \
		rsp->req_id = nRequestID; \
		rsp->last = (bIsLast ? 1 : 0); \
		log_debug("ON_RSP_THEN_SEND : struct %s | last %d", rsp->desc, rsp->last); \
		ctp_trader_send(this->_trader, rsp); \
	} while(0)


#define CUSTOM_ON(fn, tp) \
void CustomTradeSpi::fn (tp * pField, CThostFtdcRspInfoField * pRspInfo, int nRequestID, bool bIsLast)  { \
    log_debug("%s | nRequestID : %d | isLast: %d", #fn, nRequestID, bIsLast ? 1 : 0); \
	if(pRspInfo && (pRspInfo->ErrorID != 0)) { \
		log_debug("%s | ErrorRsp | %d | %s", #fn, pRspInfo->ErrorID, pRspInfo->ErrorMsg); \
    } \
	do { \
		ctp_rsp_t * rsp = (ctp_rsp_t*)malloc(sizeof(ctp_rsp_t)); \
		memset(rsp, 0, sizeof(ctp_rsp_t)); \
		rsp->req_id = nRequestID; \
		rsp->last = (bIsLast ? 1 : 0); \
        strcpy(rsp->desc, #tp); \
        strcpy(rsp->field_name, #tp); \
		if(pField) { \
			rsp->field = (void *)malloc(sizeof(tp)); \
			memcpy(rsp->field, pField, sizeof(tp)); \
			rsp->size = sizeof(tp); \
		} \
		else { \
			rsp->field = NULL; \
			rsp->size = 0; \
		} \
        if(pRspInfo) { \
            rsp->rsp_info = (void *)malloc(sizeof(CThostFtdcRspInfoField)); \
            memcpy(rsp->rsp_info, pRspInfo, sizeof(CThostFtdcRspInfoField)); \
        } \
		ctp_trader_send(this->_trader, rsp); \
	} while(0); \
}

ctp_rsp_t * pack_data(void * data, size_t size) {
	ctp_rsp_t * rsp = (ctp_rsp_t*)malloc(sizeof(ctp_rsp_t));
	memset(rsp, 0, sizeof(ctp_rsp_t));
	rsp->field = (void *)malloc(size);
	memcpy(rsp->field, data, size);
	rsp->size = size;
	return rsp;
}

void CustomTradeSpi::OnRspSettlementInfoConfirm(
	CThostFtdcSettlementInfoConfirmField * pField,
	CThostFtdcRspInfoField *pRspInfo,
	int nRequestID,
	bool bIsLast)
{
	if (!isErrorRspInfo(pRspInfo)) {
		this->_trader->connected = 4;
		log_info("OnRspSettlementInfoConfirm | Success | ConfirmDate:%s %s", pField->ConfirmDate, pField->ConfirmTime);
		// ON_RSP_THEN_SEND(CThostFtdcSettlementInfoConfirmField);

		ctp_rsp_t * rsp = pack_data(pField, sizeof(*pField));
		rsp->req_id = nRequestID;
		rsp->last = bIsLast ? 1 : 0;
		ctp_trader_send(this->_trader, rsp);
	}
	else {
		log_info("OnRspSettlementInfoConfirm | Failed", pRspInfo->ErrorID, pRspInfo->ErrorMsg);
	}
}

CUSTOM_ON(OnRspQryTradingAccount, CThostFtdcTradingAccountField);
CUSTOM_ON(OnRspQryInvestorPosition, CThostFtdcInvestorPositionField);
CUSTOM_ON(OnRspQryInstrument, CThostFtdcInstrumentField);

// void CustomTradeSpi::OnRspQryInstrument( CThostFtdcInstrumentField *pInstrument, CThostFtdcRspInfoField *pRspInfo, int nRequestID, bool bIsLast)
// {
// 	log_info("OnRspQryInstrument | %s | %s", pInstrument->ExchangeID, pInstrument->InstrumentID);
// }

// void CustomTradeSpi::OnRspQryTradingAccount( CThostFtdcTradingAccountField * pField, CThostFtdcRspInfoField *pRspInfo, int nRequestID, bool bIsLast)
// {
// 	if (!isErrorRspInfo(pRspInfo)) {
// 		log_info("OnRspQryTradingAccount | Succeed");
// 		ON_RSP_THEN_SEND(CThostFtdcTradingAccountField);
// 	}
// 	else {
// 		log_info("OnRspQryTradingAccount | Failed", pRspInfo->ErrorID, pRspInfo->ErrorMsg);
// 	}
// }

// void CustomTradeSpi::OnRspQryInvestorPosition(
// 	CThostFtdcInvestorPositionField *pField,
// 	CThostFtdcRspInfoField *pRspInfo,
// 	int nRequestID,
// 	bool bIsLast)
// {
// 	if (!isErrorRspInfo(pRspInfo)) {
// 		log_info("OnRspQryInvestorPosition | Succeed");
// 		ON_RSP_THEN_SEND(CThostFtdcInvestorPositionField);
// 	}
// 	else {
// 		log_info("OnRspQryInvestorPosition | Failed", pRspInfo->ErrorID, pRspInfo->ErrorMsg);
// 	}
// }

// void CustomTradeSpi::OnRspQryDepthMarketData(
// 	CThostFtdcDepthMarketDataField *pField,
// 	CThostFtdcRspInfoField *pRspInfo,
// 	int nRequestID,
// 	bool bIsLast)
// {
// 	if (!isErrorRspInfo(pRspInfo)) {
// 		log_info("OnRspQryDepthMarketData | Succeed | %s | %lf", pField->InstrumentID, pField->LastPrice);
// 		ON_RSP_THEN_SEND(CThostFtdcDepthMarketDataField);
// 	}
// 	else {
// 		log_info("OnRspQryDepthMarketData | Failed", pRspInfo->ErrorID, pRspInfo->ErrorMsg);
// 	}
// }

void CustomTradeSpi::OnRspOrderInsert(
	CThostFtdcInputOrderField *pField, 
	CThostFtdcRspInfoField *pRspInfo,
	int nRequestID,
	bool bIsLast)
{
	if (!isErrorRspInfo(pRspInfo)) {
		log_info("OnRspOrderInsert | %s | %d | %s", pField->OrderRef);
		ON_RSP_THEN_SEND(CThostFtdcInputOrderField);
	}
	else {
		log_info("OnRspOrderInsert | Failed", pRspInfo->ErrorID, pRspInfo->ErrorMsg);
	}
}

void CustomTradeSpi::OnRspOrderAction(
	CThostFtdcInputOrderActionField *pInputOrderAction,
	CThostFtdcRspInfoField *pRspInfo,
	int nRequestID,
	bool bIsLast)
{
	if (!isErrorRspInfo(pRspInfo)) { 
		log_info("OnRspOrderAction | %s | %s | %d | %s", 
			pInputOrderAction->ExchangeID, 
			pInputOrderAction->OrderSysID, 
			pRspInfo->ErrorID, pRspInfo->ErrorMsg);
	}
}

void CustomTradeSpi::OnRtnOrder(CThostFtdcOrderField *pField)
{
	// FrontID + SessionID + OrderRef
	int front_id = this->_trader->front_id;
	int session_id = this->_trader->session_id;
	strcpy(this->_trader->lst_order_ref, pField->OrderRef);

	// ExchangeID + OrderSysID
	// log_info("OnRtnOrder | %s | %s | %s | Info | %s | %lf | %d | %d | Status | %c | %c", 
	log_info("OnRtnOrder | Ref: %d+%d+%s | Sys: %s+%s | %s | %lf | #:%d | #Traded: %d | Status | %c | %c", 
			front_id,
			session_id,
			pField->OrderRef,

			pField->ExchangeID,
			pField->OrderSysID,

			pField->InstrumentID,
			pField->LimitPrice,
			pField->VolumeTotal,
			pField->VolumeTraded,

			pField->OrderSubmitStatus,
			pField->OrderStatus
		);
	ON_RSP_THEN_SEND_SIMPLE(CThostFtdcOrderField);
}

void CustomTradeSpi::OnRtnTrade(CThostFtdcTradeField *pField)
{
	log_info("OnRtnTrade | Sys: %s+%s | %s | Time: %s %s | %lf | %d | %c",
			pField->ExchangeID,
			pField->OrderSysID,

			pField->InstrumentID,
			pField->TradeDate,
			pField->TradeTime,
			pField->Price,
			pField->Volume,
			pField->Direction
		);
	ON_RSP_THEN_SEND_SIMPLE(CThostFtdcTradeField);
}

bool CustomTradeSpi::isErrorRspInfo(CThostFtdcRspInfoField *pRspInfo)
{
	bool bResult = pRspInfo && (pRspInfo->ErrorID != 0);
	if (bResult)
		log_info("isErrorRspInfo | %d | %s", pRspInfo->ErrorID, pRspInfo->ErrorMsg);
	return bResult;
}

int CustomTradeSpi::reqUserLogin()
{
	log_info("reqUserLogin | %s | %s | %s", this->_trader->broker, this->_trader->user, this->_trader->password);
	CThostFtdcReqUserLoginField loginReq;
	memset(&loginReq, 0, sizeof(loginReq));
	strcpy(loginReq.BrokerID, this->_trader->broker);
	strcpy(loginReq.UserID, this->_trader->user);
	strcpy(loginReq.Password, this->_trader->password);
	CTP_TRADER_REQ(this->_trader, UserLogin, &loginReq);
}

int CustomTradeSpi::reqUserLogout()
{
	CThostFtdcUserLogoutField logoutReq;
	memset(&logoutReq, 0, sizeof(logoutReq));
	strcpy(logoutReq.BrokerID, this->_trader->broker);
	strcpy(logoutReq.UserID, this->_trader->user);
	CTP_TRADER_REQ(this->_trader, UserLogout, &logoutReq);
}


int CustomTradeSpi::reqSettlementInfoConfirm()
{
	log_info("reqSettlementInfoConfirm");
	CThostFtdcSettlementInfoConfirmField settlementConfirmReq;
	memset(&settlementConfirmReq, 0, sizeof(settlementConfirmReq));
	strcpy(settlementConfirmReq.BrokerID, this->_trader->broker);
	strcpy(settlementConfirmReq.InvestorID, this->_trader->user);

	CTP_TRADER_REQ(this->_trader, SettlementInfoConfirm, &settlementConfirmReq);
}

#undef _trader_api
#undef _trader_spi