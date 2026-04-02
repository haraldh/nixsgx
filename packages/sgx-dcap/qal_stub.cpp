/*
 * Stub for tee_qae_get_target_info from the QAL (Quote Appraisal Library).
 * The real implementation loads the QAE enclave, which requires SGX hardware.
 * Since we only build the QVL (software-only) path, this stub returns an
 * error so callers gracefully skip the QAE code path.
 */
#include "sgx_ql_lib_common.h"
#include "sgx_report.h"

quote3_error_t tee_qae_get_target_info(sgx_target_info_t *)
{
    return SGX_QL_ERROR_UNEXPECTED;
}
