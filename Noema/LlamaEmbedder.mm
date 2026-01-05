// LlamaEmbedder.mm
#import "LlamaEmbedder.h"
#import "LlamaBackendManager.h"
#import "Noema-Bridging.h"
#include <vector>
#include <string>
#include <cmath>
#include <cstdlib>
#include <cstdint>

// Backwards-compatible define for pooling types in case headers are older
#ifndef LLAMA_POOLING_NONE
#define LLAMA_POOLING_NONE 0
#endif
#ifndef LLAMA_POOLING_MEAN
#define LLAMA_POOLING_MEAN 1
#endif

// The declarations are now provided by the bridging header,
// so this block is no longer needed.

static inline void noema_llama_kv_cache_clear(struct llama_context *ctx) {
#if defined(__APPLE__)
  using llama_get_memory_fn = llama_memory_t (*)(struct llama_context *);
  using llama_memory_clear_fn = void (*)(llama_memory_t, bool);
  using llama_memory_seq_rm_fn = bool (*)(llama_memory_t, llama_seq_id, llama_pos, llama_pos);

  llama_get_memory_fn p_get_memory = (llama_get_memory_fn)llama_get_memory;
  llama_memory_clear_fn p_memory_clear = (llama_memory_clear_fn)llama_memory_clear;
  llama_memory_seq_rm_fn p_memory_seq_rm = (llama_memory_seq_rm_fn)llama_memory_seq_rm;

  if (p_memory_seq_rm && p_get_memory) {
    (void)p_memory_seq_rm(p_get_memory(ctx), 0, -1, -1);
  } else if (p_memory_clear && p_get_memory) {
    p_memory_clear(p_get_memory(ctx), /*data*/false);
  }
#else
  // Assume modern llama.cpp providing llama_memory_seq_rm
  (void)llama_memory_seq_rm(llama_get_memory(ctx), 0, -1, -1);
#endif
}

@implementation LlamaEmbedder {
  llama_model *_model;
  llama_context *_ctx;
  int _dim;
}

- (instancetype)initWithModelPath:(NSString *)modelPath
                          threads:(int)threads
                       nGpuLayers:(int)nGpuLayers {
  self = [super init];
  if (!self) return nil;
    noema_llama_backend_addref();
    struct llama_model_params mp = llama_model_default_params();
    ggml_backend_dev_t cpu = ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_CPU);
    static ggml_backend_dev_t cpu_devices[2];
    mp.n_gpu_layers = nGpuLayers;
    if (nGpuLayers <= 0) {
      cpu_devices[0] = cpu;
      cpu_devices[1] = NULL;
      mp.devices = cpu_devices;
    }
    _model = llama_load_model_from_file(modelPath.UTF8String, mp);
    if (!_model) { noema_llama_backend_release(); return self; }
    struct llama_context_params cp = llama_context_default_params();
    cp.embeddings = true;
    // manage batches and outputs manually.
    cp.n_threads = threads > 0 ? threads : 2;
    cp.n_threads_batch = cp.n_threads;
    // Use a larger context appropriate for nomic-embed-text-v1.5 (n_ctx_train = 2048)
    cp.n_ctx = 2048;
    // Configure batching for single-sequence processing. We embed one text at a time
    // but allow up to `n_ctx` tokens per batch.
    cp.n_batch = 2048;
    cp.n_ubatch = cp.n_batch;
    cp.n_seq_max = 1;
    // Respect model's mean pooling requirement (nomic-bert.pooling_type = 1)
    cp.pooling_type = (enum llama_pooling_type)LLAMA_POOLING_MEAN;
    // Explicitly disable Flash Attention for non-causal BERT-style models.
    cp.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_DISABLED;
    cp.offload_kqv = false;
  // Initialize context using modern API
  _ctx = llama_init_from_model(_model, cp);
  if (!_ctx) { llama_model_free(_model); _model = NULL; noema_llama_backend_release(); return self; }
  llama_set_n_threads(_ctx, cp.n_threads, cp.n_threads);
  _dim = _model ? llama_n_embd(_model) : 0;
  return self;
}

- (BOOL)isReady { return _model && _ctx && _dim > 0; }
- (int)dimension { return _dim; }

- (int)countTokens:(NSString *)text {
  if (!_model) return 0;
  std::string s(text.UTF8String);
  std::vector<llama_token> toks;
  toks.resize(s.size() + 8);
  const struct llama_vocab *vocab = llama_model_get_vocab(_model);
  int n = llama_tokenize(vocab, s.c_str(), (int32_t)s.length(), toks.data(), (int)toks.size(), /*add_special*/ true, /*parse_special*/ false);
  return n < 0 ? 0 : n;
}

- (BOOL)embedText:(NSString *)text intoBuffer:(float *)buffer length:(int)length {
  if (!_model || !_ctx || !buffer || length < _dim) return NO;
  
  // Clear the KV cache before processing a new sequence to ensure a clean state.
  noema_llama_kv_cache_clear(_ctx);
  
  std::string s(text.UTF8String);
  std::vector<llama_token> toks;
  toks.resize(s.size() + 8);
  const struct llama_vocab *vocab = llama_model_get_vocab(_model);
  int n = llama_tokenize(vocab, s.c_str(), (int32_t)s.length(), toks.data(), (int)toks.size(), /*add_special*/ true, /*parse_special*/ false);
  if (n <= 0) return NO;
  toks.resize(n);
  // Clamp tokens to context - 8 for safety
  const int ctx_max = llama_n_ctx(_ctx);
  const int limit = std::max(1, ctx_max - 8);
  if (n > limit) {
    const int start = n - limit;
    std::vector<llama_token> tail(toks.begin() + start, toks.end());
    toks.swap(tail);
    n = (int)toks.size();
  }
  // Do not truncate here; token-aware chunking in Swift ensures inputs fit.
  // Initialize batch for token IDs (embd=0): we pass token IDs, not precomputed embeddings
  llama_batch batch = llama_batch_init(n, 0, 1);
  if (!batch.token) { llama_batch_free(batch); return NO; }
  if (!batch.logits) {
    // Older llama.cpp builds may not allocate the logits buffer; allocate
    // one so we can mark tokens as graph outputs and avoid ggml asserts.
    batch.logits = (int8_t *)calloc(n, sizeof(int8_t));
    if (!batch.logits) { llama_batch_free(batch); return NO; }
  }
  batch.n_tokens = n;
  for (int i = 0; i < n; ++i) {
    batch.token[i] = toks[i];
    batch.pos[i] = i;
    batch.seq_id[i][0] = 0;
    batch.n_seq_id[i] = 1;
    // Mark all tokens as outputs so mean pooling can aggregate across the
    // entire sequence when pooling_type is LLAMA_POOLING_MEAN.
    batch.logits[i] = 1;
  }
  // Forcibly use llama_encode as we are linking against a modern llama.cpp library
  int rc = llama_encode(_ctx, batch);
  llama_batch_free(batch);
  if (rc != 0) return NO;

  // For mean pooling, get the embedding for the entire sequence (ID 0)
  const float *emb = llama_get_embeddings_seq(_ctx, 0);
  if (!emb) return NO;
  
  // Validate embeddings before copying
  for (int i = 0; i < _dim; i++) {
    if (!std::isfinite(emb[i])) {
      return NO;  // Reject NaN or Inf values
    }
  }
  
  memcpy(buffer, emb, sizeof(float) * _dim);
  return YES;
}

- (void)unload {
  if (_ctx) { llama_free(_ctx); _ctx = NULL; }
  if (_model) { llama_model_free(_model); _model = NULL; }
  noema_llama_backend_release();
}

@end

