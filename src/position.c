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
