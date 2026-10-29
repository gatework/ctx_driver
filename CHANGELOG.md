# Changelog

Changes to the public contract are recorded here. Versions follow Semantic Versioning.

## Unreleased

## 0.4.0 (2026-10-29)

- Use the parser command contract for borrowed-session reads; preserve single-command identity and stop-after-desynchronization behavior.
- Require ctx_parser 0.4.x.

## 0.3.0 (2026-10-29)

- Require every completed receipt step to identify the exact requested command as `{ command: String }`; malformed identities stop later queries while retaining raw fingerprints. Normalize native connector steps at the session boundary.

## 0.2.8 (2026-10-24)

- Leave the ctx_parser dependency unconstrained in the gemspec; applications select and lock a verified dependency combination.

## 0.2.7 (2026-10-23)

- Skip subsequent queries after malformed single-command receipts while preserving valid command failure and local decoding isolation.
- Update the documented session protocol and declare the required parser version.

## 0.2.6 (2026-10-23)

- Validate single-command receipts consistently without legacy rejection hooks; preserve borrowed-session ownership.

## 0.2.5 (2026-10-21)

- Add repository-specific AGENTS.md guidance for responsibilities, Ruby conventions, evidence boundaries and validation.
- Reject failed single-query receipts containing multiple completed commands while retaining source evidence.

## 0.2.4 (2026-10-18)

- Clear Bundler bootstrap variables when verifying packages in an isolated gem installation, including calls made through bundle exec.

## 0.2.3 (2026-10-18)

- Hide borrowed session, clock and response internals from inspection and pretty printing, including response string interpolation, without changing explicit output access.
- Reuse frozen clock values directly while retaining defensive snapshots for mutable times.

## 0.2.2 (2026-10-18)

- Adapt optional native sessions to net-connector 0.13.0 and newer, including command results, terminal decoding and safe error codes.
- Preserve response bodies before observation-clock callbacks can reuse their buffers, while retaining source evidence when decoding fails.
- Remove padded first-line command echoes without changing body indentation, and validate one-command input before consulting native sessions.
- Centralize command-text validation and safely share frozen command, body and timestamp values to avoid redundant snapshot allocations.
- Verify both dependency-free offline loading and the optional adapter through an installed package and a local PTY process.

## 0.2.1 (2026-10-17)

- Correct installation documentation to state the required ctx_parser 0.2.x API.

## 0.2.0 (2026-10-17)

- Require ctx_parser 0.2.x for the renamed public contracts.

- Mark an aborted command unusable for the current reader while propagating cancellation, including Thread termination, without closing or replaying the borrowed session.
- Snapshot start times and response bodies before subsequent caller callbacks can mutate them.
- Validate session and clock protocols, capture field types, and success/failure/skipped consistency.
- Ignore non-exception connector `Error` constants when classifying failures.
- Decode native responses without redundant output concatenation or a full array of body lines.

- Name the borrowed-session adapter `CtxDriver::Session` and load it from `ctx_driver/session`.

- Separate command receipt, command failure, and retained session failure terminology without changing execution behavior.

## 0.1.0 (2026-10-16)

### Added

- Borrowed-session command execution, immutable captures, safe diagnostics, and failure isolation.
- Standalone RubyGems packaging under `ctx_driver` with the `ctx_driver` require path and `CtxDriver` namespace.
- English and Chinese documentation, an offline example, and standalone RSpec/RuboCop development tasks.
- Linux/macOS CI, isolated package verification, and automatic RubyGems and GitHub Releases with identical artifacts.

### Fixed

- Adapt native net-connector sessions without implicit reconnect or privilege escalation; preserve explicit session failure semantics.

### Changed

- Cross-module dependencies resolve through RubyGems/Bundler instead of relative sibling paths.
- Motor persistence and application-specific adapters remain in the host application.
