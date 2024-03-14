#include "position.h"
#include "stdlib.h"
#include "string.h"


ctp_position_t * ctp_position_create(struct CThostFtdcInvestorPositionField * data) {
    ctp_position_t * p;
    p = (ctp_position_t *)malloc(sizeof(ctp_position_t));
    memset(p, 0, sizeof(ctp_position_t));
    if(data) {
        memcpy(&(p->field), data, sizeof(struct CThostFtdcInvestorPositionField));
    }
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
    ctp_position_keeper_t * pk = (ctp_position_keeper_t *)malloc(sizeof(ctp_position_keeper_t));
    memset(pk, 0, sizeof(ctp_position_keeper_t));
    pthread_mutex_init(&pk->lock, NULL);
}

int ctp_position_keeper_update(ctp_position_keeper_t * pk, struct CThostFtdcInvestorPositionField * data, int last) {
    ctp_position_t * p = ctp_position_create(data);
    if( pk->cache == NULL ) {
        pk->cache = p;
    }
    else {
        ctp_position_append(pk->cache, p);
    }

    if( last ) {
        // lock
        pthread_mutex_lock(&pk->lock);

        ctp_position_free(pk->curr);
        pk->curr = pk->cache;
        pk->cache = NULL;

        pthread_mutex_unlock(&pk->lock);
    }
}
ctp_position_t * ctp_position_keeper_localcopy(ctp_position_keeper_t * pk) {
    pthread_mutex_lock(&pk->lock);
    ctp_position_t * p = pk->curr;
    ctp_position_t * copy = NULL;
    ctp_position_t * q = NULL;

    while (p != NULL) {
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
