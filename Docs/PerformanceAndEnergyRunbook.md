# Performance & Energy Validation Runbook

This checklist helps ensure each release of Noema meets latency and power targets on iPhone and iPad hardware before shipping.

## Instruments Sessions

### 1. Time Profiler

1. Launch **Instruments → Time Profiler** targeting a representative device (A16 iPhone & M2 iPad).
2. Exercise the following flows:
   - Cold launch to chat ready state.
   - Importing and embedding a medium dataset (~50 MB PDF).
   - Running a Crew Mode contract that triggers `python.execute` and retrieval.
3. Flag regressions when:
   - Main-thread utilization exceeds 75 % for more than 2 s.
   - Dataset embedding spends >30 % time in JSON decoding or disk I/O layers.
   - Notebook execution blocks the main thread while awaiting WebView responses.
4. Capture a baseline trace and store it under `PerformanceBaselines/<release>/time-profiler.trace` for comparison.

### 2. Points of Hangs

1. Attach the **Points of Hangs** instrument while repeating the flows above.
2. Ensure no hangs exceed the 200 ms threshold; investigate any stacks rooted in SwiftUI layout or Core Data fetches.
3. Document fixes and re-run until the session is clean.

## Power Budget Validation

### Hardware Targets

* **iPhone** – iPhone 14 Pro (A16) on iOS 17.4
* **iPad** – iPad Pro 11" (M2) on iPadOS 17.4

### Workflow

1. Charge devices to 100 % and enable **Low Power Mode** off.
2. Connect to **Xcode → Energy Log** and record during:
   - 15 min mixed chat with retrieval.
   - 10 min Crew Mode run with notebook emissions.
3. Export logs and store them under `PerformanceBaselines/<release>/energy/<device>-<date>.elog`.
4. Compare against prior release budgets:
   - Average CPU usage ≤ 55 % (iPhone) / 65 % (iPad).
   - Foreground energy impact ≤ “Medium”.
   - No thermal throttling warnings.

### Pass/Fail Criteria

* If CPU or energy thresholds exceed the budget, capture deltas, file an issue, and block release until addressed.
* Maintain a changelog of mitigations (e.g., caching, task cancellation) alongside the logs for auditing.

## Reporting

* Summarize each validation run in the release notes with links to stored traces.
* Include a short narrative covering peak CPU, energy classification, and mitigations applied.
