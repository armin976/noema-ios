// Noema-Bridging.h
#import <Foundation/Foundation.h>
#import <stdint.h>

// Make XCFramework C API visible to Swift when available
#if __has_include(<llama/llama.h>)
#import <llama/llama.h>
#elif __has_include(<LlamaFramework/llama.h>)
#import <LlamaFramework/llama.h>
#elif __has_include("llama.h")
#import "llama.h"
#endif

// Expose ggml backend when available so Objective-C++ files can rely on it
#if __has_include(<ggml/ggml-backend.h>)
#import <ggml/ggml-backend.h>
#elif __has_include(<ggml-backend.h>)
#import <ggml-backend.h>
#elif __has_include("ggml-backend.h")
#import "ggml-backend.h"
#endif

#ifdef __cplusplus
extern "C" {
#endif

int32_t gguf_layer_count(const char *path);
size_t app_memory_footprint(void);

struct gguf_moe_scan_result {
    int32_t status;
    int32_t is_moe;
    int32_t expert_count;
    int32_t expert_used_count;
    int32_t total_layer_count;
    int32_t moe_layer_count;
    int32_t hidden_size;
    int32_t feed_forward_size;
    int32_t vocab_size;
};

int gguf_moe_scan(const char *path, struct gguf_moe_scan_result *out_result);

#ifdef __cplusplus
}
#endif

// Expose minimal Objective-C++ bridges to Swift
#if __has_include("LlamaRunner.h")
#import "LlamaRunner.h"
#endif
#if __has_include("LlamaEmbedder.h")
#import "LlamaEmbedder.h"
#endif
#if __has_include("LlamaVisionShims.h")
#import "LlamaVisionShims.h"
#endif
#if __has_include("LlamaBackendManager.h")
#import "LlamaBackendManager.h"
#endif
#if __has_include("LlamaSwiftBatchHelpers.h")
#import "LlamaSwiftBatchHelpers.h"
#endif
