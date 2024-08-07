#ifndef _LIBCTP_H_
#define _LIBCTP_H_

#include "ThostFtdcUserApiDataType.h"
#include "ThostFtdcUserApiStruct.h"
#include "stdint.h"
#include "macros.h"
#include "position.h"
#include <stdbool.h>
#include "cond.h"

// typedef void (*ctp_func_cb_t)(void * tick, void * _ctx);
// typedef void (*ctp_tick_cb)(struct CThostFtdcDepthMarketDataField * tick);

// common callback type
typedef void (*ctp_hook_cb)(void * self, void * data);

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

    // external hook
    // ctp_hook_cb hook;

    void * ext_cond;
} ctp_md_t;


// Applicaton Interface
ctp_md_t * ctp_md_new();
ctp_md_t * ctp_md_init(ctp_md_t * md, const char front_addr[], const char broker[], const char user[]);
void ctp_md_subscribe(ctp_md_t * md, const char symbol[]);
void ctp_md_hook(ctp_md_t * md, ctp_hook_cb hook);
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

    // external conditional variable
    void * ext_cond;
} ctp_trader_t;

ctp_trader_t * ctp_trader_new();
ctp_trader_t * ctp_trader_init(ctp_trader_t * trader, const char front_addr[], const char broker[], 
    const char user[], const char password[], const char app_id[], const char auth_code[]);

ctp_trader_t * ctp_trader_start(ctp_trader_t * trader);
void ctp_trader_wait_for_settle(ctp_trader_t * t);

typedef struct {
    // header
    uint32_t rsp_typ;
    char desc[256];
    char func_name[256];
    char field_name[256];

    // main body
    int req_id;
    void * field;
    size_t size;
    int last;
    bool is_last;

    // common
    void * rsp_info;
} ctp_rsp_t;

void ctp_trader_send(ctp_trader_t * t, ctp_rsp_t * msg);
// ctp_rsp_t * ctp_trader_recv(ctp_trader_t * t);
ctp_rsp_t * ctp_trader_recv(ctp_trader_t * t, bool blocking);
void ctp_rsp_free(ctp_rsp_t * r);

//
// query/fetch model (with req_id as the key)
// query_xxx => OnRspXXX => reg update => fetch => (optional) free
//

int ctp_trader_query_account(ctp_trader_t * trader); 
int ctp_trader_query_position(ctp_trader_t * trader);
int ctp_trader_query_instrument(ctp_trader_t * trader, const char * exchange_id);

// ReqQryDepthMarketData
// int ctp_trader_query_marketdata(ctp_trader_t * trader, const char * symbol);

int ctp_trader_query_order(ctp_trader_t * t);

//
// Order Executions
//
int ctp_trader_order_insert(ctp_trader_t * t, const char * symbol, double price, int volume, char flag);
// int ctp_trader_order_cancel(ctp_trader_t * t, int front_id, int session_id, const char * order_ref);
// int ctp_trader_order_cancel(ctp_trader_t * t, const char * exchange_id, const char * order_sys_id);
int ctp_trader_order_cancel(ctp_trader_t * t, const char * symbol, const char * exchange_id, const char * order_sys_id);

// int ctp_trader_order_cancel(ctp_trader_t * t, )

int ctp_trader_logout(ctp_trader_t * t);

#endif