/* Compile-only verification against the actual HarmonyOS aarch64 toolchain.
 * These sizes also match the executable Windows FFI regression fixture. */
#include <stdint.h>
#include <stddef.h>
#include <time.h>
#include <poll.h>
#include "smb2/smb2.h"
#include "smb2/libsmb2.h"
#include "smb2/libsmb2-dcerpc-srvsvc.h"
_Static_assert(sizeof(void *) == 8, "64-bit target required");
_Static_assert(sizeof(struct smb2_stat_64) == 88, "Dart Smb2Stat64 layout");
_Static_assert(sizeof(struct smb2dirent) == 96, "Dart Smb2Dirent layout");
_Static_assert(sizeof(struct dcerpc_utf16) == 32, "Dart DcerpcString layout");
_Static_assert(sizeof(struct srvsvc_SHARE_INFO_1) == 72, "Dart ShareInfo1 layout");
_Static_assert(sizeof(struct srvsvc_NetrShareEnum_rep) == 48, "Dart ShareEnumReply layout");
_Static_assert(offsetof(struct srvsvc_NetrShareEnum_rep, ses) == 8, "Reply field offset");
_Static_assert(sizeof(struct pollfd) == 8, "Dart POSIX pollfd layout");
