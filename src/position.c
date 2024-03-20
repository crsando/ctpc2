#include "position.h"
#include "stdlib.h"
#include "string.h"
#include "log.h"


ctp_position_t * ctp_position_create(struct CThostFtdcInvestorPositionField * data) {
    log_debug("ctp_position_new %d", data);
    ctp_position_t * p;
    p = (ctp_position_t *)malloc(sizeof(ctp_position_t));
    memset(p, 0, sizeof(ctp_position_t));
    if(data) {
        memcpy(&(p->field), data, sizeof(struct CThostFtdcInvestorPositionField));
    }
    log_debug("ctp_position_new %d end", data);
    return p;
}
void ctp_position_append(ctp_position_t * l, ctp_position_t * p) {
    if(l != NULL) {
        while (l->nxt != NULL) 
            l = l->nxt;
        l->nxt = p;
    }
}

void ctp_position_free(ctp_position_t * l) {
    ctp_position_t * p;
    ctp_position_t * n;
    p = l;
    while( p != NULL ) {
        n = p;
        p = p->nxt;
        free(n);
    }
}
struct _ctp_position_keeper_t {
    ctp_position_t * curr;
    ctp_position_t * cache;

    pthread_mutex_t lock;
};

ctp_position_keeper_t * ctp_position_keeper_new() {
    log_debug("ctp_position_keeper_new");
    ctp_position_keeper_t * pk = (ctp_position_keeper_t *)malloc(sizeof(ctp_position_keeper_t));
    memset(pk, 0, sizeof(ctp_position_keeper_t));
    pthread_mutex_init(&pk->lock, NULL);
    return pk;
}

int ctp_position_keeper_update(ctp_position_keeper_t * pk, struct CThostFtdcInvestorPositionField * data, int last) {
    log_debug("ctp_position_keeper_update %d | %d | %d", pk, data, last);
    ctp_position_t * p = ctp_position_create(data);
    pthread_mutex_lock(&pk->lock);
    if( pk->cache == NULL ) {
        log_debug("ctp_position_keeper_update 0");
        pk->cache = p;
    }
    else {
        log_debug("ctp_position_keeper_update append");
        ctp_position_append(pk->cache, p);
    }
    pthread_mutex_unlock(&pk->lock);

    if( last ) {
        log_debug("ctp_position_keeper_update lock and swap");
        // lock
        pthread_mutex_lock(&pk->lock);

        ctp_position_free(pk->curr);
        pk->curr = pk->cache;
        pk->cache = NULL;

        pthread_mutex_unlock(&pk->lock);
        log_debug("ctp_position_keeper_update unlock");
    }
}

ctp_position_t * ctp_position_keeper_localcopy(ctp_position_keeper_t * pk) {
    log_debug("ctp_position_keeper_localcopy start");
    pthread_mutex_lock(&pk->lock);
    ctp_position_t * p = pk->curr;
    ctp_position_t * copy = NULL;
    ctp_position_t * q = NULL;

    log_debug("ctp_position_keeper_localcopy while");
    while (p != NULL) {
        log_debug("ctp_position_keeper_localcopy create 1 | %d", p);
        q = ctp_position_create(&p->field);
        if(copy == NULL) {
            copy = q;
        }
        else {
            ctp_position_append(copy, q);
        }
        p = p->nxt;
    }

    pthread_mutex_unlock(&pk->lock);

    return copy;
}
