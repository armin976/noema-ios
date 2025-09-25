# App Review Compliance Summary

This document captures how Noema satisfies App Store Review Guideline 2.5.2 and related platform policies when distributing the offline notebook and model tooling experience.

## Bundled Interpreter + Tooling

* **Offline Python runtime** – The Pyodide WebAssembly build is shipped inside the application bundle (`NoemaPython/pyodide`). Noema never downloads executable code at runtime; it only reads files already present in the bundle.
* **No dynamic code loading** – The app does not fetch or execute user-supplied binaries. Notebook execution runs inside the embedded WebAssembly sandbox and uses resources contained in the app bundle.
* **User-authored code only** – Users create notebook cells and code snippets themselves. The interpreter executes the user’s code and produces artifacts within the sandboxed cache directory.

## Dataset + Model Distribution

* **Curated datasets** – Open Textbook Library content is downloaded as static documents (PDF/EPUB/TXT) into the app’s `Documents/LocalLLMDatasets` container for offline use.
* **Model handling** – Hugging Face and manual model installs are retrieved as data files and stored in the sandbox. They are not executed directly and remain subject to the system’s file sandbox protections.

## User Visibility + Transparency

* **In-app disclosure** – Dataset download screens and the Notebook inspector clearly describe when content is sourced from the Open Textbook Library, Hugging Face, or Files.app imports.
* **Console + artifacts** – Notebook executions surface stdout/stderr logs and generated artifacts so users can inspect everything produced by the interpreter.

## Network Use + Privacy

* **Offline-first design** – All LLM inference, dataset embedding, and notebook execution occurs entirely on-device.
* **Explicit network toggles** – Settings screens expose switches for optional features (e.g., Brave Search proxy) so users can disable any network access.

## Submission Checklist

Before submitting to App Review:

1. Re-run the **Python enablement toggle** test to ensure notebook execution is disabled when the setting is off.
2. Verify the bundled Pyodide payload is present in the shipping archive and that no additional downloads occur after install.
3. Capture screenshots showing dataset import flows and the offline notebook console to demonstrate user-visible code execution.
4. Include this summary in the App Store Review Notes to pre-empt questions about guideline 2.5.2.
