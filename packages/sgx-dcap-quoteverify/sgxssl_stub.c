/*
 * Stub for sgx_usgxssl untrusted library.
 * The real library provides OCall wrappers for SGXSSL enclaves.
 * These are only called when running inside an SGX enclave context,
 * which requires SGX hardware. The quoteverify library loads the
 * QvE enclave dynamically via dlopen, so these stubs are sufficient
 * for the non-enclave (QVL) code path.
 */
#include <sys/time.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>

void u_sgxssl_ftime(void *timeptr, uint32_t timeb_len)
{
    (void)timeb_len;
    struct timeval tv;
    gettimeofday(&tv, NULL);
    /* struct timeb layout: time_t time; unsigned short millitm; ... */
    memset(timeptr, 0, timeb_len);
    memcpy(timeptr, &tv.tv_sec, sizeof(tv.tv_sec));
}

void u_sgxssl_usleep(unsigned int usec)
{
    usleep(usec);
}
