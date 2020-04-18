/*
 * strchr test.
 *
 * Copyright (c) 2019, Arm Limited.
 * SPDX-License-Identifier: MIT
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <assert.h>
#include "stringlib.h"

static const struct fun
{
    const char *name;
    size_t (*fun)(const char *s, const char *a);
} funtab[] = {
#define F(x) {#x, x},
    F(strspn)
#if __ARM_FEATURE_SVE2
    F(__strspn_aarch64_sve2)
#endif
#undef F
};

#define ARRAY_SIZE(X)  (sizeof(X) / sizeof(X[0]))

static int test_status;
#define ERR(...) (test_status=1, printf(__VA_ARGS__))

#define A 32
#define LEN 250000
static char sbuf[LEN+3*A];

static void *alignup(void *p)
{
    return (void*)(((uintptr_t)p + A-1) & -A);
}

static void test(const struct fun *fun, int align, int seekpos,
                 int str_len, int acc_len)
{
    char *src = alignup(sbuf);
    char *s = src + align;
    char *a = s + str_len + 1;
    size_t r, f = seekpos >= 0 ? seekpos : str_len;

    assert(align < A);
    assert(str_len + acc_len + 2 < LEN);
    assert(seekpos < str_len - 1);

    memset(src, '?', align + str_len + acc_len + A);

    for (int i = 0; i < acc_len; i++) {
        a[i] = 'a' + i % 26;
    }
    a[acc_len] = '\0';

    for (int i = 0; i < str_len; i++) {
        s[i] = 'a' + i % (acc_len < 26 ? acc_len : 26);
    }
    s[str_len] = '\0';

    if (seekpos >= 0) {
        s[seekpos] = 'X';
    }

    r = fun->fun(s, a);

    if (r != f) {
        ERR("%s(%p,%p) returned %zd, expected %zd\n",
            fun->name, s, a, r, f);
        /* abort(); */
    }
}

int main()
{
    int r = 0;
    for (int i = 0; i < ARRAY_SIZE(funtab); ++i) {
        test_status = 0;
        for (int a = 0; a < A; a++) {
            for (int n = 1; n < 100; n++) {
                for (int m = 1; m < 100; m++) {
                    for (int sp = 0; sp < n - 1; sp++) {
                        test(funtab+i, a, sp, n, m);
                    }
                    test(funtab+i, a, -1, n, m);
                }
            }
            for (int n = 200; n < LEN; n *= 2) {
                for (int m = 1; m < 300; m += 10) {
                    test(funtab+i, a, -1, n, m);
                    test(funtab+i, a, n / 2, n, m);
                }
            }
        }
        printf("%s %s\n", test_status ? "FAIL" : "PASS", funtab[i].name);
        if (test_status) {
            r = -1;
        }
    }
    return r;
}
