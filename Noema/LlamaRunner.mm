// LlamaRunner.mm
#import "LlamaRunner.h"
#import <Foundation/Foundation.h>
#include <vector>
#include <string>
#include <algorithm>
#include <atomic>
#include <cstdint>
#include <cstdlib>
#include <type_traits>
// Build-time configuration for llama.cpp capabilities
#import "NoemaLlamaConfig.h"
#import "LlamaBackendManager.h"
#if __has_include(<llama/llama.h>)
#import <llama/llama.h>
#elif __has_include(<LlamaFramework/llama.h>)
#import <LlamaFramework/llama.h>
#else
#import "llama.h"
#endif

// Optional vision headers (present in vision-enabled llama builds)
#if __has_include(<llama/llava.h>)
#include <llama/llava.h>
#define NOEMA_HAS_LLAVA 1
#elif __has_include("llava.h")
#include "llava.h"
#define NOEMA_HAS_LLAVA 1
#endif

#if __has_include(<llama/clip.h>)
#include <llama/clip.h>
#define NOEMA_HAS_CLIP 1
#elif __has_include("clip.h")
#include "clip.h"
#define NOEMA_HAS_CLIP 1
#endif

// Compatibility shims for clearing the KV cache across llama.cpp versions.
#if defined(__APPLE__)
extern "C" {
__attribute__((weak_import)) LLAMA_API llama_memory_t llama_get_memory(const struct llama_context * ctx);
__attribute__((weak_import)) LLAMA_API void llama_memory_clear(llama_memory_t mem, bool data);
__attribute__((weak_import)) LLAMA_API bool llama_memory_seq_rm(llama_memory_t mem, llama_seq_id seq_id, llama_pos p0, llama_pos p1);
}
#else
extern "C" {
LLAMA_API llama_memory_t llama_get_memory(const struct llama_context * ctx);
LLAMA_API void llama_memory_clear(llama_memory_t mem, bool data);
LLAMA_API bool llama_memory_seq_rm(llama_memory_t mem, llama_seq_id seq_id, llama_pos p0, llama_pos p1);
}
#endif

static inline void noema_llama_kv_cache_clear(struct llama_context * ctx, bool clearData) {
#if defined(__APPLE__)
  using llama_get_memory_fn = llama_memory_t (*)(const struct llama_context *);
  using llama_memory_clear_fn = void (*)(llama_memory_t, bool);
  using llama_memory_seq_rm_fn = bool (*)(llama_memory_t, llama_seq_id, llama_pos, llama_pos);

  llama_get_memory_fn p_get_memory = (llama_get_memory_fn)llama_get_memory;
  llama_memory_clear_fn p_memory_clear = (llama_memory_clear_fn)llama_memory_clear;
  llama_memory_seq_rm_fn p_memory_seq_rm = (llama_memory_seq_rm_fn)llama_memory_seq_rm;

  if (p_memory_seq_rm && p_get_memory) {
    (void)p_memory_seq_rm(p_get_memory(ctx), 0, -1, -1);
  } else if (p_memory_clear && p_get_memory) {
    p_memory_clear(p_get_memory(ctx), clearData);
  }
#else
  llama_memory_t mem = llama_get_memory(ctx);
  (void)llama_memory_seq_rm(mem, 0, -1, -1);
  if (clearData) {
    llama_memory_clear(mem, /*data=*/true);
  }
#endif
}

// (Removed) Legacy helper functions for batch operations; using direct batch API instead

// --- KV cache type mappers ---
static inline bool noema_equals_ci(const char *a, const char *b) {
  if (!a || !b) return false;
  while (*a && *b) {
    char ca = (*a >= 'a' && *a <= 'z') ? (char)(*a - 32) : *a;
    char cb = (*b >= 'a' && *b <= 'z') ? (char)(*b - 32) : *b;
    if (ca != cb) return false;
    ++a;
    ++b;
  }
  return *a == 0 && *b == 0;
}

static inline ggml_type noema_map_kv_type(NOEMAKVCacheType t) {
  switch (t) {
    case NOEMAKVCacheTypeF32:   return GGML_TYPE_F32;
    case NOEMAKVCacheTypeF16:   return GGML_TYPE_F16;
    case NOEMAKVCacheTypeQ8_0:  return GGML_TYPE_Q8_0;
    case NOEMAKVCacheTypeQ5_0:  return GGML_TYPE_Q5_0;
    case NOEMAKVCacheTypeQ5_1:  return GGML_TYPE_Q5_1;
    case NOEMAKVCacheTypeQ4_0:  return GGML_TYPE_Q4_0;
    case NOEMAKVCacheTypeQ4_1:  return GGML_TYPE_Q4_1;
    case NOEMAKVCacheTypeIQ4_NL:return GGML_TYPE_IQ4_NL;
  }
  return GGML_TYPE_F16;
}

static inline const char * noema_kv_type_name(ggml_type t) {
  switch (t) {
    case GGML_TYPE_F32:   return "f32";
    case GGML_TYPE_F16:   return "f16";
    case GGML_TYPE_Q8_0:  return "q8_0";
    case GGML_TYPE_Q5_0:  return "q5_0";
    case GGML_TYPE_Q5_1:  return "q5_1";
    case GGML_TYPE_Q4_0:  return "q4_0";
    case GGML_TYPE_Q4_1:  return "q4_1";
    case GGML_TYPE_IQ4_NL:return "iq4_nl";
    default:              return "unknown";
  }
}

// Parse a KV quant string (e.g., "F16", "Q4_1", "IQ4_NL") into a ggml_type.
// Returns true if recognized; false otherwise.
static inline bool noema_parse_kv_string(const char * s, ggml_type * out) {
  if (s == NULL || out == NULL) return false;
  if (noema_equals_ci(s, "F32"))      { *out = GGML_TYPE_F32;   return true; }
  if (noema_equals_ci(s, "F16"))      { *out = GGML_TYPE_F16;   return true; }
  if (noema_equals_ci(s, "Q8_0"))     { *out = GGML_TYPE_Q8_0;  return true; }
  if (noema_equals_ci(s, "Q5_0"))     { *out = GGML_TYPE_Q5_0;  return true; }
  if (noema_equals_ci(s, "Q5_1"))     { *out = GGML_TYPE_Q5_1;  return true; }
  if (noema_equals_ci(s, "Q4_0"))     { *out = GGML_TYPE_Q4_0;  return true; }
  if (noema_equals_ci(s, "Q4_1"))     { *out = GGML_TYPE_Q4_1;  return true; }
  if (noema_equals_ci(s, "IQ4_NL"))   { *out = GGML_TYPE_IQ4_NL;return true; }
  // Also accept lowercase llama.cpp spellings
  if (noema_equals_ci(s, "iq4_nl"))   { *out = GGML_TYPE_IQ4_NL;return true; }
  return false;
}

static inline llama_flash_attn_type noema_parse_flash_string(const char *s) {
  if (s == NULL) return LLAMA_FLASH_ATTN_TYPE_AUTO;
  if (noema_equals_ci(s, "auto"))     return LLAMA_FLASH_ATTN_TYPE_AUTO;
  if (noema_equals_ci(s, "enabled"))  return LLAMA_FLASH_ATTN_TYPE_ENABLED;
  if (noema_equals_ci(s, "on"))       return LLAMA_FLASH_ATTN_TYPE_ENABLED;
  if (noema_equals_ci(s, "disabled")) return LLAMA_FLASH_ATTN_TYPE_DISABLED;
  if (noema_equals_ci(s, "off"))      return LLAMA_FLASH_ATTN_TYPE_DISABLED;
  int val = atoi(s);
  if (val < 0) return LLAMA_FLASH_ATTN_TYPE_AUTO;
  if (val > 0) return LLAMA_FLASH_ATTN_TYPE_ENABLED;
  return LLAMA_FLASH_ATTN_TYPE_DISABLED;
}

namespace {

template <typename T, typename = void>
struct noema_has_member_type_k : std::false_type {};

template <typename T>
struct noema_has_member_type_k<T, std::void_t<decltype(((T *)nullptr)->type_k)>>
    : std::true_type {};

template <typename T, typename = void>
struct noema_has_member_type_v : std::false_type {};

template <typename T>
struct noema_has_member_type_v<T, std::void_t<decltype(((T *)nullptr)->type_v)>>
    : std::true_type {};

}  // namespace

static inline void noema_apply_flash_and_kv_params(struct llama_context_params &cparams,
                                                   NOEMAKVCacheConfig cfg,
                                                   ggml_type *resolvedK,
                                                   ggml_type *resolvedV,
                                                   bool *usedMergedFallback,
                                                   ggml_type *mergedOut) {
  if (usedMergedFallback) { *usedMergedFallback = false; }
  if (mergedOut) { *mergedOut = GGML_TYPE_F16; }
  const char *env_fa = getenv("LLAMA_FLASH_ATTENTION");
  cparams.flash_attn_type = noema_parse_flash_string(env_fa);

  ggml_type kType = GGML_TYPE_F16;
  ggml_type vType = GGML_TYPE_F16;
  const char *env_k = getenv("LLAMA_K_QUANT");
  const char *env_v = getenv("LLAMA_V_QUANT");
  ggml_type parsed;
  if (env_k && noema_parse_kv_string(env_k, &parsed)) { kType = parsed; }
  if (env_v && noema_parse_kv_string(env_v, &parsed)) { vType = parsed; }
  if (cfg.enabled) {
    kType = noema_map_kv_type(cfg.typeK);
    vType = noema_map_kv_type(cfg.typeV);
  }

  if (resolvedK) { *resolvedK = kType; }
  if (resolvedV) { *resolvedV = vType; }

  constexpr bool hasSeparateKVTypes =
      noema_has_member_type_k<llama_context_params>::value &&
      noema_has_member_type_v<llama_context_params>::value;
  if constexpr (hasSeparateKVTypes) {
    cparams.type_k = kType;
    cparams.type_v = vType;
  } else {
    ggml_type merged = (kType == GGML_TYPE_F32 || vType == GGML_TYPE_F32) ? GGML_TYPE_F32 :
                       (kType == GGML_TYPE_F16 || vType == GGML_TYPE_F16) ? GGML_TYPE_F16 :
                       (kType == GGML_TYPE_Q8_0 || vType == GGML_TYPE_Q8_0) ? GGML_TYPE_Q8_0 :
                       (kType == GGML_TYPE_Q5_1 || vType == GGML_TYPE_Q5_1) ? GGML_TYPE_Q5_1 :
                       (kType == GGML_TYPE_Q5_0 || vType == GGML_TYPE_Q5_0) ? GGML_TYPE_Q5_0 :
                       (kType == GGML_TYPE_IQ4_NL || vType == GGML_TYPE_IQ4_NL) ? GGML_TYPE_IQ4_NL :
                       GGML_TYPE_Q4_0;

    cparams.type_k = merged;
    cparams.type_v = merged;

    if (usedMergedFallback) { *usedMergedFallback = true; }
    if (mergedOut) { *mergedOut = merged; }
  }
}

// Preprocess provided images and prime the llama context with vision embeddings.
// Returns the number of image prefix tokens appended to the context (pos offset for subsequent text), or -1 on error.
static int noema_llava_prime_with_images(
    llama_model * model,
    llama_context * ctx,
    const std::vector<std::string> & image_paths,
    int n_threads) {
#if defined(NOEMA_HAS_LLAVA) && defined(NOEMA_HAS_CLIP)
    if (!model || !ctx || image_paths.empty()) { return 0; }
    int total_prefix = 0;
    for (const auto & path : image_paths) {
        // Load image into CLIP-friendly buffer
        struct clip_image_u8 img_u8 = {0};
        bool ok_load = clip_image_load_from_file(path.c_str(), &img_u8);
        if (!ok_load) {
            return -1;
        }
        struct clip_image_f32 img_f32 = {0};
        bool ok_f32 = clip_image_f32_from_u8(&img_f32, &img_u8);
        clip_image_u8_free(&img_u8);
        if (!ok_f32) {
            clip_image_f32_free(&img_f32);
            return -1;
        }
        // Create image embed using the current llama model (expects integrated mmproj in GGUF)
        struct llava_image_embed * embed = nullptr;
        bool ok_embed = llava_image_embed_make_with_model(model, &img_f32, /*n_images*/ 1, &embed, n_threads);
        clip_image_f32_free(&img_f32);
        if (!ok_embed || embed == nullptr) {
            if (embed) { llava_image_embed_free(embed); }
            // Return a specific error code for "not a vision model"
            return -2;
        }
        // Evaluate/embed into llama context; obtain prefix token count if available
        int n_pfx = llava_eval_image_embed(ctx, embed);
        if (n_pfx < 0) { n_pfx = 0; }
        total_prefix += n_pfx;
        llava_image_embed_free(embed);
    }
    return total_prefix;
#else
    (void)model; (void)ctx; (void)image_paths; (void)n_threads;
    return -1;
#endif
}

// Construct a robust default sampler chain.
// Uses temperature + top-k to avoid empty candidate sets.
// Optional top-p/typical lines are left commented with min_keep = 1 for safe experimentation.
static llama_sampler * noema_make_default_sampler() {
  auto *chain = llama_sampler_chain_init(llama_sampler_chain_default_params());
  llama_sampler_chain_add(chain, llama_sampler_init_temp(0.7f));
  llama_sampler_chain_add(chain, llama_sampler_init_top_k(40));
  // Optional samplers (enable one, keep values loose, and do not stack tightly):
  // llama_sampler_chain_add(chain, llama_sampler_init_top_p(0.90f, 1));
  // llama_sampler_chain_add(chain, llama_sampler_init_typical(1.0f, 1));
  // Add greedy sampler to the chain so a greedy fallback is available inside the chain
  llama_sampler_chain_add(chain, llama_sampler_init_greedy());
  return chain;
}


@interface LlamaRunner ()
@property (atomic, assign) NOEMAKVCacheConfig kvConfig;
@end


@implementation LlamaRunner {
  llama_model *_model;
  llama_context *_ctx;
  bool _loaded;
  int _nThreads;
  bool _verbose;
  std::atomic<bool> _cancelRequested;
}

- (instancetype)init {
  self = [super init];
  if (!self) return nil;
  // Default = disabled: use F16/F16
  NOEMAKVCacheConfig def;
  def.enabled = NO;
  def.typeK = NOEMAKVCacheTypeF16;
  def.typeV = NOEMAKVCacheTypeF16;
  _kvConfig = def;
  return self;
}

- (void)setKVCacheConfig:(NOEMAKVCacheConfig)config { _kvConfig = config; }
- (NOEMAKVCacheConfig)kvCacheConfig { return _kvConfig; }

- (nullable instancetype)initWithModelPath:(NSString *)modelPath
                       nCtxTokens:(int)nCtx
                       nGpuLayers:(int)nGpu
                           nThreads:(int)nThreads {
  return [self initWithModelPath:modelPath nCtxTokens:nCtx nSeqMax:1 nGpuLayers:nGpu nThreads:nThreads];
}

- (nullable instancetype)initWithModelPath:(NSString *)modelPath
                       mmprojPath:(NSString * _Nullable)mmprojPath
                       nCtxTokens:(int)nCtx
                       nGpuLayers:(int)nGpu
                           nThreads:(int)nThreads {
  return [self initWithModelPath:modelPath mmprojPath:mmprojPath nCtxTokens:nCtx nSeqMax:1 nGpuLayers:nGpu nThreads:nThreads];
}

- (void)cancelCurrent {
  _cancelRequested.store(true);
}

// Designated initializers with explicit sequence parallelism
- (nullable instancetype)initWithModelPath:(NSString *)modelPath
                       nCtxTokens:(int)nCtx
                          nSeqMax:(int)nSeqMax
                       nGpuLayers:(int)nGpu
                           nThreads:(int)nThreads {
  self = [super init];
  if (!self) return nil;

  const char *v = getenv("NOEMA_LLAMA_VERBOSE");
  _verbose = (v && atoi(v) != 0);

  noema_llama_backend_addref();

#if TARGET_OS_IPHONE || TARGET_OS_OSX
  if (nGpu > 0) {
    @autoreleasepool {
      NSBundle *bundle = [NSBundle mainBundle];
      NSString *metallibPath = [bundle pathForResource:@"default" ofType:@"metallib"];
      if (metallibPath.length > 0) {
        if (_verbose) NSLog(@"[LlamaRunner] Metal kernels found: %@", metallibPath);
        setenv("LLAMA_METAL_PATH", metallibPath.UTF8String, 1);
      } else {
        NSLog(@"[LlamaRunner] Warning: default.metallib not found in bundle. Falling back to CPU if needed.");
      }
    }
  } else {
    unsetenv("LLAMA_METAL_PATH");
  }
#endif

  struct llama_model_params mparams = llama_model_default_params();
  mparams.n_gpu_layers = nGpu;
  mparams.main_gpu = 0;
  static ggml_backend_dev_t cpu_devices[2];
  if (nGpu <= 0) {
    ggml_backend_dev_t cpu = ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_CPU);
    cpu_devices[0] = cpu;
    cpu_devices[1] = NULL;
    mparams.devices = cpu_devices;
  }
  // Default to mmap on unless explicitly disabled via environment
#if defined(LLAMA_MODEL_PARAMS_HAS_USE_MMAP)
  {
    bool use_mmap = true;
    const char *env_mmap = getenv("LLAMA_MMAP");
    if (env_mmap != NULL) {
      use_mmap = (atoi(env_mmap) != 0);
    }
    mparams.use_mmap = use_mmap;
  }
#endif

  _model = llama_load_model_from_file([modelPath UTF8String], mparams);
  if (!_model) { noema_llama_backend_release(); return nil; }

  struct llama_context_params cparams = llama_context_default_params();
  int effective_n_ctx = nCtx;
#if defined(NOEMA_HAS_LLAVA) && defined(NOEMA_HAS_CLIP)
  if (nCtx < 8192) {
    NSLog(@"[LlamaRunner] Warning: nCtx of %d may be too small for multimodal use; increasing to 8192.", nCtx);
    effective_n_ctx = 8192;
  }
#endif
  // Clamp to model's training context to avoid oversizing
  {
    const int train_ctx = llama_n_ctx_train(_model);
    if (train_ctx > 0 && effective_n_ctx > train_ctx) {
      if (_verbose) NSLog(@"[LlamaRunner] Clamping n_ctx from %d to model train ctx %d", effective_n_ctx, train_ctx);
      effective_n_ctx = train_ctx;
    }
  }
  cparams.n_ctx = effective_n_ctx;
  cparams.n_threads = nThreads;
  cparams.n_threads_batch = nThreads;
  cparams.n_seq_max = std::max(1, nSeqMax);
  // Match context batching to our batch allocations to avoid logits array mismatches
  cparams.n_batch = 512;
  cparams.n_ubatch = 512;
  ggml_type resolvedK = GGML_TYPE_F16;
  ggml_type resolvedV = GGML_TYPE_F16;
  bool usedMerged = false;
  ggml_type mergedType = GGML_TYPE_F16;
  noema_apply_flash_and_kv_params(cparams, self.kvConfig, &resolvedK, &resolvedV, &usedMerged, &mergedType);
  if (_verbose && usedMerged) {
    NSLog(@"[Noema] Warning: llama.cpp too old for separate K/V cache types. Using merged cache type=%s.", noema_kv_type_name(mergedType));
  }

  // Soft validator/warnings
  auto warn_if_shady = [](ggml_type t){
    switch (t) {
      case GGML_TYPE_F32:
        fprintf(stderr, "[Noema] Note: KV F32 is for debugging; expect 2x memory vs F16.\n");
        break;
      default: break;
    }
  };
  warn_if_shady(resolvedK);
  warn_if_shady(resolvedV);

  // Pre-flight parameter validation to avoid ggml_abort on tiny per-seq contexts
  const int n_ctx_per_seq = cparams.n_ctx / (cparams.n_seq_max > 0 ? cparams.n_seq_max : 1);
  const int n_ctx_train = llama_n_ctx_train(_model);
  const int minimum_required_ctx = 2048;
  if (n_ctx_per_seq < minimum_required_ctx) {
    NSLog(@"[LlamaRunner] Error: Per-sequence context length too small (%d). Required at least %d. Train ctx: %d.", n_ctx_per_seq, minimum_required_ctx, n_ctx_train);
      llama_model_free(_model);
    _model = nullptr;
    _loaded = false;
    noema_llama_backend_release();
    return nil;
  }

  _ctx = llama_init_from_model(_model, cparams);
  if (_ctx == nullptr) {
      llama_model_free(_model);
    _model = nullptr;
    _loaded = false;
    noema_llama_backend_release();
    return nil;
  }
  llama_set_n_threads(_ctx, nThreads, nThreads);
  _loaded = true;
  _nThreads = nThreads;

  if (_verbose) {
    NSLog(@"[LlamaRunner] Context ready. n_ctx=%d, n_seq_max=%d, n_gpu_layers=%d", llama_n_ctx(_ctx), cparams.n_seq_max, nGpu);
  }

  return self;
}

- (nullable instancetype)initWithModelPath:(NSString *)modelPath
                       mmprojPath:(NSString * _Nullable)mmprojPath
                       nCtxTokens:(int)nCtx
                          nSeqMax:(int)nSeqMax
                       nGpuLayers:(int)nGpu
                           nThreads:(int)nThreads {
  self = [super init];
  if (!self) return nil;

  const char *v = getenv("NOEMA_LLAMA_VERBOSE");
  _verbose = (v && atoi(v) != 0);
  noema_llama_backend_addref();

#if TARGET_OS_IPHONE || TARGET_OS_OSX
  if (nGpu > 0) {
    @autoreleasepool {
      NSBundle *bundle = [NSBundle mainBundle];
      NSString *metallibPath = [bundle pathForResource:@"default" ofType:@"metallib"];
      if (metallibPath.length > 0) {
        if (_verbose) NSLog(@"[LlamaRunner] Metal kernels found: %@", metallibPath);
        setenv("LLAMA_METAL_PATH", metallibPath.UTF8String, 1);
      } else {
        NSLog(@"[LlamaRunner] Warning: default.metallib not found in bundle. Falling back to CPU if needed.");
      }
    }
  } else {
    unsetenv("LLAMA_METAL_PATH");
  }
#endif

  struct llama_model_params mparams = llama_model_default_params();
  mparams.n_gpu_layers = nGpu;
  mparams.main_gpu = 0;
  static ggml_backend_dev_t cpu_devices[2];
  if (nGpu <= 0) {
    ggml_backend_dev_t cpu = ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_CPU);
    cpu_devices[0] = cpu;
    cpu_devices[1] = NULL;
    mparams.devices = cpu_devices;
  }
  // Default to mmap on unless explicitly disabled via environment
#if defined(LLAMA_MODEL_PARAMS_HAS_USE_MMAP)
  {
    bool use_mmap = true;
    const char *env_mmap = getenv("LLAMA_MMAP");
    if (env_mmap != NULL) {
      use_mmap = (atoi(env_mmap) != 0);
    }
    mparams.use_mmap = use_mmap;
  }
#endif

#if defined(LLAMA_MODEL_PARAMS_HAS_MMPROJ)
  if (mmprojPath != nil && [mmprojPath length] > 0) {
    BOOL isDir = NO;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:mmprojPath isDirectory:&isDir];
    if (!exists || isDir) {
      if (_verbose) NSLog(@"[LlamaRunner] projector missing or not a file: %@", mmprojPath);
    } else {
      mparams.mmproj = [mmprojPath UTF8String];
      if (_verbose) NSLog(@"[LlamaRunner] Using external projector: %@", mmprojPath);
    }
  }
#else
  if (mmprojPath != nil && [mmprojPath length] > 0) {
    NSLog(@"[Noema][info] This llama.cpp build does not expose mparams.mmproj; using merged VLMs only.");
  }
#endif

  _model = llama_load_model_from_file([modelPath UTF8String], mparams);
  if (!_model) { noema_llama_backend_release(); return nil; }

  struct llama_context_params cparams = llama_context_default_params();
  int effective_n_ctx = nCtx;
#if defined(NOEMA_HAS_LLAVA) && defined(NOEMA_HAS_CLIP)
  if (nCtx < 8192) {
    NSLog(@"[LlamaRunner] Warning: nCtx of %d may be too small for multimodal use; increasing to 8192.", nCtx);
    effective_n_ctx = 8192;
  }
#endif
  {
    const int train_ctx = llama_n_ctx_train(_model);
    if (train_ctx > 0 && effective_n_ctx > train_ctx) {
      if (_verbose) NSLog(@"[LlamaRunner] Clamping n_ctx from %d to model train ctx %d", effective_n_ctx, train_ctx);
      effective_n_ctx = train_ctx;
    }
  }
  cparams.n_ctx = effective_n_ctx;
  cparams.n_threads = nThreads;
  cparams.n_threads_batch = nThreads;
  cparams.n_seq_max = std::max(1, nSeqMax);
  // Match context batching to our batch allocations to avoid logits array mismatches
  cparams.n_batch = 512;
  cparams.n_ubatch = 512;
  ggml_type resolvedK = GGML_TYPE_F16;
  ggml_type resolvedV = GGML_TYPE_F16;
  bool usedMerged = false;
  ggml_type mergedType = GGML_TYPE_F16;
  noema_apply_flash_and_kv_params(cparams, self.kvConfig, &resolvedK, &resolvedV, &usedMerged, &mergedType);
  if (_verbose && usedMerged) {
    NSLog(@"[Noema] Warning: llama.cpp too old for separate K/V cache types. Using merged cache type=%s.", noema_kv_type_name(mergedType));
  }
  auto warn_if_shady = [](ggml_type t){
    switch (t) {
      case GGML_TYPE_F32:
        fprintf(stderr, "[Noema] Note: KV F32 is for debugging; expect 2x memory vs F16.\n");
        break;
      default: break;
    }
  };
  warn_if_shady(resolvedK);
  warn_if_shady(resolvedV);

  const int n_ctx_per_seq = cparams.n_ctx / (cparams.n_seq_max > 0 ? cparams.n_seq_max : 1);
  const int n_ctx_train = llama_n_ctx_train(_model);
  const int minimum_required_ctx = 2048;
  if (n_ctx_per_seq < minimum_required_ctx) {
    NSLog(@"[LlamaRunner] Error: Per-sequence context length too small (%d). Required at least %d. Train ctx: %d.", n_ctx_per_seq, minimum_required_ctx, n_ctx_train);
      llama_model_free(_model);
    _model = nullptr;
    _loaded = false;
    noema_llama_backend_release();
    return nil;
  }

  _ctx = llama_init_from_model(_model, cparams);
  if (_ctx == nullptr) {
      llama_model_free(_model);
    _model = nullptr;
    _loaded = false;
    noema_llama_backend_release();
    return nil;
  }
  llama_set_n_threads(_ctx, nThreads, nThreads);
  _loaded = true;
  _nThreads = nThreads;

  return self;
}

- (BOOL)hasVisionOps {
#if __has_include(<llama/llava.h>) || __has_include("llava.h") || __has_include(<llama/clip.h>) || __has_include("clip.h")
    return YES;
#else
    return NO;
#endif
}

- (LlamaVisionProbe)probeVision {
#if defined(NOEMA_HAS_LLAVA) && defined(NOEMA_HAS_CLIP)
  if (!_loaded || _model == nullptr || _ctx == nullptr) {
    return LlamaVisionProbeUnavailable;
  }
  @autoreleasepool {
    // Write a minimal 1x1 PNG to a temporary file for probing
    // This avoids bundling an asset and lets clip_image_load_from_file handle decoding.
    static const unsigned char kPng1x1[] = {
      0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
      0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,0x08,0x06,0x00,0x00,0x00,0x1F,0x15,0xC4,
      0x89,0x00,0x00,0x00,0x0A,0x49,0x44,0x41,0x54,0x78,0x9C,0x63,0xF8,0x0F,0x00,0x01,
      0x01,0x01,0x00,0x18,0xDD,0x8E,0x7B,0x00,0x00,0x00,0x00,0x49,0x45,0x4E,0x44,0xAE,
      0x42,0x60,0x82
    };
    NSString *tmpName = [NSTemporaryDirectory() stringByAppendingPathComponent:@"noema_probe.png"];
    NSData *pngData = [NSData dataWithBytes:kPng1x1 length:sizeof(kPng1x1)];
    (void)[pngData writeToFile:tmpName atomically:YES];

    std::vector<std::string> imgs;
    imgs.emplace_back([tmpName UTF8String]);
    int primed = noema_llava_prime_with_images(_model, _ctx, imgs, _nThreads);

    // Clean up probe artifacts: reset KV/context and remove temp file
    noema_llama_kv_cache_clear(_ctx, /*clearData=*/true);
    llama_set_embeddings(_ctx, false);
    [[NSFileManager defaultManager] removeItemAtPath:tmpName error:nil];

    if (primed == -2) { return LlamaVisionProbeNoProjector; }
    if (primed < 0) { return LlamaVisionProbeUnavailable; }
    return LlamaVisionProbeOK;
  }
#else
  return LlamaVisionProbeUnavailable;
#endif
}

- (void)generateWithPrompt:(NSString *)prompt
                  maxTokens:(int)maxTokens
                     onToken:(LlamaTokenHandler)onToken
                      onDone:(LlamaDoneHandler)onDone
                     onError:(LlamaErrorHandler)onError {
  if (!_loaded) {
    if (onError) {
      NSError *err = [NSError errorWithDomain:@"Llama" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Model not loaded"}];
      onError(err);
    }
    return;
  }

  // Reset cancellation flag at the start of each generation
  _cancelRequested.store(false);

    // Clear memory/KV using new memory API
    noema_llama_kv_cache_clear(_ctx, /*clearData=*/true);
    // Ensure we are producing logits (not embeddings) for subsequent decodes/sampling
    llama_set_embeddings(_ctx, false);


  // Build an initial prompt (avoid duplicate BOS by disabling auto-add when control tokens are present)
  const int n_batch_alloc = 512;
  llama_batch batch = llama_batch_init(/*n_tokens_alloc*/ n_batch_alloc, /*embd*/ 0, /*n_seq_max*/ 1);
  std::string p = [prompt UTF8String];
  std::vector<llama_token> toks;
  toks.resize(p.size() * 4 + 16);
  const struct llama_vocab *vocab = llama_model_get_vocab(_model);
  // Decide whether to auto-insert BOS depending on whether the prompt already starts with control tokens
  bool addSpecial = true;
  if (!p.empty()) {
    const char c0 = p[0];
    // Common control-token prefixes in chat templates: '<' (e.g. <bos>, <|...|>) or '[' (e.g. [INST])
    if (c0 == '<' || c0 == '[') {
      addSpecial = false;
    }
  }
  // Parse special tokens (e.g., <|im_start|>, <|eot_id|>) to preserve chat templates; avoid double BOS
  int n = llama_tokenize(vocab, p.c_str(), (int32_t)p.length(), toks.data(), (int)toks.size(), /*add_special*/ addSpecial, /*parse_special*/ true);
  toks.resize(n);

  // Clamp prompt to fit into context window with headroom
  const int ctx_max = llama_n_ctx(_ctx);
  const int prompt_limit = std::max(1, ctx_max - 64);
  if (n > prompt_limit) {
    // Keep only the most recent tail of the prompt
    const int start = n - prompt_limit;
    std::vector<llama_token> tail(toks.begin() + start, toks.end());
    toks.swap(tail);
    n = (int)toks.size();
  }

  // If the prompt is empty, inject a BOS and run a single decode to produce logits
  if (n == 0) {
    batch.n_tokens = 0;
    batch.token[0]     = llama_vocab_bos(vocab);
    batch.pos[0]       = 0;
    batch.n_seq_id[0]  = 1;
    batch.seq_id[0][0] = 0;
    batch.logits[0]    = true;
    batch.n_tokens     = 1;

    if (llama_decode(_ctx, batch) != 0) {
      if (onError) {
        NSError *err = [NSError errorWithDomain:@"Llama" code:2 userInfo:@{NSLocalizedDescriptionKey:@"decode failed (BOS)"}];
        onError(err);
      }
      llama_batch_free(batch);
      return;
    }
    // Keep n at 0; we already produced logits at pos 0. We'll start generation at pos 1.
  }

  // Evaluate the entire prompt in chunks so KV positions remain consecutive
  int n_cur = 0;
  while (n_cur < n) {
    if (_cancelRequested.load()) {
      llama_batch_free(batch);
      if (onDone) onDone();
      return;
    }
    batch.n_tokens = 0;
    const int n_chunk = std::min(n - n_cur, n_batch_alloc);
    // Clear logits flags for the slice we will use, then mark the last token to return logits
    for (int j = 0; j < n_chunk; ++j) batch.logits[j] = 0;
    for (int i = 0; i < n_chunk; ++i) {
      const int pos = n_cur + i;
      batch.token[batch.n_tokens]     = toks[pos];
      batch.pos[batch.n_tokens]       = pos;
      batch.n_seq_id[batch.n_tokens]  = 1;
      batch.seq_id[batch.n_tokens][0] = 0;
      batch.logits[batch.n_tokens]    = (i == n_chunk - 1);
      batch.n_tokens++;
    }
    if (_cancelRequested.load()) {
      llama_batch_free(batch);
      if (onDone) onDone();
      return;
    }
    if (llama_decode(_ctx, batch) != 0) {
      if (onError) {
        NSError *err = [NSError errorWithDomain:@"Llama" code:2 userInfo:@{NSLocalizedDescriptionKey:@"decode failed"}];
        onError(err);
      }
      llama_batch_free(batch);
      return;
    }
    n_cur += n_chunk;
  }

  // Default sampler: temperature + top-k
  auto *smpl = noema_make_default_sampler();
  llama_sampler_reset(smpl);
  
  const int base_pos = (n > 0 ? n : 1);
  int generated = 0;
  const bool unlimited = maxTokens <= 0;
  while (unlimited || generated < maxTokens) {
    if (_cancelRequested.load()) { break; }
    const int idx = -1; // sample from the most recent logits
    llama_token tok = llama_sampler_sample(smpl, _ctx, idx);
    if (tok < 0) {
      // No candidate available from sampler
      break;
    }
    if (tok == llama_vocab_eos(vocab)) break;
    // Inform the sampler about the accepted token to keep internal state consistent
    llama_sampler_accept(smpl, tok);

    // detokenize single token - updated function signature
    char buf[512];
    int nout = llama_token_to_piece(vocab, tok, buf, sizeof(buf), 0, false);
    if (nout > 0 && onToken) {
      NSString *piece = [[NSString alloc] initWithBytes:buf length:nout encoding:NSUTF8StringEncoding];
      onToken(piece ?: @"");
    }

    // feed back token using the new batch API
    batch.n_tokens = 0;
    // Stop if we are at the end of the context
    if (base_pos + generated >= ctx_max - 1) { break; }
    batch.token[batch.n_tokens]     = tok;
    batch.pos[batch.n_tokens]       = base_pos + generated;
    batch.n_seq_id[batch.n_tokens]  = 1;
    batch.seq_id[batch.n_tokens][0] = 0;
    // Ensure logits are requested for this single-token decode
    batch.logits[0] = 0;
    batch.logits[0]    = 1;
    batch.n_tokens++;
    if (_cancelRequested.load()) { break; }
    if (llama_decode(_ctx, batch) != 0) {
      break;
    }
    generated++;
  }

  llama_sampler_free(smpl);
  llama_batch_free(batch);
  if (onDone) onDone();
}

- (void)generateWithPrompt:(NSString *)prompt
                imagePaths:(NSArray<NSString *> * _Nullable)imagePaths
                 maxTokens:(int)maxTokens
                   onToken:(LlamaTokenHandler)onToken
                    onDone:(LlamaDoneHandler)onDone
                   onError:(LlamaErrorHandler)onError {
    if (!_loaded) {
        if (onError) {
            NSError *err = [NSError errorWithDomain:@"Llama" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Model not loaded"}];
            onError(err);
        }
        return;
    }

    // Reset cancellation flag at the start of each generation
    _cancelRequested.store(false);

    // If no images, fall back to text-only path
    if (imagePaths == nil || imagePaths.count == 0) {
        [self generateWithPrompt:prompt maxTokens:maxTokens onToken:onToken onDone:onDone onError:onError];
        return;
    }

#if defined(NOEMA_HAS_LLAVA) && defined(NOEMA_HAS_CLIP)
    // Clear memory/KV before priming with images
    noema_llama_kv_cache_clear(_ctx, /*clearData=*/true);

    std::vector<std::string> imgs;
    imgs.reserve(imagePaths.count);
    for (NSString *s in imagePaths) { imgs.emplace_back([s UTF8String]); }
    int n_pfx = noema_llava_prime_with_images(_model, _ctx, imgs, _nThreads);
    if (_verbose) {
        NSLog(@"[LlamaRunner] Vision priming complete. prefix_tokens=%d, n_ctx=%d", n_pfx, llama_n_ctx(_ctx));
    }
    // Ensure we are producing logits (disable embedding-only mode) after vision priming
    llama_set_embeddings(_ctx, false);
    if (n_pfx == -2) {
        if (onError) {
            NSError *err = [NSError errorWithDomain:@"Llama" code:1003 userInfo:@{NSLocalizedDescriptionKey:@"Loaded model does not support images (missing mmproj weights)"}];
            onError(err);
        }
        return;
    } else if (n_pfx < 0) {
        if (onError) {
            NSError *err = [NSError errorWithDomain:@"Llama" code:1002 userInfo:@{NSLocalizedDescriptionKey:@"Failed to process image(s) for vision model"}];
            onError(err);
        }
        return;
    }

    // After priming, evaluate the text prompt as a continuation. We reuse the text path but offset positions.
    // Build tokens once
    const int n_batch_alloc = 512;
    llama_batch batch = llama_batch_init(/*n_tokens_alloc*/ n_batch_alloc, /*embd*/ 0, /*n_seq_max*/ 1);
    std::string p = [prompt UTF8String];
    std::vector<llama_token> toks;
    toks.resize(p.size() * 4 + 16);
    const struct llama_vocab *vocab = llama_model_get_vocab(_model);
    bool addSpecial = true;
    if (!p.empty()) {
        const char c0 = p[0];
        if (c0 == '<' || c0 == '[') { addSpecial = false; }
    }
    int n = llama_tokenize(vocab, p.c_str(), (int32_t)p.length(), toks.data(), (int)toks.size(), /*add_special*/ addSpecial, /*parse_special*/ true);
    toks.resize(n);

    const int ctx_max = llama_n_ctx(_ctx);
    const int prompt_limit = std::max(1, ctx_max - 64);
    if (n > prompt_limit) {
        const int start = n - prompt_limit;
        std::vector<llama_token> tail(toks.begin() + start, toks.end());
        toks.swap(tail);
        n = (int)toks.size();
    }

    // If the text prompt is empty, inject a BOS at the end of the image prefix and decode once
    if (n == 0) {
        batch.n_tokens = 0;
        batch.token[0]     = llama_vocab_bos(vocab);
        batch.pos[0]       = n_pfx + 0;
        batch.n_seq_id[0]  = 1;
        batch.seq_id[0][0] = 0;
        batch.logits[0]    = true;
        batch.n_tokens     = 1;
        if (llama_decode(_ctx, batch) != 0) {
            llama_batch_free(batch);
            if (onError) {
                NSError *err = [NSError errorWithDomain:@"Llama" code:2 userInfo:@{NSLocalizedDescriptionKey:@"decode failed (BOS)"}];
                onError(err);
            }
            return;
        }
    }

    // Evaluate text tokens starting after the image prefix
    int n_cur = 0;
    while (n_cur < n) {
        if (_cancelRequested.load()) {
            llama_batch_free(batch);
            if (onDone) onDone();
            return;
        }
        batch.n_tokens = 0;
        const int n_chunk = std::min(n - n_cur, n_batch_alloc);
        // Clear logits flags for the slice we will use, then mark the last token to return logits
        for (int j = 0; j < n_chunk; ++j) batch.logits[j] = 0;
        for (int i = 0; i < n_chunk; ++i) {
            const int pos = n_pfx + n_cur + i;
            batch.token[batch.n_tokens]     = toks[n_cur + i];
            batch.pos[batch.n_tokens]       = pos;
            batch.n_seq_id[batch.n_tokens]  = 1;
            batch.seq_id[batch.n_tokens][0] = 0;
            batch.logits[batch.n_tokens]    = (i == n_chunk - 1);
            batch.n_tokens++;
        }
        if (_cancelRequested.load()) {
            llama_batch_free(batch);
            if (onDone) onDone();
            return;
        }
        if (llama_decode(_ctx, batch) != 0) {
            llama_batch_free(batch);
            if (onError) {
                NSError *err = [NSError errorWithDomain:@"Llama" code:2 userInfo:@{NSLocalizedDescriptionKey:@"decode failed"}];
                onError(err);
            }
            return;
        }
        n_cur += n_chunk;
    }

    // Default sampler: temperature + top-k
    auto *smpl = noema_make_default_sampler();
    llama_sampler_reset(smpl);

    const int base_pos = n_pfx + (n > 0 ? n : 1);
    int generated = 0;
    const bool unlimited = maxTokens <= 0;
    while (unlimited || generated < maxTokens) {
        if (_cancelRequested.load()) { break; }
        const int idx = -1; // sample from the most recent logits
        llama_token tok = llama_sampler_sample(smpl, _ctx, idx);
        if (tok < 0) {
            // No candidate available from sampler
            break;
        }
        if (tok == llama_vocab_eos(vocab)) break;
        llama_sampler_accept(smpl, tok);
        char buf[512];
        int nout = llama_token_to_piece(vocab, tok, buf, sizeof(buf), 0, false);
        if (nout > 0 && onToken) {
            NSString *piece = [[NSString alloc] initWithBytes:buf length:nout encoding:NSUTF8StringEncoding];
            onToken(piece ?: @"");
        }
        batch.n_tokens = 0;
        if (base_pos + generated >= ctx_max - 1) { break; }
        batch.token[batch.n_tokens]     = tok;
        batch.pos[batch.n_tokens]       = base_pos + generated;
        batch.n_seq_id[batch.n_tokens]  = 1;
        batch.seq_id[batch.n_tokens][0] = 0;
        // Ensure logits are requested for this single-token decode
        batch.logits[0] = 0;
        batch.logits[0]    = 1;
        batch.n_tokens++;
        if (_cancelRequested.load()) { break; }
        if (llama_decode(_ctx, batch) != 0) { break; }
        generated++;
    }

    llama_sampler_free(smpl);
    llama_batch_free(batch);
    if (onDone) onDone();
#else
    if (onError) {
        NSError *err = [NSError errorWithDomain:@"Llama" code:1001 userInfo:@{NSLocalizedDescriptionKey:@"This llama.cpp runner was built without vision support"}];
        onError(err);
    }
#endif
}

- (void)unload {
  if (_ctx) { llama_free(_ctx); _ctx = nullptr; }
    if (_model) { llama_model_free(_model); _model = nullptr; }
  _loaded = false;
  noema_llama_backend_release();
}

@end
