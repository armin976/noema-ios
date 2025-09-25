# Quality Gates

Noema's continuous integration workflow enforces a strict set of checks to keep the project healthy and deterministic.

## Automated checks

The CI workflow (`.github/workflows/ci.yml`) runs on every push and pull request and performs the following steps:

1. **Debug build** – `xcodebuild` performs a clean Debug build of the `Noema` scheme with warnings treated as errors, strict concurrency checking, and the Undefined Behavior Sanitizer enabled.
2. **Release build** – the Release configuration builds with the same warning and concurrency gates to ensure shipping bits stay strict.
3. **Unit tests** – `xcodebuild test` runs the test suite on an iOS Simulator to keep the notebook runtime, cache, and scheme handler behaviour covered.
4. **Static analysis** – `xcodebuild analyze` must complete without emitting new warnings.
5. **Archive validation** – `xcodebuild archive` produces a signed archive, verifying that codesign settings remain valid.
6. **Optional Swift formatting** – if a `.swiftformat` configuration file is present, CI installs `swiftformat` so formatting checks can be added locally without breaking automation.

All warnings fail the build in every configuration, so new code must be warning-free before merging.

## Local workflows

The `Makefile` mirrors the CI pipeline:

```bash
make build    # Debug + Release builds
make test     # Run the XCTest suite
make analyze  # Static analysis
make archive  # Verify archive settings
make ci       # Runs the full sequence above
```

Developers should run `make ci` before opening a pull request to catch issues early.

## Debug Self-Check

Debug builds expose **Debug ▸ Run Self-Check**, a three-step diagnostic harness that verifies:

1. The embedded Pyodide runtime can import `sys` and `pandas` and emit version metadata.
2. The Python result cache can persist and reload a notebook run (tables plus a tiny PNG image).
3. Path traversal protection rejects dataset requests that leave the allowed roots.

Results are written to `Documents/Diagnostics/last_report.md` and presented via Quick Look so issues can be shared easily.
