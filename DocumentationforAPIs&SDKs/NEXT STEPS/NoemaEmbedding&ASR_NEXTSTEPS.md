# Integrating multilingual embeddings and on-device transcription in Noema

## Product goals implied by the feedback

The feedback points toward a coherent expansion of Noema’s “local knowledge” proposition, with two pillars that ought to feel native across iOS, macOS, and visionOS: a modern multilingual embedding stack with a curated model chooser, and first-class audio and video understanding through transcription and media ingestion.

A careful reading also clarifies that this is not simply a matter of swapping one embedding checkpoint for another. The request is for a system that (a) works across multiple embedding architectures and pooling conventions, (b) makes those differences legible in UI without forcing users into technical decisions, and (c) preserves the existing “Explore” experience pattern, especially the device-fit recommendation badge that currently guides LLM downloads. fileciteturn45file0L1-L450

In parallel, ASR and transcription are framed as a differentiator: users should be able to summarize and interrogate audio and video, not merely accept text documents. That implies a pipeline that can ingest media, transcribe reliably, preserve timestamps and provenance, and then integrate transcripts into the same retrieval and chat workflows as documents. citeturn2search2turn3search1turn2search1

## Current state in the repository and what it implies for integration

Noema presently hardcodes a single embedding model and wires it into dataset indexing and retrieval via a llama.cpp-based backend.

The embedding model path is fixed to a specific repository directory and filename under Documents, with `nomic-embed-text-v1.5.Q4_K_M.gguf` as the only supported artifact, and the embedding actor loads that file into a `LlamaEmbeddingBackend`. fileciteturn40file0L1-L200

The embedding “task” concept exists, but its configurability is minimal: `EmbeddingTask.searchQuery` and `.searchDocument` prepend `search_query:` and `search_document:` respectively, and pooling is effectively a placeholder enum with only `.none`. fileciteturn41file0L1-L80

Despite the pooling enum being inert, the implementation currently depends on mean pooling at the llama.cpp layer. The Objective-C++ embedder sets `cp.embeddings = true`, fixes `cp.n_ctx = 2048`, and explicitly requests mean pooling by setting `cp.pooling_type = LLAMA_POOLING_MEAN`. It then marks all tokens as outputs so that sequence pooling can aggregate across the full sequence and retrieves the pooled vector via `llama_get_embeddings_seq`. fileciteturn43file0L1-L220

On the UI side, “Embedding Model” appears in Settings as a single status row labelled “Nomic Embed Text v1.5 (Q4_K_M)”, with a download flow that mirrors onboarding, plus a delete affordance. There is no chooser, no search, and no structured way to represent “recommended” embedding sizes the way LLMs are presented in Explore. fileciteturn45file0L1-L450

Dataset indexing and retrieval are already designed around a token-aware chunking and embedding pass. During chunk preparation, Noema counts tokens using the embedding model tokenizer, uses `maxTokensPerChunk = 1200`, and only later batch-embeds chunks, persisting vectors to disk for future retrieval. fileciteturn46file0L1-L650

One structural gap becomes important the moment multiple embedding models are introduced: dataset index metadata, as persisted today, does not carry an embedding “fingerprint” (model ID, dimension, pooling strategy, normalization, or prompt template). The code already refuses to use a stale index when a dataset is marked `requiresReindex`, but there is no systematic mechanism that sets `requiresReindex` based on embedding configuration drift. fileciteturn46file0L1-L220

These observations imply that the embedding work must be treated as a refactor plus an expansion: the current code path is coherent for a single GGUF encoder embedding model, but it is not yet a general embedding platform.

## Embeddings integration plan that remains robust across models

A stable implementation needs a separation between (a) model selection and metadata, (b) embedding execution, and (c) downstream consumers such as dataset indexing. The goal is that changing models becomes a controlled state transition rather than a global rewrite.

**Embedding model identity and metadata**

Introduce an internal “embedding model record” layer, analogous in spirit to how LLMs are handled in Explore, but tailored to embeddings. Each record should contain:

- A stable `id` (for example, a Hugging Face repo ID) and a `displayName`.
- Output properties: `dimension` (or a range when models support adjustable embedding dimensions), and expected similarity semantics (cosine or dot product, with cosine preferred when vectors are normalized).
- Input constraints: maximum recommended sequence length and any required prompt prefixes or instruction templates.
- Default pooling strategy and whether the model expects mean pooling or CLS-based pooling.
- Licensing flags that can be surfaced in UI (for example, “non-commercial”).
- A list of installable artifacts per runtime format. For Noema’s current stack, GGUF is the baseline, but the design should also admit Core ML embedding models if added later.

This metadata layer is not a luxury. It is the only clean way to support models like E5 that require specific prefixes and explicit mean pooling, alongside models like BGE-M3 whose dense representation is defined as the normalized hidden state of the `[CLS]` token. citeturn0search0turn0search2

**Pooling and normalization as first-class configuration**

Pooling is presently implicit, but it must become explicit because it differs across families:

- In the multilingual E5 family, the canonical approach is attention-mask-aware average pooling of last hidden states, followed by L2 normalization, and the model card is explicit about both the pooling formula and the required `query:` and `passage:` prefixes. citeturn0search0turn0search3
- In BGE-M3’s dense mode, the dense embedding is defined as the normalized hidden state at the special `[CLS]` token position, which is a different pooling definition with different failure modes if implemented incorrectly. citeturn0search1turn0search2
- In the current Noema embedder, mean pooling is requested at the llama.cpp level (`LLAMA_POOLING_MEAN`), and the code assumes that pooled sequence embeddings are directly returned. That assumption is reasonable for the current model, yet it is not general without reading model metadata and selecting a pooling method per model. fileciteturn43file0L1-L220

The plan should therefore expand `EmbeddingPooling` beyond `.none` to at least: `meanMasked`, `cls`, and `lastToken`, plus a “modelDefault” option. `modelDefault` should be the only option exposed in non-advanced UI.

At the execution layer, there are two acceptable implementations:

- **Engine-level pooling when supported**, by setting llama.cpp pooling type (mean or CLS) and retrieving `llama_get_embeddings_seq`. This matches today’s approach and keeps the Swift layer simpler. fileciteturn43file0L1-L220
- **Client-level pooling for maximum portability**, by retrieving token-level embeddings (when the backend exposes them) and applying masked pooling in Swift, reproducing the E5 reference implementation including attention mask handling. The E5 model card shows the precise masked-fill and normalization logic expected for strong results. citeturn0search0

Given the request for robustness across many embedding models, the recommended approach is hybrid: implement engine-level pooling for speed, but retain a client-level reference path for correctness testing and for backends that cannot provide a reliable pooled form.

Normalization should remain on by default, as Noema presently normalizes vectors after embedding. This aligns with E5’s guidance and keeps cosine similarity meaningful in retrieval. fileciteturn42file0L1-L230turn0search0

**Prompt and task templating per embedding model**

Replace the fixed `EmbeddingTask.prefix` strings with a model-scoped template system:

- Each embedding model record defines how to format inputs for `query` and `document` embeddings.
- The caller requests an abstract task such as `.retrievalQuery` or `.retrievalDocument`, and the template layer produces a string for the backend.

This is necessary because the best-performing embedding families differ sharply:

- Multilingual E5 expects the literal prefixes `query:` and `passage:` even for non-English text. citeturn0search0turn0search3
- EmbeddingGemma describes a prompt scheme that prepends a task descriptor and uses distinct “query” and “document” prompt forms, including a document template that includes `title:` metadata. citeturn4search4
- Qwen3-Embedding emphasizes “instruction-aware” embeddings and recommends task-specific instructions, written in English for multilingual contexts. citeturn4search0turn4search1

Noema already has a place to inject such logic: `EmbeddingTask` exists. The plan is to refactor it into a more expressive task model and move formatting responsibility into per-model metadata rather than a fixed switch statement. fileciteturn41file0L1-L80

**Dataset index fingerprinting and reindex workflow**

Once the embedding model becomes user-selectable, every dataset index must carry a persistent fingerprint. At minimum:

- embedding model ID and version (or repo ID plus file checksum),
- embedding dimension,
- pooling strategy,
- normalization policy,
- chunking policy inputs that affect vectors (token cap, overlap, and prompt template).

When Noema loads an existing index, it should compare this fingerprint to the current embedding configuration. If mismatched, the dataset should be marked `requiresReindex`, and retrieval should fail gracefully with a UI prompt to rebuild. Noema already has a code path that refuses stale indexes when `requiresReindex` is true. The missing piece is deterministic computation and persistence of the fingerprint so that `requiresReindex` can be set automatically. fileciteturn46file0L1-L200

**Download and install pipeline unification**

Embedding model download currently exists in two places: `EmbedModelInstaller` has a hardcoded remote URL, and `DownloadController.startEmbedding` also has an embedding download path but still resolves to the same fixed nomic file. fileciteturn44file0L1-L120turn34file0L1-L220

The plan is to remove the hardcoded embedding URL entirely and route all embedding downloads through the same download engine used for models and datasets, with the embedding model record supplying the exact artifact URL, expected size, and checksum when available. This change ensures that the “curated list” can actually install multiple models and track them consistently.

## Curated multilingual embedding model lineup and model-specific operational details

The curated list should balance two constraints: what the community is recommending now, and what can realistically run on Apple devices with clear “fit” guidance.

Reddit discussions in r/LocalLLaMA over the past year provide two useful signals: Qwen3 embedding models are repeatedly cited as top performers on multilingual leaderboards, and Nomic v1.5 is explicitly called out for poor Thai performance by at least one benchmarker. citeturn0reddit48turn0reddit52turn0reddit51

The curated list should not merely list names. It should specify, for each model, the key operational facts that determine whether it behaves correctly in Noema: pooling, prefixing, context length, dimension, and license.

**Recommended default multilingual baseline**

Qwen3-Embedding-0.6B is a strong candidate for a new default on multilingual grounds. Its model card specifies support for 100+ languages, 32k context length, and an embedding dimension up to 1024, with a user-defined output dimension range from 32 to 1024 via MRL support. It is Apache-2.0 licensed, which simplifies commercial distribution. citeturn4search0

The architectural implication is that Noema should treat “dimension” as potentially configurable for some models, because Qwen3 explicitly supports smaller output dimensions without retraining, which can materially reduce on-device vector storage and speed up similarity computations. citeturn4search0

**Larger, higher-quality multilingual option**

Qwen3-Embedding-4B scales to an embedding dimension up to 2560, still with adjustable output dimensions, and keeps the same 32k context length and Apache-2.0 license. This should be presented as a “high quality” option suitable primarily for Macs and high-end iPads due to compute and memory demands. citeturn4search1

**Encoder-style multilingual model with explicit mean pooling requirements**

Multilingual E5 models remain widely used in retrieval, and their model card provides an explicit, reproducible mean pooling implementation that uses the attention mask to exclude padding, followed by L2 normalization. It also emphasizes that each input should carry `query:` or `passage:` prefixes, even for non-English texts, or performance degrades. citeturn0search0turn0search3

This makes multilingual E5 an ideal “reference model” for Noema’s pooling correctness tests: if Noema can reproduce E5’s published pooling behavior and similarity behavior, it is far more likely to behave correctly across other encoder models.

**Hybrid retrieval specialist with CLS pooling semantics**

BGE-M3 is repeatedly recommended in community answers for multilingual hybrid retrieval, partly because it supports multiple retrieval styles. Its documentation describes multi-functionality and multi-linguality, and it formally defines the dense embedding as the normalized hidden state at the `[CLS]` position. It also advertises long-input handling up to 8192 tokens. citeturn0search1turn0search2turn0reddit49

For Noema, the actionable point is pooling. BGE-M3’s dense mode, if implemented with mean pooling, will not match the intended representation, and retrieval quality will likely drift. Hence the curated model list needs to encode “pooling = CLS” as an operational requirement, and the backend must support it. citeturn0search2

**Small, fast option with licensing considerations**

EmbeddingGemma-300m appears in community recommendations as a fast local model, and the model card indicates 768-dimensional embeddings. However, the Hugging Face page also indicates access is gated behind Google’s usage license, which should be surfaced explicitly in Noema’s UI as a licensing restriction. citeturn0reddit52turn4search4

EmbeddingGemma also introduces an unusually explicit prompt templating scheme for query and document embedding, including a default task description and document templates that carry a title field. This is a direct argument for the model-scoped templating layer described earlier. citeturn4search4

**Popular but non-commercial model that must be labelled accordingly**

Jina Embeddings v3 is frequently mentioned in multilingual embedding discussions, and the r/LocalLLaMA thread explicitly raises the commercial licensing constraint. Hugging Face documentation and the model card specify that the model supports long sequences up to 8192 tokens and uses task-specific adapters, but the license is CC BY-NC 4.0, which is non-commercial by default. citeturn0reddit51turn4search3turn4search2

Noema can still include it in the curated list if the product philosophy is to be transparent and helpful, but it must be guarded by a conspicuous “Non-commercial” badge and an explanatory detail view, to prevent accidental adoption by users who need permissive licenses.

**Replacing the current default**

At present, Noema is anchored to `nomic-embed-text-v1.5` as the sole embedding model. Community benchmarking in the Thai setting describes it as effectively lacking Thai support for real tasks, despite being able to detect that the text is Thai. That is aligned with the feedback request to move to a newer multilingual option. citeturn0reddit48turn40file0L1-L80

## UI and UX plan for the embedding model section

The UI must do two things at once: keep “simple mode” approachable, while allowing knowledgeable users to reason about the impact of embeddings, prompts, and reindexing.

**Where embeddings live in the product**

Settings currently exposes a single embedding model row with download and delete actions. This should become a summary row that always shows:

- the active embedding model name, size tier badge, and installation state,
- a “Change” affordance that navigates to a dedicated “Embedding Models” page,
- a short indication of what changing embeddings affects: “Dataset search quality and indexing.”

This refactor builds directly on existing structure: Settings already has an “Embedding Model” card, download UI, and a boolean `embedAvailable` derived from the model file’s presence on disk. fileciteturn45file0L1-L450

**Embedding Models page design**

The Embedding Models page should parallel the LLM Explore experience rather than invent a new metaphor:

- A curated “Recommended” section at the top, ordered by suitability on the current device.
- A search surface (optional in simple mode, default in advanced mode) that can query known embedding registries.
- Each model displayed in a card that includes the same “fits” badge treatment that LLM Explore uses, but computed with embedding-specific heuristics. The badge should remain a single, legible signal, because the LLM Explore pattern already establishes user expectations. fileciteturn27file0L1-L220turn29file0L1-L220

To support “model size recommendation badges” across iOS, macOS, and visionOS, embed models need a consistent device-fit heuristic. The existing `ModelRAMAdvisor` can be reused conceptually, but embeddings should likely have a separate estimator because embedding inference does not allocate the same KV-cache working set as autoregressive generation. The UI should still present a familiar output: “Fits on your device” or a warning state. fileciteturn29file0L1-L220

**Model detail view contents**

A model detail view should be short enough for scanning yet complete enough to prevent mistakes. The essential items are:

- Languages and context window.
- Embedding dimension and whether it is adjustable.
- Pooling default and whether it can be overridden.
- The exact query and document templates, shown as a copyable snippet in advanced mode (for example, E5’s `query:` and `passage:` rules, EmbeddingGemma’s `task:` and `title:` rules).
- License summary with a plain-language badge.

These details can be drawn from authoritative model cards where available, which is particularly important for prefixing and pooling rules, because those are the most common sources of silently degraded retrieval quality. citeturn0search0turn0search2turn4search4

**Changing the active embedding model and reindexing**

Switching embedding models must surface one unavoidable consequence: existing dataset vectors become incompatible. This should be handled with a structured transition dialog:

- “Switch model” confirms the new active model.
- The dialog explains that existing indexes will be marked stale and may need rebuilding.
- The user can choose “Reindex all now” or “Later.” If “Later,” dataset cards in Stored should show a small “Needs reindex” badge.

Noema already has a retrieval failure path when a dataset is stale, and it already communicates indexing stages and progress. The new work is to ensure that staleness originates from fingerprint mismatch rather than a manual toggle. fileciteturn46file0L1-L220

**Where advanced embedding settings belong**

Pooling choices, template overrides, chunk-size controls, and normalization should not be on the main Settings surface in simple mode. The clean pattern is:

- Simple mode: model chooser only, with an automatic “model default” configuration.
- Advanced mode: an “Embedding Advanced” subpanel inside the model detail screen, where overrides are tightly scoped to the selected model and validated.

This respects the fact that model cards themselves often treat these choices as correctness constraints rather than aesthetic preferences. E5’s prefix and pooling guidance is a correctness constraint; presenting it as an optional toggle in simple UI would be a recipe for support tickets. citeturn0search0

## ASR, transcription, and audio-video interaction plan

A serious ASR integration in Noema requires both an engine strategy and a product strategy. The engine strategy concerns dependencies and runtimes; the product strategy concerns how transcription becomes a seamless part of chat, memory, and datasets.

**Engine options that fit Apple platforms**

The Speech framework provides a native baseline via `SFSpeechRecognizer`, including the ability to determine whether on-device recognition is supported and to request on-device-only operation via `requiresOnDeviceRecognition`. Apple’s documentation is explicit that some locales may require an Internet connection, so Noema should treat “offline-only” as a guarded option that checks device capabilities and language support. citeturn2search1turn2search9turn2search5

For open-weight, on-device transcription, there are two leading candidates:

- WhisperKit, an MIT-licensed framework designed for on-device speech-to-text on Apple Silicon, offering streaming transcription, timestamps, and voice activity detection. Its repository describes Swift Package Manager integration and a local server mode that implements OpenAI-style audio endpoints. citeturn2search2turn2search10
- whisper.cpp, an MIT-licensed C/C++ port of Whisper that emphasizes minimal dependencies and Apple Silicon optimization, with Metal and Core ML mentioned as optimizations, plus quantization support. The project also has Swift Package Manager integration guidance through a dedicated package repository and notes about maintenance direction. citeturn3search1turn3search2

Noema should not pick only one of these. The sound architecture is a pluggable “TranscriptionBackend” with at least:

- `AppleSpeechBackend` (fastest to ship, provides a baseline, offers on-device mode when available),
- `WhisperKitBackend` (best user experience on Apple hardware if it meets iOS and visionOS deployment requirements in practice),
- `WhisperCppBackend` (portable fallback, particularly attractive if WhisperKit platform constraints emerge).

The implementation pattern can mirror Noema’s existing approach for model backends: a protocol plus multiple concrete implementations, with selection stored in settings and surfaced in UI in a curated list.

**Support for audio-language models such as Qwen2-Audio**

The feedback mentions “Qwen ASR” and multimodal audio input. Qwen2-Audio is explicitly positioned as an audio-language model that can accept audio input directly, supporting both “voice chat” and “audio analysis,” and is released with an Apache-2.0 license. Its transformers documentation describes processor components and audio tokens. citeturn1search0turn1search1turn1search6

However, Qwen2-Audio-7B is not a realistic on-device target for iPhones under sensible performance constraints. Noema should therefore treat audio-language models as a “remote or desktop-class” option:

- On macOS and high-end hardware, Qwen2-Audio could be supported through a remote backend or a local server integration when users are willing to configure it.
- On iOS and visionOS, the default path should remain “ASR to text” followed by LLM summarization and Q&A, because that keeps the system responsive and aligns with on-device constraints.

This division should be presented plainly in UI as “On-device transcription” versus “Audio-language model (requires powerful hardware or a server).” citeturn1search0turn2search1

**Media ingestion model and storage**

A robust design treats transcription as a pipeline that produces durable artifacts:

- Original media file (or a reference to it) stored in a controlled Noema attachments directory.
- Transcript text as a first-class document with provenance fields: language, engine, model, timestamped segments, and confidence where available.
- Optional derived artifacts: a compact “clean transcript” for retrieval embeddings, plus a “verbatim transcript” with timestamps for UI navigation.

This matches Noema’s existing dataset ingestion approach, where extracted text is written to disk, compacted, and only then embedded. The same pattern should be reused for media: “extract transcript,” “compact transcript,” “embed transcript,” and “index.” fileciteturn46file0L1-L450

**Chat UX for audio and video**

Noema already has an attachment affordance architecture for images, and the Settings model already includes a cleanup policy for chat attachments. This should be extended to audio and video rather than implemented as a separate subsystem. fileciteturn45file0L1-L120

The expected chat flow should be:

- User attaches an audio or video file, or records audio.
- Noema displays a media chip (duration, size, name) and a “Transcribe” action, with an option to auto-transcribe based on settings.
- While transcription runs, show streaming partial text when the backend supports it, because this is the single best way to give reassurance that work is progressing. Apple’s own guidance for speech recognition UX emphasizes visible indicators and progressive text updates. citeturn2search1turn2search5
- When transcription completes, Noema posts the transcript into the chat context as a cited source, and offers two next actions: “Summarize” and “Ask a question.”

For video, the minimum viable path is to extract audio and transcribe. A second iteration can add frame sampling if a vision-capable LLM is loaded, enabling summaries that integrate both spoken content and key visual moments.

**Dataset and memory integration**

Once a transcript exists, it should be eligible for two uses:

- One-off chat grounding: include transcript chunks in the prompt similarly to dataset chunks.
- Durable memory: users can save transcripts into Stored as datasets, or as a lightweight “Media Library” parallel to datasets.

Because Noema’s retrieval system already tokenizes, chunks, embeds, and ranks chunks via cosine similarity, transcripts become a natural extension, provided the embedding model and chunk policy are correctly recorded in metadata. fileciteturn46file0L1-L650turn42file0L1-L230

## Delivery plan, sequencing, and risk management

A pragmatic delivery sequence should reduce user-facing risk by stabilizing embedding selection and index compatibility first, then layering transcription.

**First delivery slice: embeddings as a platform**

Ship a refactor that introduces multiple installed embedding models, an active model selection, and dataset index fingerprinting, while keeping the default behavior close to today’s experience.

Key acceptance criteria:

- Multiple installable embedding models, with the active model stored in settings.
- A curated list surfaced in UI, with device-fit badges.
- Dataset indexes are marked stale when the active embedding configuration changes, and users are guided to reindex.

This work directly replaces hardcoded paths and hardcoded download URLs in the current embedding implementation. fileciteturn40file0L1-L80turn44file0L1-L120

**Second delivery slice: pooling and prompt correctness hardening**

Implement model-scoped prompt templates and pooling strategies, then add regression checks using reference behavior from model cards, particularly E5’s mean pooling logic and BGE-M3’s CLS definition.

This step is essential because once Noema offers multiple models, incorrect pooling becomes a silent quality regression that users will interpret as “RAG is unreliable.” citeturn0search0turn0search2

**Third delivery slice: transcription baseline via Apple Speech**

Add audio attachments and transcription using `SFSpeechRecognizer`, with on-device-only mode enforced when the user is in off-grid mode or when privacy settings demand it. The Speech framework already exposes the capability probes needed (`supportsOnDeviceRecognition`), and Apple’s live-audio guide shows how to set `requiresOnDeviceRecognition`. citeturn2search1turn2search9

This provides immediate product value and surfaces UI patterns that the Whisper backends can later reuse.

**Fourth delivery slice: Whisper backends and curated ASR models**

Introduce WhisperKit and whisper.cpp backends, choosing the best default per platform based on measured performance and operational constraints. WhisperKit’s emphasis on streaming, timestamps, and VAD is aligned with a polished UX; whisper.cpp offers portability and can be integrated via Swift packaging approaches described in its ecosystem. citeturn2search2turn3search1turn3search2

The ASR settings UI should mirror the embedding model approach:

- A curated list of ASR model sizes (tiny through large variants), with “fits” badges and a plain quality-speed description.
- Clear separation between “engine” (Apple Speech, WhisperKit, whisper.cpp) and “model” (specific Whisper variant).

**Fifth delivery slice: media as a retrievable knowledge source**

Once transcription is stable, treat audio and video transcripts as ingestible documents:

- Save transcripts as Stored items.
- Embed transcripts using the active embedding model.
- Allow dataset-style citation views when answers use transcript chunks.

This is where Noema gains the “interact with audio and video as well as documents” capability described in the feedback, in a way that reuses the existing retrieval architecture rather than building parallel systems. fileciteturn46file0L1-L450

**Risks and mitigations**

The main technical risks are silent quality degradation from incorrect pooling and templating, exploding storage from high-dimensional embeddings, and user confusion when indexes need rebuilding.

Each of these is addressable through design:

- Encode pooling and templates in the curated record and default to “model recommended,” exposing overrides only in advanced mode. citeturn0search0turn0search2turn4search4
- Prefer models that offer dimension control (Qwen3’s adjustable embedding dimensions are a meaningful lever) and surface this as an advanced storage-performance control with safe defaults. citeturn4search0turn4search1
- Make reindexing explicit, reversible, and understandable: a dataset should never silently degrade; it should be either “ready” or “needs reindex,” with a clear call to action. fileciteturn46file0L1-L220