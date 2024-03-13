#ifndef _POSITION_H_
#define _POSITION_H_

#include "ThostFtdcUserApiDataType.h"
#include "ThostFtdcUserApiStruct.h"

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

#endif