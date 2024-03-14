#ifndef _POSITION_H_
#define _POSITION_H_

#include "ThostFtdcUserApiDataType.h"
#include "ThostFtdcUserApiStruct.h"
#include "pthread.h"

struct _ctp_position_t;
typedef struct _ctp_position_t ctp_position_t;

struct _ctp_position_t {
    struct CThostFtdcInvestorPositionField field;
    ctp_position_t * nxt;
    int finished;
} ;

ctp_position_t * ctp_position_create(struct CThostFtdcInvestorPositionField * data);
void ctp_position_append(ctp_position_t * l, ctp_position_t * p);
void ctp_position_free(ctp_position_t * l);


typedef struct {
    ctp_position_t * curr;
    ctp_position_t * cache;

    pthread_mutex_t lock;
} ctp_position_keeper_t;

ctp_position_keeper_t * ctp_position_keeper_new();
int ctp_position_keeper_update(ctp_position_keeper_t * pk, struct CThostFtdcInvestorPositionField * data, int last);
ctp_position_t * ctp_position_keeper_localcopy(ctp_position_keeper_t * pk);

#endif