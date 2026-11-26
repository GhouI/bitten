/* ServiceManagement: there is no launchd to hand jobs to. Submitting or
 * removing a job fails with an error saying so; the domains exist. */
#include <stdbool.h>

#include "../corefoundation/cf.h"

static const struct cf_string *d_kSMDomainSystemLaunchd, *d_kSMDomainUserLaunchd, *d_kSMErrorDomainLaunchd;
DX_EXPORT("_kSMDomainSystemLaunchd", &d_kSMDomainSystemLaunchd);
DX_EXPORT("_kSMDomainUserLaunchd", &d_kSMDomainUserLaunchd);
DX_EXPORT("_kSMErrorDomainLaunchd", &d_kSMErrorDomainLaunchd);
__attribute__((constructor)) static void sm_init(void) {
    d_kSMDomainSystemLaunchd = d___CFStringMakeConstantString("kSMDomainSystemLaunchd");
    d_kSMDomainUserLaunchd = d___CFStringMakeConstantString("kSMDomainUserLaunchd");
    d_kSMErrorDomainLaunchd = d___CFStringMakeConstantString("kSMErrorDomainLaunchd");
}

enum { SM_ERROR_INTERNAL = 2, SM_ERROR_JOB_NOT_FOUND = 6 };   /* kSMErrorInternalFailure, kSMErrorJobNotFound */

static void fail(struct cf_error **error, CFIndex code) {
    if (error) *error = d_CFErrorCreate(NULL, d_kSMErrorDomainLaunchd, code, NULL);
}

static Boolean d_SMJobSubmit(const void *domain, const void *job, const void *auth, struct cf_error **error) {
    fail(error, SM_ERROR_INTERNAL);
    return 0;
}
DX_FN(SMJobSubmit);
static Boolean d_SMJobRemove(const void *domain, const void *label, const void *auth, Boolean wait, struct cf_error **error) {
    fail(error, SM_ERROR_JOB_NOT_FOUND);
    return 0;
}
DX_FN(SMJobRemove);
static Boolean d_SMJobBless(const void *domain, const void *label, const void *auth, struct cf_error **error) {
    fail(error, SM_ERROR_INTERNAL);
    return 0;
}
DX_FN(SMJobBless);
static const void *d_SMJobCopyDictionary(const void *domain, const void *label) { return NULL; }
DX_FN(SMJobCopyDictionary);
static Boolean d_SMLoginItemSetEnabled(const void *identifier, Boolean enabled) { return 0; }
DX_FN(SMLoginItemSetEnabled);
