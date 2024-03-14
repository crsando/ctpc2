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
	// _api(md)->Join();
}
void ctp_md_join(ctp_md_t * md) {
	_api(md)->Join();
}

// ctp_md_t * ctp_md_init(ctp_md_t * md, const char front_addr[], const char broker[], const char user[], const char password[])
ctp_md_t * ctp_md_init(ctp_md_t * md, const char front_addr[], const char broker[], const char user[]) 
{
    log_debug("ctp_md_init | %s | %s", front_addr, broker);
	// <TODO> Check string length
	strcpy(md->front_addr, &front_addr[0]);
	strcpy(md->broker, &broker[0]);
	strcpy(md->user, &user[0]);
	// strcpy(md->password, &password[0]);


    // symbols
    const int max_symbols_num = 16;
    md->symbols = (char **)malloc(sizeof(char *) * (max_symbols_num + 1));
    memset(md->symbols, 0, sizeof(char *) * (max_symbols_num + 1));
    md->symbols_num = 0;

	CustomMdSpi * pMdUserSpi = new CustomMdSpi();       // 创建行情回调实例
    // strcpy(pMdUserSpi->gBrokerID, broker);
    // strcpy(pMdUserSpi->gInvestorID, user);
    // strcpy(pMdUserSpi->gInvestorPassword, password);

	pMdUserSpi->g_pMdUserApi = CThostFtdcMdApi::CreateFtdcMdApi();   // 创建行情实例
	pMdUserSpi->g_pMdUserApi->RegisterSpi(pMdUserSpi);               // 注册事件类
	pMdUserSpi->g_pMdUserApi->RegisterFront(md->front_addr);           // 设置行情前置地址
	
	md->_spi = (void *)pMdUserSpi;
	md->_api = (void *)(pMdUserSpi->g_pMdUserApi);
	_spi(md)->_md = md;

	md->connected = 0;

	return md;
}

// void ctp_md_subscribe(ctp_md_t * md, char * symbol, ctp_func_cb_t cb, void * ctx)
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
    // memcpy(md->symbols + md->symbols_num, &buf, sizeof(char *));
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

void ctp_trader_default_rsp_handler(ctp_trader_t * trader, const char name[], void * field, void * rsp_info, int req_id, int is_last) {
	log_info("handler | OnRsp%s\n | %d", name, req_id);
}

ctp_trader_t * ctp_trader_init(
    ctp_trader_t * trader, 
    const char front_addr[], const char broker[], 
    const char user[], const char password[],
    const char app_id[], const char auth_code[]
    )
{
	log_info("ctp_trader_init | %s | %s | %s | %s | %s", front_addr, broker, user, app_id, auth_code);
    // if(trader == NULL) {
    //     trader = (ctp_trader_t *)malloc(sizeof(ctp_trader_t));
    // }
	assert(trader != NULL);
    // memset(trader, 0, sizeof(ctp_trader_t));

    strcpy(trader->front_addr, front_addr);
    strcpy(trader->broker, broker);
    strcpy(trader->user, user);
    strcpy(trader->password, password);
    strcpy(trader->app_id, app_id);
    strcpy(trader->auth_code, auth_code);

	//
	trader->reg = (ctp_reg_t **)malloc( sizeof(ctp_reg_t*) );
	*(trader->reg) = NULL;

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

// ctp_account_t * ctp_trader_fetch_account(ctp_trader_t * trader, int req_id) {
//     // log_debug("ctp_trader_fetch_account | %d", req_id);
// 	ctp_account_t * field = NULL;
// 	ctp_reg_t * r = NULL;
// 	r = ctp_reg_get(trader->reg, req_id);
// 	if (r) {
//         // same type effectively
//         field = (ctp_account_t *)malloc(sizeof(ctp_account_t));
// 		memcpy(field, (struct CThostFtdcTradingAccountField *)(r->data), sizeof(struct CThostFtdcTradingAccountField));
// 		ctp_reg_del(trader->reg, req_id);
// 	}
// 	return field;
// }

// void ctp_account_free(ctp_account_t * p) { free(p); }

// int ctp_trader_query_position(ctp_trader_t * trader) {
// 	CThostFtdcQryInvestorPositionField field;
// 	memset(&field, 0, sizeof(field));
// 	strcpy(field.BrokerID, trader->broker);
// 	strcpy(field.InvestorID, trader->user);
// 	CTP_TRADER_REQ(trader, QryInvestorPosition, &field);
// }

// ctp_position_t * ctp_trader_fetch_position(ctp_trader_t * trader, int req_id) {
// 	ctp_position_t * p = NULL;
// 	ctp_reg_t * r = NULL;
// 	r = ctp_reg_get(trader->reg, req_id);
// 	if (r) {
// 		p = ((ctp_position_t *)(r->data))->nxt;
//         if ( p->finished == 1 ) {
//             ctp_reg_del(trader->reg, req_id);
//             return p;
//         }
//         else {
//             return NULL; // not finished yet
//         }
// 	}
// 	return NULL;
// }

} // end extern "C"