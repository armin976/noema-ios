# Noema

**Noema** brings large-language-model intelligence to your iPhone and iPad while keeping all of your data and processing completely offline. By combining local AI models with curated textbooks and your own documents, it provides a powerful on-device knowledge assistant without sacrificing privacy.

## Key Features

### Offline models from Hugging Face
- **Integrated model search** – Browse the Hugging Face hub directly inside the app. The registry constructs API queries against https://huggingface.co/api/models to find models and returns records with metadata such as model ID, author, tags and available quantization formats.
- **One-tap downloads with progress** – The download manager emits events like started, progress, verifying and finished during each installation. Models are downloaded into the app’s sandbox, verified and cached so you can resume or pause downloads at any time.
- **Automatic dependency management** – For models that require additional files (e.g., configuration or tokenizer files), the installer fetches and stores them along with the weights.

### Open Textbook Library (OTL) integration
- Browse the Open Textbook Library from within Noema. A dedicated registry searches the catalog and caches the results locally.
- Import full textbooks. Downloaded PDFs or EPUBs are embedded on device and indexed for retrieval.

### Bring your own documents
- Add personal PDF or EPUB files and optionally text/markdown files. The dataset detail view recognises supported formats – PDF, EPUB, TXT, MD, JSON, JSONL, CSV and TSV – and warns when a dataset contains only unsupported types.
- All documents are embedded into a retrieval index for retrieval-augmented generation (RAG). You can ask questions and Noema will search your documents and cite passages without sending anything to the cloud.

### Triple-backend model support
Noema is the first mobile LLM app to support three different model formats:
- **GGUF** – high-performance quantized weights used by llama.cpp.
- **MLX** – Apple’s Metal-accelerated MLX format for running models natively on Apple Silicon.
- **SLM (Liquid AI)** – Liquid AI’s “small language model” format.

These formats are represented in the app’s `ModelFormat` enum (`gguf`, `mlx`, `slm`, `apple`), enabling you to choose the right balance of speed and memory use. The RAM advisor heuristics estimate the working-set footprint for each format and compute whether a model fits into the device’s memory budget. Functions such as `fitsInRAM()` and `maxContextUnderBudget()` report whether a given model/context will run comfortably on your device.

### RAM check & model size helper
A built-in RAM adviser uses device-specific limits to estimate how much memory is available. It multiplies the quantized weight size by a format-specific factor and adds estimates for the key-value cache to determine whether a model of a given size and context length fits. It can also compute the maximum context length that fits under budget and exposes this information in the UI so you can pick an appropriate model and prompt length.

### Built-in tool calling and retrieval-augmented generation
Noema implements a flexible tool calling system for both llama.cpp (server and in-process modes) and MLX backends. Tools can be called automatically during a chat session to perform functions such as:
- Web search using Brave Search through a user-configured proxy (`BRAVE_SEARCH_PROXY_URL` environment variable or `BraveSearchProxyURL` in Info.plist).
- Document retrieval against your locally indexed datasets.
- Custom functions exposed through the app’s tool registry.

When tool calling is enabled, the model can issue JSON tool calls and receive structured responses, making it easy to access your documents without exceeding context limits.

### Offline Python notebook & analytics pane
- **Headless Pyodide runtime** – A bundled Pyodide WebAssembly build powers the `python.execute` tool. The interpreter runs inside a hidden `WKWebView`, entirely offline with wheels for `numpy`, `pandas` and `matplotlib` included in the app bundle.
- **Notebook pane** – On iPad the chat view now shows a split layout: chat on the left, a live Notebook on the right. iPhone devices can open the Notebook from the chat toolbar. Each Python execution records stdout/stderr plus table and image artefacts directly into the notebook cells.
- **Dataset sharing** – Import CSV files through Files.app. Any files placed in `On My iPhone/iPad > Noema > Datasets` are exposed to Pyodide via the custom `appdata://` scheme handled by `AppDataSchemeHandler`.
- **Settings toggle** – Disable or enable Python execution under **Settings → Python → Enable offline Python**. When disabled, notebook cells render but the `Run` button is inactive.

#### Sample workflow
1. Import the bundled sample dataset from the Files app (`sample.csv` under *Noema ▸ Samples*).
2. In chat, ask the assistant: “Summarize null counts and plot histograms for the numeric columns in sample.csv.”
3. The model calls `python.execute` with a payload similar to:
   ```python
   import pandas as pd, matplotlib.pyplot as plt
   df = pd.read_csv("/data/sample.csv")
   print(df.isna().sum().to_frame("nulls").to_json(orient="table"))
   numeric = df.select_dtypes(include="number")
   numeric.hist(figsize=(8, 6))
   plt.tight_layout()
   plt.savefig("/tmp/hist.png", dpi=180)
   ```
4. The Notebook pane captures the JSON table preview and histogram image. You can export the notebook as Markdown plus JSON metadata or re-run the code cell to iterate on analysis.

The entire workflow functions in airplane mode and satisfies App Store rule 2.5.2 because all executable code is user-authored and shipped inside the binary.

### Low-RAM, high-knowledge design
Instead of embedding all knowledge inside huge model weights, Noema emphasises external knowledge sources. By pairing compact models with large local datasets (textbooks, PDFs, etc.), you can store far more information on-device than would be possible if the weights contained all of it. Retrieval-augmented generation ensures that the assistant cites relevant passages from your data rather than hallucinating answers.

### Advanced settings for power users
- **Context length and quantization** – adjust the prompt context size and quantization level to trade off quality versus speed and memory usage.
- **GPU acceleration** – enable or disable Metal acceleration for supported models.
- **Tool-calling** – toggle built-in tools and set timeouts or maximum tool turns.

### Privacy-first & offline
All processing happens on your device. The app never sends your chats, files or downloaded models to any server. Even web search uses your local Brave proxy configuration, and offline mode disables network access entirely. Combined with Apple sandboxing, this ensures that your data remains private.

---

## Getting Started

### Requirements
- iOS 17 / iPadOS 17 or later with Apple Silicon (A12 Bionic or newer).
- Enough free storage space to accommodate downloaded models and datasets (models range from a few hundred megabytes to multiple gigabytes; textbooks vary by file size).


### Installation
```bash
git clone https://github.com/armin976/Noema.git
cd Noema
```
Open the Xcode project (`Noema.xcodeproj`) and choose the Noema target.

Run on your device. Because the app uses on-device model execution, you must deploy to a physical iPhone/iPad rather than the simulator.

Once the app launches, visit the Explore tab to search and install a model. You can then browse the Datasets tab to import textbooks or add your own documents. The Settings tab exposes advanced options including context length, tool-calling and offline mode.

### Configuration
- **Brave Search** – provide a proxy URL via the `BRAVE_SEARCH_PROXY_URL` environment variable or add `BraveSearchProxyURL` to your Info.plist. Without this configuration the web search tool remains disabled.
- **RevenueCat Purchases** – supply your key with the `REVENUECAT_API_KEY` environment variable or `RevenueCatAPIKey` in Info.plist if you enable subscriptions.
- **Server mode** – optionally set `LLAMA_SERVER_URL` to point to a llama.cpp server if you prefer remote inference.

---

## Contributing
Contributions are welcome! Feel free to open issues or pull requests to improve features, add new tools or fix bugs. For substantial changes, please discuss your ideas in an issue first.

---

## License
This project is licensed under the [MIT License](LICENSE).

---

## Acknowledgements
Noema builds upon open-source communities including llama.cpp, MLX, Liquid AI’s SLM and the Open Textbook Library. Huge thanks to these projects for making offline AI on mobile devices possible.
