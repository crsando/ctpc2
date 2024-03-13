#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#define CTP_DATETIME_BUF_SIZE 20

//
// day : 20240101
// time: 09:00:00
//
int64_t ctp_date_time_to_msec(const char * day, const char * time, int msec) {
    int64_t rst;
    struct tm dt;
    char buffer[CTP_DATETIME_BUF_SIZE];

    memset(buffer, 0, sizeof(char)*(CTP_DATETIME_BUF_SIZE));

    strncpy(buffer, day, 4);
    strncpy(buffer + 4, "-", 1);
    strncpy(buffer + 5, day + 4, 2);
    strncpy(buffer + 7, "-", 1);
    strncpy(buffer + 8, day + 6, 2);
    strncpy(buffer + 10, " ", 8);
    strncpy(buffer + 11, time, 8);

    printf(buffer);
    putchar('\n');


    memset(&dt, 0, sizeof(struct tm));
    strptime(buffer, "%Y-%m-%d %H:%M:%S", &dt);

    rst = (int64_t)mktime(&dt);
    rst = (rst * 1000) + ((int64_t)msec);

    return rst;
}

// nanosecs, use with questdb
char * ctp_nsecs_to_str(int64_t nsecs) {
    struct tm s;
    char tmp[24];
    unsigned int sp = nsecs % 1000000;
    time_t epoch = (time_t)((nsecs - sp) / 1000000);
    printf("epoch:%ld sp:%d", epoch, sp);
    localtime_r(&epoch, &s);
    memset(tmp, 0, sizeof(tmp));
    strftime(tmp, 64, "%Y-%m-%dT%H:%M:%S", &s);
    printf(tmp);
    printf("\n");

    char * str;
    str = (char *)malloc(sizeof(char) * 32);
    memset(str, 0, sizeof(char)*32);
    sprintf(str, "%s.%06d", tmp, sp);
    return str;
}