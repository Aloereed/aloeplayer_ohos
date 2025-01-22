/*
 * @Author: 
 * @Date: 2025-01-21 19:48:59
 * @LastEditors: 
 * @LastEditTime: 2025-01-21 19:49:07
 * @Description: file content
 */
#include <stdio.h>
#include <setjmp.h>

/** Holds information to implement exception handling. */
__thread jmp_buf ex_buf__;
