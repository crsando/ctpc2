#include "ctpc2.h"
#include "cond.h"
#include "queue.h"
#include "log.h"

#include <string.h>
#include <stdlib.h>
#include <stdbool.h>

#include "uv.h"

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

    if(t->ext_cond) {
        cond_trigger_begin(t->ext_cond);
        cond_trigger_end(t->ext_cond, 1);
    }

    if(t->async) {
        uv_async_send(t->async);
    }
}

ctp_rsp_t * ctp_trader_recv(ctp_trader_t * t, bool blocking) {
    ctp_rsp_t * msg = NULL;
    cond_wait_begin(t->c);

    if(blocking) {
        if ( queue_length(t->q) == 0 )
            cond_wait(t->c);
    }
    msg = (ctp_rsp_t *)queue_pop_ptr(t->q);

    cond_wait_end(t->c);
    return msg;
}

void ctp_trader_release(ctp_trader_t * t) {
    queue_delete(t->q);
    cond_release(t->c);
}

void ctp_rsp_free(ctp_rsp_t * r) {
    if(r != NULL)
        free(r);
}

void ctp_trader_wait_for_settle(ctp_trader_t * t) {
    while(t->connected != 4) {
        ctp_rsp_t * rsp = ctp_trader_recv(t, true);
        ctp_rsp_free(rsp);
    }
}