// LlamaBackendManager.mm
#import "LlamaBackendManager.h"
#if __has_include(<llama/llama.h>)
#import <llama/llama.h>
#elif __has_include("llama.h")
#import "llama.h"
#endif
#import <Foundation/Foundation.h>
#include <atomic>

static void noema_llama_log_forward(enum ggml_log_level level, const char * text, void * user_data) {
    (void)level;
    (void)user_data;
    if (text == nullptr) { return; }

    fputs(text, stderr);

    NSString *message = [[NSString alloc] initWithUTF8String:text];
    if (message.length == 0) { return; }

    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *userInfo = @{ @"level": @(level), @"message": message };
        [[NSNotificationCenter defaultCenter] postNotificationName:@"Noema.llamaLogMessage"
                                                            object:nil
                                                          userInfo:userInfo];
    });
}

static std::atomic<int> s_refcount{0};

void noema_llama_backend_addref(void) {
    int prev = s_refcount.fetch_add(1, std::memory_order_acq_rel);
    if (prev == 0) {
        llama_backend_init();
        llama_log_set(noema_llama_log_forward, nullptr);
    }
}

void noema_llama_backend_release(void) {
    int prev = s_refcount.fetch_sub(1, std::memory_order_acq_rel);
    if (prev == 1) {
        llama_log_set(nullptr, nullptr);
        llama_backend_free();
    }
}

int noema_llama_backend_refcount(void) {
    return s_refcount.load(std::memory_order_acquire);
}
