#ifndef _UTIL_H_
#define _UTIL_H_

#include <time.h>

int64_t ctp_date_time_to_msec(const char * day, const char * time, int msec);
char * ctp_nsecs_to_str(int64_t nsecs);

#endif 