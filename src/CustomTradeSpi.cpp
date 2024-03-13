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


#define CTP_TRADER_ON_RSP(cmd, cf) \
void CustomTradeSpi::OnRsp ## cmd ## (cf * field, \
	CThostFtdcRspInfoField * pRspInfo, \
	int nRequestID, \
	bool bIsLast \
	) \
{ \
	if (!isErrorRspInfo(pRspInfo)) { \
		log_info("OnRsp%s | RequstID: %d | Success\n", #cmd, nRequestID); \
		if ( this->_trader->on_rsp ) { \
			this->_trader->on_rsp(#cmd, (field), pRspInfo, nRequestID, (bIsLast ? 1 : 0)); \
		} \
	} \
	else { \
		log_info("OnRsp%s | RequstID: %d | Failed | %s\n", # cmd, nRequestID, pRspInfo->ErrorMsg); \
	} \
} 

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

void CustomTradeSpi::OnRspSettlementInfoConfirm(
	CThostFtdcSettlementInfoConfirmField *pSettlementInfoConfirm,
	CThostFtdcRspInfoField *pRspInfo,
	int nRequestID,
	bool bIsLast)
{
	if (!isErrorRspInfo(pRspInfo))
	{
		this->_trader->connected = 4;
		log_info("OnRspSettlementInfoConfirm | Success | ConfirmDate:%s %s", pSettlementInfoConfirm->ConfirmDate, pSettlementInfoConfirm->ConfirmTime);
	}
	else {
		log_info("OnRspSettlementInfoConfirm | Failed", pRspInfo->ErrorID, pRspInfo->ErrorMsg);
	}
}

void CustomTradeSpi::OnRspQryInstrument( CThostFtdcInstrumentField *pInstrument, CThostFtdcRspInfoField *pRspInfo, int nRequestID, bool bIsLast)
{
	log_info("OnRspQryInstrument | %s | %s", pInstrument->ExchangeID, pInstrument->InstrumentID);
}

void CustomTradeSpi::OnRspQryTradingAccount( CThostFtdcTradingAccountField *pTradingAccount, CThostFtdcRspInfoField *pRspInfo, int nRequestID, bool bIsLast)
{
	ctp_rsp_t * rsp = (ctp_rsp_t*)malloc(sizeof(ctp_rsp_t));
	rsp->field = (void *)malloc(sizeof(CThostFtdcTradingAccountField));
	memcpy(rsp->field, pTradingAccount, sizeof(CThostFtdcTradingAccountField));
	rsp->info = (CThostFtdcRspInfoField*)malloc(sizeof(CThostFtdcRspInfoField));
	memcpy(rsp->info, pRspInfo);
	rsp->req_id = nRequestID;
	rsp->last = bIsLast ? 1 : 0;
	ctp_trader_send(this->_trader, rsp);
}

void CustomTradeSpi::OnRspQryInvestorPosition(
	CThostFtdcInvestorPositionField *pInvestorPosition,
	CThostFtdcRspInfoField *pRspInfo,
	int nRequestID,
	bool bIsLast)
{
}

void CustomTradeSpi::OnRspOrderInsert(
	CThostFtdcInputOrderField *pInputOrder, 
	CThostFtdcRspInfoField *pRspInfo,
	int nRequestID,
	bool bIsLast)
{
	log_info("OnRspOrderInsert | %s | %d | %s", pInputOrder->OrderRef, pRspInfo->ErrorID, pRspInfo->ErrorMsg);
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

void CustomTradeSpi::OnRtnOrder(CThostFtdcOrderField *pOrder)
{
	// FrontID + SessionID + OrderRef
	int front_id = this->_trader->front_id;
	int session_id = this->_trader->session_id;

	// ExchangeID + OrderSysID
	// log_info("OnRtnOrder | %s | %s | %s | Info | %s | %lf | %d | %d | Status | %c | %c", 
	log_info("OnRtnOrder | Ref: %d+%d+%s | Sys: %s+%s | %s | %lf | #:%d | #Traded: %d | Status | %c | %c", 
			front_id,
			session_id,
			pOrder->OrderRef,

			pOrder->ExchangeID,
			pOrder->OrderSysID,

			pOrder->InstrumentID,
			pOrder->LimitPrice,
			pOrder->VolumeTotal,
			pOrder->VolumeTraded,

			pOrder->OrderSubmitStatus,
			pOrder->OrderStatus
		);
}

void CustomTradeSpi::OnRtnTrade(CThostFtdcTradeField *pTrade)
{
	log_info("OnRtnTrade | Sys: %s+%s | %s | Time: %s %s | %lf | %d | %c",
			pTrade->ExchangeID,
			pTrade->OrderSysID,

			pTrade->InstrumentID,
			pTrade->TradeDate,
			pTrade->TradeTime,
			pTrade->Price,
			pTrade->Volume,
			pTrade->Direction
		);
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