#include "ctpc2.h"

#include "log.h"
#include "cond.h"
#include "queue.h"

#include <string.h>
#include <assert.h>
#include <stdlib.h>


#define _SERVICE_MQ_DEF_SIZE_ 1024

ctp_md_t * ctp_md_new() {
	ctp_md_t * md = (ctp_md_t *)malloc(sizeof(ctp_md_t));
	memset(md, 0, sizeof(ctp_md_t));

    md->q = queue_new_ptr(_SERVICE_MQ_DEF_SIZE_);
    md->c = (struct cond *)malloc(sizeof(struct cond));
    cond_create(md->c);
	return md;
}

void ctp_md_send(ctp_md_t * md, void *msg) {
	cond_trigger_begin(md->c);
    queue_push_ptr(md->q, msg);
    cond_trigger_end(md->c, 1);

    // remove hook support
    // if(md->hook) {
	//     md->hook(md, msg);
    // }

    if(md->ext_cond) {
        // log_debug("ext_cond send");
        cond_trigger_begin(md->ext_cond);
        cond_trigger_end(md->ext_cond, 1);
    }
}

ctp_md_tick_t * ctp_md_recv(ctp_md_t * md) {
    ctp_md_tick_t * msg = NULL;
    while ( msg == NULL ) {
        cond_wait_begin(md->c);

        while( queue_length(md->q) == 0 )
            cond_wait(md->c);
        msg = (ctp_md_tick_t *)queue_pop_ptr(md->q);

        cond_wait_end(md->c);
    }
    return msg;
}

void ctp_md_tick_free(ctp_md_tick_t * t) {
    log_debug("ctp_md_tick_free");
    free(t);
}