#ifndef _ASSTEST_H
#define _ASSTEST_H
int initassinner(const char * subfile, int frame_w, int frame_h );
char* getPng(int tm,int frame_w , int frame_h);
void cleanupinner();
#endif