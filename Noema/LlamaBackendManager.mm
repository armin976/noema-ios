// LlamaBackendManager.mm
#import "LlamaBackendManager.h"
#if __has_include(<llama/llama.h>)
#import <llama/llama.h>
#elif __has_include("llama.h")
#import "llama.h"
#endif
#include <atomic>

static std::atomic<int> s_refcount{0};

void noema_llama_backend_addref(void) {
    int prev = s_refcount.fetch_add(1, std::memory_order_acq_rel);
    if (prev == 0) {
        llama_backend_init();
    }
}

void noema_llama_backend_release(void) {
    int prev = s_refcount.fetch_sub(1, std::memory_order_acq_rel);
    if (prev == 1) {
        llama_backend_free();
    }
}

int noema_llama_backend_refcount(void) {
    return s_refcount.load(std::memory_order_acquire);
}
