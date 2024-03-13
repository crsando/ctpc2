#ifndef _LIBCTP_H_
#define _LIBCTP_H_

#include "ThostFtdcUserApiDataType.h"
#include "ThostFtdcUserApiStruct.h"
#include "stdint.h"
#include "reg.h"
#include "macros.h"
#include "position.h"

typedef void (*ctp_func_cb_t)(void * tick, void * _ctx);
typedef void (*ctp_tick_cb)(struct CThostFtdcDepthMarketDataField * tick);

typedef struct {
    // tcp://xxx.xxx.xxx.xxx:xxxx
    char front_addr[128]; // FrontAddr
    char broker[11]; // BrokerID
    char user[13]; // InvestorID
    // char password[41]; // InvestorPassword

    // status
    int connected; // 0: not connected; 1: connected; 2: logined; 3: subscribe complete

    // only one symbol
    // char symbol[9]; // InstrumentID

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


// response

// declarations
struct _ctp_trader_t;
typedef struct _ctp_trader_t ctp_trader_t;
typedef struct _ctp_reg_t ctp_reg_t;

typedef void (*ctp_trader_rsp_cb)(ctp_trader_t * trader, const char name[], void * field, void * rsp_info, int req_id, int is_last);


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

    // class pointer
    void * _spi;
    void * _api;

    int req_id; // start from 0, incr on requests

    //
    ctp_trader_rsp_cb on_rsp;
    ctp_reg_t ** reg; // ATTENTION, double star here

    // internal message queue for tick data
    struct queue * q;
    struct cond * c;
} ctp_trader_t;

// void ctp_trader_default_rsp_handler(ctp_trader_t * trader, const char name[], void * field, void * rsp_info, int req_id, int is_last);

ctp_trader_t * ctp_trader_new();
ctp_trader_t * ctp_trader_init(ctp_trader_t * trader, const char front_addr[], const char broker[], 
    const char user[], const char password[], const char app_id[], const char auth_code[]);


typedef struct {
    uint32_t rsp_typ;
    void * field;
    size_t size;
    struct CThostFtdcRspInfoField * info;
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

// typedef struct CThostFtdcTradingAccountField ctp_account_t;
// ctp_account_t * ctp_trader_fetch_account(ctp_trader_t * trader, int req_id);
// void ctp_account_free(ctp_account_t * p);

// int ctp_trader_query_position(ctp_trader_t * trader);
// ctp_position_t * ctp_trader_fetch_position(ctp_trader_t * trader, int req_id);


// typedef int (*ctp_trader_req_cb)(void * field, int req_id);
// int ctp_trader_query(ctp_trader_t * trader, ctp_trader_req_cb func, void * field);
// void * ctp_trader_fetch(ctp_trader_t * trader, int req_id);

#endif