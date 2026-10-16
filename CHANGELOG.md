# Changelog

Changes to the public contract are recorded here. Versions follow Semantic Versioning.

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
