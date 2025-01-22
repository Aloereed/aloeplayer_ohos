#ifndef EXCEPTION_H
#define EXCEPTION_H

#include <setjmp.h>

/** Holds information to implement exception handling. */
extern __thread jmp_buf ex_buf__;

#endif // EXCEPTION_H
