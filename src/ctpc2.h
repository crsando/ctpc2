#ifndef _LIBCTP_H_
#define _LIBCTP_H_

#include "ThostFtdcUserApiDataType.h"
#include "ThostFtdcUserApiStruct.h"
#include "stdint.h"
#include "macros.h"
#include "position.h"

// typedef void (*ctp_func_cb_t)(void * tick, void * _ctx);
// typedef void (*ctp_tick_cb)(struct CThostFtdcDepthMarketDataField * tick);

typedef struct {
    // tcp://xxx.xxx.xxx.xxx:xxxx
    char front_addr[128]; // FrontAddr
    char broker[11]; // BrokerID
    char user[13]; // InvestorID

    // status
    int connected; // 0: not connected; 1: connected; 2: logined; 3: subscribe complete

    char ** symbols;
    int symbols_num;

    void * _spi;
    void * _api;

    // internal message queue for tick data
    struct queue * q;
    struct cond * c;
} ctp_md_t;


// Applicaton Interface
ctp_md_t * ctp_md_new();
ctp_md_t * ctp_md_init(ctp_md_t * md, const char front_addr[], const char broker[], const char user[]);
void ctp_md_subscribe(ctp_md_t * md, const char symbol[]);
void ctp_md_start(ctp_md_t * md);

typedef struct CThostFtdcDepthMarketDataField ctp_md_tick_t;
void ctp_md_send(ctp_md_t * md, void *msg);
ctp_md_tick_t * ctp_md_recv(ctp_md_t * md);
void ctp_md_tick_free(ctp_md_tick_t * t);


// declarations
struct _ctp_trader_t;
typedef struct _ctp_trader_t ctp_trader_t;

typedef struct _ctp_trader_t {
    char front_addr[128]; // FrontAddr
    char broker[11]; // BrokerID
    char user[13]; // InvestorID
    char password[41]; // InvestorPassword
    char app_id[256];
    char auth_code[256];

    // status
    int connected; // 0: not connected; 1: connected; 2: logined; 3: subscribe complete 4: settlementinfoconfirmed

    // session info
    // OnRspUserLogin
    int front_id;
    int	session_id;	//会话编号
    char max_order_ref[13];	//报单引用
    char lst_order_ref[13];

    // class pointer
    void * _spi;
    void * _api;

    int req_id; // start from 0, incr on requests

    // internal message queue for tick data
    struct queue * q;
    struct cond * c;
} ctp_trader_t;

ctp_trader_t * ctp_trader_new();
ctp_trader_t * ctp_trader_init(ctp_trader_t * trader, const char front_addr[], const char broker[], 
    const char user[], const char password[], const char app_id[], const char auth_code[]);
ctp_trader_t * ctp_trader_start(ctp_trader_t * trader);
void ctp_trader_wait_for_settle(ctp_trader_t * t);

typedef struct {
    int req_id;
    uint32_t rsp_typ;
    char desc[256];
    void * field;
    size_t size;
    int last;
} ctp_rsp_t;

void ctp_trader_send(ctp_trader_t * t, ctp_rsp_t * msg);
ctp_rsp_t * ctp_trader_recv(ctp_trader_t * t);
void ctp_rsp_free(ctp_rsp_t * r);

//
// query/fetch model (with req_id as the key)
// query_xxx => OnRspXXX => reg update => fetch => (optional) free
//

int ctp_trader_query_account(ctp_trader_t * trader); 
int ctp_trader_query_position(ctp_trader_t * trader);

// ReqQryDepthMarketData
// int ctp_trader_query_marketdata(ctp_trader_t * trader, const char * symbol);


//
// Order Executions
//
int ctp_trader_order_insert(ctp_trader_t * t, const char * symbol, double price, int volume, char flag);

#endif