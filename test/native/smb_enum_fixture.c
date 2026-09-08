/* ABI regression fixture: deliberately uses the vendored upstream C layouts.
 * Build: gcc -shared -I libsmb2/include test/native/smb_enum_fixture.c -o build/smb_enum_fixture.dll
 * It never opens a network connection. */
#include <stdint.h>
#include <stddef.h>
#include <time.h>
#include <stdlib.h>
#include <string.h>
#include "smb2/smb2.h"
#include "smb2/libsmb2.h"
#include "smb2/libsmb2-dcerpc-srvsvc.h"

static smb2_command_cb pending;
static void *pending_data;
static int mode, freed, aborted;
static struct srvsvc_SHARE_INFO_1 entries[5];
static struct srvsvc_SHARE_INFO_1_carray array;
static struct srvsvc_NetrShareEnum_rep reply;

void fixture_reset(int value) { mode = value; freed = 0; aborted = 0; pending = NULL; }
int fixture_freed(void) { return freed; }
int fixture_aborted(void) { return aborted; }
int fixture_reply_size(void) { return sizeof(reply); }
int fixture_entry_size(void) { return sizeof(entries[0]); }
int smb2_share_enum_async(struct smb2_context *ctx, enum SHARE_INFO_enum level,
                         smb2_command_cb cb, void *data) {
    if (level != SHARE_INFO_1) return -22;
    if (mode == 3) return -13;
    pending = cb;
    pending_data = data;
    return 0;
}
t_socket smb2_get_fd(struct smb2_context *ctx) { return 1; }
int smb2_which_events(struct smb2_context *ctx) { return 1; }
int poll(void *fds, unsigned long count, int timeout) { return 1; }
void smb2_free_data(struct smb2_context *ctx, void *data) { if (data == &reply) freed++; }
int smb2_service(struct smb2_context *ctx, int revents) {
    if (mode == 4) return -1;
    if (!pending) return 0;
    entries[0].netname.utf8 = "Videos"; entries[0].type = SHARE_TYPE_DISKTREE;
    entries[1].netname.utf8 = "IPC$"; entries[1].type = SHARE_TYPE_IPC;
    entries[2].netname.utf8 = "C$"; entries[2].type = SHARE_TYPE_HIDDEN;
    entries[3].netname.utf8 = "Videos"; entries[3].type = SHARE_TYPE_DISKTREE;
    entries[4].netname.utf8 = "Printer"; entries[4].type = SHARE_TYPE_PRINTQ;
    array.max_count = 5; array.share_info_1 = entries;
    reply.status = 0;
    reply.ses.Level = 1; reply.ses.ShareInfo.Level = 1;
    reply.ses.ShareInfo.Level1.EntriesRead = mode == 2 ? 6 : 5;
    reply.ses.ShareInfo.Level1.Buffer = &array;
    reply.total_entries = 5;
    smb2_command_cb cb = pending; pending = NULL;
    cb(ctx, mode == 1 ? 5 : 0, &reply, pending_data);
    return 0;
}
void fixture_abort(struct smb2_context *ctx) {
    aborted++;
    if (pending) {
        smb2_command_cb cb = pending; pending = NULL;
        cb(ctx, -1, NULL, pending_data);
    }
}

struct fixture_context { char share[128]; int directory_index; };
struct fixture_handle { struct fixture_context *owner; };
static int active_contexts, active_handles, stat_failure, read_limit = 65536, short_read, read_calls;
static uint64_t file_size = 6;
static char last_path[1024];
int fixture_contexts(void) { return active_contexts; }
int fixture_handles(void) { return active_handles; }
int fixture_reads(void) { return read_calls; }
void fixture_read_mode(int value) {
    stat_failure = value == 1; short_read = value == 2; read_calls = 0;
    file_size = value >= 3 ? 8 * 1024 * 1024 : 6;
    read_limit = value == 3 ? 1024 * 1024 : 65536;
}
uint32_t smb2_get_max_read_size(struct smb2_context *ctx) { return read_limit; }
const char *fixture_last_path(void) { return last_path; }
struct smb2_context *smb2_init_context(void) {
    active_contexts++;
    return (struct smb2_context *)calloc(1, sizeof(struct fixture_context));
}
void smb2_destroy_context(struct smb2_context *ctx) { active_contexts--; free(ctx); }
void smb2_set_user(struct smb2_context *ctx, const char *value) {}
void smb2_set_password(struct smb2_context *ctx, const char *value) {}
void smb2_set_domain(struct smb2_context *ctx, const char *value) {}
void smb2_set_security_mode(struct smb2_context *ctx, uint16_t value) {}
void smb2_set_sign(struct smb2_context *ctx, int value) {}
void smb2_set_seal(struct smb2_context *ctx, int value) {}
void smb2_set_timeout(struct smb2_context *ctx, int value) {}
int smb2_connect_share(struct smb2_context *ctx, const char *server, const char *share, const char *user) {
    if (!strcmp(share, "Denied")) return -13;
    strncpy(((struct fixture_context *)ctx)->share, share, 127);
    return 0;
}
int smb2_disconnect_share(struct smb2_context *ctx) { return 0; }
const char *smb2_get_error(struct smb2_context *ctx) { return "fixture access denied"; }
struct smb2dir *smb2_opendir(struct smb2_context *ctx, const char *path) {
    strcpy(last_path, path);
    ((struct fixture_context *)ctx)->directory_index = 0;
    return (struct smb2dir *)ctx;
}
struct smb2dirent *smb2_readdir(struct smb2_context *ctx, struct smb2dir *dir) {
    static struct smb2dirent entry;
    if (((struct fixture_context *)ctx)->directory_index++) return NULL;
    entry.name = "clip #100%.mkv";
    entry.st.smb2_type = SMB2_TYPE_FILE;
    entry.st.smb2_size = 6;
    return &entry;
}
void smb2_closedir(struct smb2_context *ctx, struct smb2dir *dir) {}
struct smb2fh *smb2_open(struct smb2_context *ctx, const char *path, int flags) {
    struct fixture_handle *handle = calloc(1, sizeof(*handle));
    active_handles++;
    handle->owner = (struct fixture_context *)ctx;
    strcpy(last_path, path);
    return (struct smb2fh *)handle;
}
int smb2_close(struct smb2_context *ctx, struct smb2fh *handle) { active_handles--; free(handle); return 0; }
int smb2_fstat(struct smb2_context *ctx, struct smb2fh *handle, struct smb2_stat_64 *st) {
    if (stat_failure) return -13;
    memset(st, 0, sizeof(*st)); st->smb2_size = file_size; return 0;
}
int smb2_stat(struct smb2_context *ctx, const char *path, struct smb2_stat_64 *st) {
    strcpy(last_path, path);
    memset(st, 0, sizeof(*st));
    st->smb2_size = 6;
    st->smb2_type = *path ? SMB2_TYPE_FILE : SMB2_TYPE_DIRECTORY;
    return 0;
}
int smb2_pread(struct smb2_context *ctx, struct smb2fh *handle, uint8_t *buf, uint32_t count, uint64_t offset) {
    read_calls++;
    if (short_read) return 0;
    if (count > read_limit) return -22;
    if (((struct fixture_handle *)handle)->owner != (struct fixture_context *)ctx) return -22;
    if (offset >= file_size) return 0;
    if (count > file_size - offset) count = file_size - offset;
    for (uint32_t i = 0; i < count; i++) buf[i] = (uint8_t)(offset + i);
    return count;
}
int64_t smb2_lseek(struct smb2_context *ctx, struct smb2fh *handle, int64_t offset, int whence, uint64_t *current) {
    *current = offset; return offset;
}
