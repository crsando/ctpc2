#include "uthash.h"

typedef struct _ctp_reg_t {
    int req_id;
    void * data;
    size_t size;
    UT_hash_handle hh;
} ctp_reg_t;

ctp_reg_t * ctp_reg_get(ctp_reg_t ** reg, int req_id);
ctp_reg_t * ctp_reg_put(ctp_reg_t ** reg, int req_id, void * data, size_t size);
ctp_reg_t * ctp_reg_del(ctp_reg_t ** reg, int req_id);