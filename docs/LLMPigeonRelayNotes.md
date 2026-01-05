# LLM Pigeon Server Relay Notes

## Repository snapshot
- Retrieved the Pigeon Server source via `curl -L https://github.com/permaevidence/LLM-Pigeon-Server/archive/refs/heads/main.tar.gz` and unpacked it locally for inspection.
- Primary relay logic lives in `Pigeon_ServerApp.swift` under the `Pigeon Server` target. The `CloudKitManager` singleton orchestrates the server-side pipeline.

## Key CloudKit patterns observed
- **Continuous polling plus push notifications.** The macOS app starts multiple timers (1s polling and 10s health checks) alongside push notification handling to ensure pending `Conversation` records are picked up promptly even if pushes are delayed.
- **Explicit queue management.** A `processingIDs` set guarantees a conversation is handled by at most one task at a time and prevents duplicate work from overlapping polls or push triggers.
- **Robust record updates.** Before saving completions, the manager refetches the latest CloudKit record, reapplies changes, and retries on `serverRecordChanged` conflicts. The `needsResponse`, `isGenerating`, and `stopRequested` flags are all updated atomically to reflect progress.
- **Detailed diagnostics.** Every major step—queueing, model selection reconciliation, inference start/finish, retries, and search augmentation—logs to a rolling timeline shown in the server UI. This makes it easy to trace slowdowns.
- **Stop/cancel coordination.** A background task polls the record for `stopRequested` and cancels inference promptly, also clearing flags when generation ends.

## Changes applied to Noema's relay helper
- Added a background polling loop with a 1s cadence so `CloudKitRelay` continuously drains pending work instead of relying on a single kickoff call.
- Switched to the async `records(matching:)` API for fetching `needsResponse == 1` conversations, matching Pigeon’s pattern and avoiding the previous delay-based query completion.
- Implemented conflict-aware record updates that refetch and retry saves, ensuring the reply and `needsResponse` flag land even if iOS updates the record mid-flight.
- Layered structured logging so macOS server builds can mirror Pigeon’s verbose timeline while debugging stuck sync states.
- Ensured failures leave the record flagged for retry and bump `lastUpdated`, making it easier to see stalled items in CloudKit dashboards.

## Follow-up opportunities
- Track `isGenerating` / `stopRequested` flags to support cooperative cancel requests from iOS.
- Mirror the `processingIDs` guard and richer metrics (latency tracking, provider info) from the Pigeon server for even better observability.
- Expose the logging feed through a simple UI or CLI so operators can monitor the relay without attaching a debugger.
- Adopt the dual-timer health checks from Pigeon (1s work polls, 10s watchdog) so the relay recovers even if a poll loop stalls.
- Persist structured log history to disk and surface it in an operator console, enabling after-the-fact debugging of failed generations.
- Translate Pigeon’s per-request status timelines into CloudKit metadata (e.g., `lastStarted`, `lastCompleted`) to help triage slow or stuck conversations.
