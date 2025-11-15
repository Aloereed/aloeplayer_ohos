/*
 * @Author: 
 * @Date: 2025-10-25 15:59:52
 * @LastEditors: 
 * @LastEditTime: 2025-10-25 15:59:59
 * @Description: file content
 */
#include <dlfcn.h>
#include <stdio.h>

extern "C" int load_with_global(const char* path) {
    if (!path) return 0;

    // 使用 RTLD_NOW | RTLD_GLOBAL，让符号对后续动态库可见
    void* handle = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
    if (!handle) {
        const char* err = dlerror();
        fprintf(stderr, "dlopen failed for %s: %s\n", path, err ? err : "unknown");
        return 0;
    }

    fprintf(stdout, "dlopen success for %s with RTLD_GLOBAL\n", path);
    return 1;
}
