#include "reg.h"
#include "log.h"

ctp_reg_t * ctp_reg_get(ctp_reg_t ** reg, int req_id) {
	// log_debug("ctp_reg_get | req_id: %d", req_id);
	ctp_reg_t * s = NULL;
	HASH_FIND_INT(*reg, &req_id, s);
	return s;
}
ctp_reg_t * ctp_reg_put(ctp_reg_t ** reg, int req_id, void * data, size_t size) {
	// log_debug("ctp_reg_put | req_id: %d | size: %u", req_id, size);
	ctp_reg_t * p = NULL;
	p = ctp_reg_get(reg, req_id);
	if(p) {
		log_info("ctp_reg_put | key duplicate | req_id : %d", req_id);
		return p;
	}

	p = (ctp_reg_t*)malloc(sizeof(ctp_reg_t));
	p->req_id = req_id;
	p->size = size;
	p->data = (void*)malloc(size);
	memcpy(p->data, data, size);

	HASH_ADD_INT(*reg, req_id, p);
	// log_debug("ctp_reg_put | req_id: %d | ADD : %d", req_id, p);

	return p;
}
ctp_reg_t * ctp_reg_del(ctp_reg_t ** reg, int req_id) {
	// log_debug("ctp_reg_del | req_id: %d", req_id);
	ctp_reg_t * p = NULL;
	p = ctp_reg_get(reg, req_id);
	if (p) {
		HASH_DEL(*reg, p);
	}
	free(p->data);
	free(p);
	return NULL;
}