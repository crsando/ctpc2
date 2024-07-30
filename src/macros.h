#ifndef _MACROS_H_
#define _MACROS_H

#define CTP_TRADER_READY(trader) ((trader)->connected >= 4 ? 1 : 0)

// return req_id
// must be at the end of the function definition
#define CTP_TRADER_REQ(trader, cmd, field) \
    do { \
        int req_id = ++((trader)->req_id); \
        log_debug("Req%s | req_id: %d", # cmd, req_id); \
        ((CThostFtdcTraderApi *)((trader)->_api))->Req ## cmd(field, req_id); \
        return req_id; \
    } while(0)

#endif