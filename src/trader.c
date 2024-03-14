#include "ctpc2.h"
#include "cond.h"
#include "queue.h"

#define _SERVICE_MQ_DEF_SIZE_ (1024)

ctp_trader_t * ctp_trader_new() {
    ctp_trader_t * t = (ctp_trader_t *)malloc(sizeof(ctp_trader_t));
    memset(t, 0, sizeof(ctp_trader_t));
    t->q = queue_new_ptr(_SERVICE_MQ_DEF_SIZE_);
    t->c = (struct cond *)malloc(sizeof(struct cond));
    cond_create(t->c);
    return t;
}

void ctp_trader_send(ctp_trader_t * t, ctp_rsp_t * msg) {
	cond_trigger_begin(t->c);
    queue_push_ptr(t->q, msg);
    cond_trigger_end(t->c, 1);
}
ctp_rsp_t * ctp_trader_recv(ctp_trader_t * t) {
    ctp_rsp_t * msg = NULL;
    while ( msg == NULL ) {
        cond_wait_begin(t->c);
        cond_wait(t->c);

        // designated behaviour: throw msg away, leave only the last one
        while( queue_length(t->q) > 0 )
            msg = (ctp_rsp_t *)queue_pop_ptr(t->q);

        cond_wait_end(t->c);
    }
    return msg;
}

void ctp_rsp_free(ctp_rsp_t * r) {
    if(r->field) 
        free(r->field);
    if(r->info)
        free(r->info);
    free(r);
}

//

void ctp_trader_wait_for_settle(ctp_trader_t * t) {
    while(1) {
        ctp_rsp_t * rsp = ctp_trader_recv(t);
        if (t->connected == 4) {
            return;
        }
    }
}


// int ctp_trader_query(ctp_trader_t * trader, ctp_trader_req_cb func, void * field);
// void * ctp_trader_fetch(ctp_trader_t * trader, int req_id);