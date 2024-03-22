#include <iostream>
#include <stdio.h>
#include <string>

#include "malloc.h"
#include "string.h"
#include "stdlib.h"

#include "CustomMdSpi.h"
#include "CustomTradeSpi.h"

#include "assert.h"

extern "C" {
#include "log.h"
#include "ctpc2.h"

// MD API
#define _api(md) ((CThostFtdcMdApi *)((md)->_api))
#define _spi(md) ((CustomMdSpi *)((md)->_spi))

void ctp_md_start(ctp_md_t * md) {
    log_debug("ctp_md_start");
	_api(md)->Init();
}
void ctp_md_join(ctp_md_t * md) {
	_api(md)->Join();
}

ctp_md_t * ctp_md_init(ctp_md_t * md, const char front_addr[], const char broker[], const char user[]) 
{
    log_debug("ctp_md_init | %s | %s", front_addr, broker);
	// <TODO> Check string length
	strcpy(md->front_addr, &front_addr[0]);
	strcpy(md->broker, &broker[0]);
	strcpy(md->user, &user[0]);


    // symbols
    const int max_symbols_num = 16;
    md->symbols = (char **)malloc(sizeof(char *) * (max_symbols_num + 1));
    memset(md->symbols, 0, sizeof(char *) * (max_symbols_num + 1));
    md->symbols_num = 0;

	CustomMdSpi * pMdUserSpi = new CustomMdSpi();       // 创建行情回调实例

	pMdUserSpi->g_pMdUserApi = CThostFtdcMdApi::CreateFtdcMdApi();   // 创建行情实例
	pMdUserSpi->g_pMdUserApi->RegisterSpi(pMdUserSpi);               // 注册事件类
	pMdUserSpi->g_pMdUserApi->RegisterFront(md->front_addr);           // 设置行情前置地址
	
	md->_spi = (void *)pMdUserSpi;
	md->_api = (void *)(pMdUserSpi->g_pMdUserApi);
	_spi(md)->_md = md;

	md->connected = 0;

	return md;
}

void ctp_md_subscribe(ctp_md_t * md, const char symbol[])
{
    log_debug("ctp_md_subscribe | %s", symbol);
    char * buf;
	int n = strlen(symbol);
	const int buf_size = 81;
    assert(n < 9);

    buf = (char *)malloc(sizeof(char) * buf_size);
    memset(buf, 0, sizeof(char) * buf_size);
    strncpy(buf, symbol, sizeof(char) * (n));


    // add
    md->symbols[md->symbols_num] = buf;
    md->symbols_num ++;


    int j;
    for(j = 0; j < md->symbols_num; j++) {
        log_debug("ctp_md_subscribe | iter | %d | %s", j, (md->symbols)[j]);
    }
}


// Trader API
#undef _spi
#undef _api
#define _spi(t) ((CustomTradeSpi *)((t)->_spi))
#define _api(t) ((CThostFtdcTraderApi *)((t)->_api))

ctp_trader_t * ctp_trader_init(
    ctp_trader_t * trader, 
    const char front_addr[], const char broker[], 
    const char user[], const char password[],
    const char app_id[], const char auth_code[]
    )
{
	log_debug("ctp_trader_init | %s | %s | %s | %s | %s", front_addr, broker, user, app_id, auth_code);
    if(trader == NULL) {
        trader = ctp_trader_new();
    }
	assert(trader != NULL);

    strcpy(trader->front_addr, front_addr);
    strcpy(trader->broker, broker);
    strcpy(trader->user, user);
    strcpy(trader->password, password);
    strcpy(trader->app_id, app_id);
    strcpy(trader->auth_code, auth_code);

    CThostFtdcTraderApi * pTradeUserApi = CThostFtdcTraderApi::CreateFtdcTraderApi(); // 创建交易实例
	CustomTradeSpi *pTradeSpi = new CustomTradeSpi;               // 创建交易回调实例

    pTradeSpi->_trader = trader;
    trader->_spi = (void *)pTradeSpi;
    trader->_api = (void *)pTradeUserApi;
	pTradeUserApi->RegisterSpi(pTradeSpi);                      // 注册事件类
	pTradeUserApi->SubscribePublicTopic(THOST_TERT_RESTART);    // 订阅公共流
	pTradeUserApi->SubscribePrivateTopic(THOST_TERT_RESTART);   // 订阅私有流
	pTradeUserApi->RegisterFront(trader->front_addr);              // 设置交易前置地址

	return trader;
}
ctp_trader_t * ctp_trader_start(ctp_trader_t * trader) {
	_api(trader)->Init();
    return trader;
}

int ctp_trader_query_account(ctp_trader_t * trader) {
    log_debug("ctp_trader_query_account");
	CThostFtdcQryTradingAccountField tradingAccountReq;
	memset(&tradingAccountReq, 0, sizeof(tradingAccountReq));
	strcpy(tradingAccountReq.BrokerID, trader->broker);
	strcpy(tradingAccountReq.InvestorID, trader->user);
	CTP_TRADER_REQ(trader, QryTradingAccount, &tradingAccountReq);
}

int ctp_trader_query_position(ctp_trader_t * trader) {
	CThostFtdcQryInvestorPositionField field;
	memset(&field, 0, sizeof(field));
	strcpy(field.BrokerID, trader->broker);
	strcpy(field.InvestorID, trader->user);
	CTP_TRADER_REQ(trader, QryInvestorPosition, &field);
}

// useless, it is for options not for futures
int ctp_trader_query_marketdata(ctp_trader_t * trader, const char * symbol) {
    CThostFtdcQryDepthMarketDataField field;
	memset(&field, 0, sizeof(field));
	strcpy(field.InstrumentID, symbol);
	CTP_TRADER_REQ(trader, QryDepthMarketData, &field);
}



int ctp_trader_order_insert(ctp_trader_t * t, const char * symbol, double price, int volume, int flag)
{
    log_debug("ctp_trader_order_insert %s | %lf | %d | %d", symbol, price, volume, flag);
    int order_ref_i = 0;
	CThostFtdcInputOrderField orderInsertReq;
	memset(&orderInsertReq, 0, sizeof(orderInsertReq));
	strcpy(orderInsertReq.BrokerID, t->broker);
	strcpy(orderInsertReq.InvestorID, t->user);
	strcpy(orderInsertReq.InstrumentID, symbol);

    order_ref_i = atoi(t->lst_order_ref) + 1;
    sprintf(orderInsertReq.OrderRef, "%012d", order_ref_i);
    sprintf(t->lst_order_ref, "%012d", order_ref_i);
    log_debug("order_ref: %s", orderInsertReq.OrderRef);

    if ( price < 0.0001 ) {
        log_debug("ctp_trader_order_insert | market order");
        orderInsertReq.OrderPriceType = THOST_FTDC_OPT_AnyPrice;
        orderInsertReq.LimitPrice = 0.0;
        orderInsertReq.TimeCondition = THOST_FTDC_TC_IOC; // 立即成交否则撤销
    }
    else {
        // limit order
        log_debug("ctp_trader_order_insert | limit order | %lf", price);
        orderInsertReq.OrderPriceType = THOST_FTDC_OPT_LimitPrice;
        orderInsertReq.LimitPrice = price;
        orderInsertReq.TimeCondition = THOST_FTDC_TC_GFD; // 当日有效
    }

    if(flag > 0) {
        orderInsertReq.CombOffsetFlag[0] = THOST_FTDC_OF_Open; // open
    }
    else {
        orderInsertReq.CombOffsetFlag[0] = THOST_FTDC_OF_Close; // close
    }
    log_debug("CombOffsetFlag[0]=%c", orderInsertReq.CombOffsetFlag[0]);
	orderInsertReq.CombHedgeFlag[0] = THOST_FTDC_HF_Speculation;

	orderInsertReq.Direction = (volume > 0 ? THOST_FTDC_D_Buy : THOST_FTDC_D_Sell);
    log_debug("Direction=%c", orderInsertReq.Direction);
	orderInsertReq.VolumeTotalOriginal = abs(volume); // input volume
	orderInsertReq.VolumeCondition = THOST_FTDC_VC_AV;
	orderInsertReq.MinVolume = 1;

	orderInsertReq.ContingentCondition = THOST_FTDC_CC_Immediately;
	orderInsertReq.ForceCloseReason = THOST_FTDC_FCC_NotForceClose;
	orderInsertReq.IsAutoSuspend = 0;
	orderInsertReq.UserForceClose = 0;

	CTP_TRADER_REQ(t, OrderInsert, &orderInsertReq);
}

} // end extern "C"