// GGUFScanner.c

#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <mach/mach.h>
#include <os/proc.h>

enum gguf_type {
    GGUF_TYPE_UINT8   = 0,
    GGUF_TYPE_INT8    = 1,
    GGUF_TYPE_UINT16  = 2,
    GGUF_TYPE_INT16   = 3,
    GGUF_TYPE_UINT32  = 4,
    GGUF_TYPE_INT32   = 5,
    GGUF_TYPE_FLOAT32 = 6,
    GGUF_TYPE_BOOL    = 7,
    GGUF_TYPE_STRING  = 8,
    GGUF_TYPE_ARRAY   = 9,
    GGUF_TYPE_UINT64  = 10,
    GGUF_TYPE_INT64   = 11,
    GGUF_TYPE_FLOAT64 = 12,
};

static uint32_t read_u32(FILE *f) {
    uint32_t v = 0;
    long pos = ftell(f);
    if (fread(&v, sizeof(v), 1, f) != 1) {
        clearerr(f);
        if (pos >= 0) {
            fseek(f, pos, SEEK_SET);
        }
        return 0;
    }
    return v;
}

static uint64_t read_u64(FILE *f) {
    uint64_t v = 0;
    long pos = ftell(f);
    if (fread(&v, sizeof(v), 1, f) != 1) {
        clearerr(f);
        if (pos >= 0) {
            fseek(f, pos, SEEK_SET);
        }
        return 0;
    }
    return v;
}

int32_t gguf_layer_count(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return 0;
    char magic[4];
    if (fread(magic, 1, 4, f) != 4 || memcmp(magic, "GGUF", 4) != 0) {
        fclose(f);
        return 0;
    }
    (void)read_u32(f); // version (ignored)
    (void)read_u64(f); // tensor count (ignored)
    uint64_t kv_count = read_u64(f);
    for (uint64_t i = 0; i < kv_count; ++i) {
        uint64_t key_len = read_u64(f);
        if (key_len > 1024) { fclose(f); return 0; }
        char key[1025];
        long pos = ftell(f);
        if (fread(key, 1, key_len, f) != key_len) {
            clearerr(f);
            if (pos >= 0) {
                fseek(f, pos, SEEK_SET);
            }
            fclose(f);
            return 0;
        }
        key[key_len] = '\0';
        uint32_t type = read_u32(f);
        if (strcmp(key, "hparams.n_layer") == 0 &&
            (type == GGUF_TYPE_INT32 || type == GGUF_TYPE_UINT32)) {
            int32_t val = (int32_t)read_u32(f);
            fclose(f);
            return val;
        } else {
            switch (type) {
                case GGUF_TYPE_UINT8:
                case GGUF_TYPE_INT8:
                case GGUF_TYPE_BOOL:
                    if (fseek(f, 1, SEEK_CUR) != 0) { fclose(f); return 0; } break;
                case GGUF_TYPE_UINT16:
                case GGUF_TYPE_INT16:
                    if (fseek(f, 2, SEEK_CUR) != 0) { fclose(f); return 0; } break;
                case GGUF_TYPE_UINT32:
                case GGUF_TYPE_INT32:
                case GGUF_TYPE_FLOAT32:
                    if (fseek(f, 4, SEEK_CUR) != 0) { fclose(f); return 0; } break;
                case GGUF_TYPE_UINT64:
                case GGUF_TYPE_INT64:
                case GGUF_TYPE_FLOAT64:
                    if (fseek(f, 8, SEEK_CUR) != 0) { fclose(f); return 0; } break;
                case GGUF_TYPE_STRING: {
                    uint64_t len = read_u64(f);
                    if (fseek(f, (long)len, SEEK_CUR) != 0) { fclose(f); return 0; } break; }
                case GGUF_TYPE_ARRAY: {
                    uint32_t et = read_u32(f);
                    uint64_t n = read_u64(f);
                    size_t sz;
                    switch (et) {
                        case GGUF_TYPE_UINT8:
                        case GGUF_TYPE_INT8:
                        case GGUF_TYPE_BOOL: sz = 1; break;
                        case GGUF_TYPE_UINT16:
                        case GGUF_TYPE_INT16: sz = 2; break;
                        case GGUF_TYPE_UINT32:
                        case GGUF_TYPE_INT32:
                        case GGUF_TYPE_FLOAT32: sz = 4; break;
                        case GGUF_TYPE_UINT64:
                        case GGUF_TYPE_INT64:
                        case GGUF_TYPE_FLOAT64: sz = 8; break;
                        case GGUF_TYPE_STRING: sz = 0; break;
                        default: sz = 0; break;
                    }
                    if (et == GGUF_TYPE_STRING) {
                        for (uint64_t j = 0; j < n; ++j) {
                            uint64_t len = read_u64(f);
                            if (fseek(f, (long)len, SEEK_CUR) != 0) { fclose(f); return 0; }
                        }
                    } else {
                        if (sz == 0) { fclose(f); return 0; }
                        // Guard against overflow before casting to long
                        if (n > SIZE_MAX / sz) { fclose(f); return 0; }
                        size_t bytes = sz * n;
                        if (fseek(f, (long)bytes, SEEK_CUR) != 0) { fclose(f); return 0; }
                    }
                    break; }
                default:
                    fclose(f); return 0;
            }
        }
    }
    fclose(f);
    return 0;
}

size_t app_memory_footprint(void) {
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    kern_return_t kr = task_info(mach_task_self_, TASK_VM_INFO, (task_info_t)&info, &count);
    if (kr != KERN_SUCCESS) return 0;
    // Use phys_footprint as approximation of current memory usage in bytes
    return (size_t)info.phys_footprint;
}

size_t app_available_memory(void) {
    size_t avail = os_proc_available_memory();
    // Always print available memory to the console for diagnostics.
    // Use fprintf to stderr to ensure it appears in console logs.
    fprintf(stderr, "[GGUFScanner] app_available_memory: %zu bytes\n", avail);
    return avail;
}
