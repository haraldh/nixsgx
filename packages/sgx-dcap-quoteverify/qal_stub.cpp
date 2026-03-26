/*
 * Stub for tee_qae_get_target_info from the QAL (Quote Appraisal Library).
 * The real implementation loads the QAE enclave, which requires SGX hardware.
 * On non-SGX platforms (e.g. macOS), this stub returns an error so the
 * quoteverify library gracefully falls back to the QVL-only code path.
 *
 * On Linux, the shared library linker allows unresolved symbols by default,
 * so this stub is not needed there. On macOS, -dynamiclib requires all
 * symbols to be resolved at link time.
 */
#include "sgx_ql_lib_common.h"
#include "sgx_report.h"

quote3_error_t tee_qae_get_target_info(sgx_target_info_t *)
{
    return SGX_QL_ERROR_UNEXPECTED;
}
