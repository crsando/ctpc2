#include "ctpc2.h"
#include "cond.h"
#include "queue.h"
#include "log.h"

#define _SERVICE_MQ_DEF_SIZE_ (1024)

ctp_trader_t * ctp_trader_new() {
    ctp_trader_t * t = (ctp_trader_t *)malloc(sizeof(ctp_trader_t));
    memset(t, 0, sizeof(ctp_trader_t));
    t->q = queue_new_ptr(_SERVICE_MQ_DEF_SIZE_);
    t->c = (struct cond *)malloc(sizeof(struct cond));
    cond_create(t->c);
    log_info("t->c : %d", t->c);
    return t;
}

void ctp_trader_send(ctp_trader_t * t, ctp_rsp_t * msg) {
    // log_debug("ctp_trader_send");
    // log_debug("ctp_trader_send %d", msg);
	cond_trigger_begin(t->c);
    queue_push_ptr(t->q, msg);
    cond_trigger_end(t->c, 1);
}
ctp_rsp_t * ctp_trader_recv(ctp_trader_t * t) {
    // log_debug("ctp_trader_recv start | %d", queue_length(t->q));
    ctp_rsp_t * msg = NULL;
    while ( msg == NULL ) {
        // log_debug("ctp_trader_recv while | %d", t->c);
        cond_wait_begin(t->c);
        // log_debug("ctp_trader_recv while 1");
        cond_wait(t->c);
        // log_debug("ctp_trader_recv while 2");

        // designated behaviour: throw msg away, leave only the last one
        // log_debug("ctp_trader_recv queue_length %d", queue_length(t->q));
        if ( queue_length(t->q) > 0 )
            msg = (ctp_rsp_t *)queue_pop_ptr(t->q);

        cond_wait_end(t->c);
    }
    // log_debug("ctp_trader_recv end");
    return msg;
}

void ctp_rsp_free(ctp_rsp_t * r) {
    if(r->field) 
        free(r->field);
    free(r);
}

//

void ctp_trader_wait_for_settle(ctp_trader_t * t) {
    while(t->connected != 4) {
        ctp_rsp_t * rsp = ctp_trader_recv(t);
        ctp_rsp_free(rsp);
    }
}


// int ctp_trader_query(ctp_trader_t * trader, ctp_trader_req_cb func, void * field);
// void * ctp_trader_fetch(ctp_trader_t * trader, int req_id);