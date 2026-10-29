# ctx_driver

[简体中文](README-zh.md) | [Source](https://github.com/gatework/ctx_driver) | [Changelog](CHANGELOG.md)

An atomic command-execution boundary for borrowed network sessions. It records safe evidence for one command, validates connector responses, and preserves the first unavailable-session reason across subsequent skipped commands.

## Features

- `Reader` sends one declared command at a time through an injected session.
- `Capture` separates command bodies from safe metadata and fingerprints.
- Independent command rejection can leave a synchronized session usable.
- Session loss stops further submissions without reconnecting or replaying.

## Installation

Requires **Ruby 4.0.6 or newer**. Add this line to your application's `Gemfile`:

```ruby
gem "ctx_driver"
```

Then run `bundle install`, or install directly with `gem install ctx_driver`. The require path is `ctx_driver` and the public namespace is `CtxDriver`; package names and Ruby namespaces are intentionally separate.

Internal runtime dependencies: [`ctx_parser`](https://github.com/gatework/ctx_parser). The gemspec leaves their versions unconstrained; applications should commit a verified `Gemfile.lock` for reproducible deployments. No Rails boot or sibling checkout paths are required.

Release artifacts and checksums are available from [GitHub Releases](https://github.com/gatework/ctx_driver/releases). Check [RubyGems](https://rubygems.org/gems/ctx_driver) for published versions.

## Offline example

From a development checkout after installing dependencies:

```sh
bundle exec ruby examples/offline.rb
```

The example uses synthetic data and performs no network access:

```ruby
require "ctx_driver"

# 用本地替身表示单条连接器结果，不打开套接字。
ExampleResponse = Data.define(:output, :steps) do
  # 确认本例合成命令已成功完成。
  def success? = true

  # 返回已去除终端修饰的命令正文。
  def value! = output
end

# 借用会话示例仅实现 Reader 所需的传输协议。
class ExampleSession
  # 本演示会话始终处于可用状态。
  def connected? = true

  # 接受声明的查询并返回单条合成命令结果。
  def send_commands(commands)
    raise ArgumentError, "Unexpected query" unless commands == [ "show interfaces" ]

    ExampleResponse.new(output: "Ethernet1/1 is up\n", steps: [ { command: commands.first } ])
  end
end

capture = CtxDriver::Reader.new(session: ExampleSession.new).read("show interfaces")
abort "Capture failed: #{capture.failure[:code]}" unless capture.success?

puts "Capture status: success"
puts "Command: #{capture.command}"
puts "Bytes: #{capture.evidence.first[:bytes]}"
puts "SHA-256: #{capture.evidence.first[:sha256]}"
# 通过 capture.body 显式访问正文；默认序列化不包含正文。
```

## Public contract and limits

`Reader.new(session:, clock:).read(command)` returns a `Capture`. Inspect `success?`, `skipped?`, `failure`, and `evidence`; access the body explicitly through `body`. `to_h`, `as_json`, and `inspect` omit the body. `Reader`, the borrowed `Session` adapter, and its response use safe `inspect`/`PP` displays that do not traverse caller-owned objects or consult connection state. Response string interpolation is also safe; raw output and decoded bodies remain available through explicit response APIs.

A custom session implements `connected?` and `send_commands([command])`. Already loaded `Net::Connector::Base` sessions from net-connector **0.13.0 or newer** are adapted automatically through `execute_operation`, without connecting or requesting privilege. The adapter removes the matched prompt and first-line command echo, and keeps raw bytes only in the explicit capture evidence boundary. A native connector that closes on command rejection stays closed; later reads are skipped. A response exposes `output`, a boolean `success?`, an array `steps`, `value!` for a successful body, and `error` on failure. A successful read must contain exactly one completed step. A failed receipt may contain at most one completed step. Invalid output, status or step counts stop later queries even when the session remains connected; validated receipts with local decoding or clock errors do not invalidate session synchronization.

net-connector remains optional: applications using this adapter must declare `gem "net-connector", ">= 0.13.0"` themselves. `examples/connector.rb` exercises the installed adapter through a local PTY process without opening network connections.

Use each reader sequentially; create separate readers for concurrent devices. The caller owns connection, disconnection, credentials, and approved command selection. Reader does not decide whether arbitrary command text is read-only. Standard execution/response errors become safe diagnostics; cancellation signals propagate.

Detailed vendor behavior, historical validation notes, and Motor-only integration are preserved in [the architecture reference](docs/architecture-zh.md). Host integration examples in that reference require Motor; they are not standalone gem APIs. Motor adapters live under `backend/lib/baseline`, `backend/lib/vxlan`, and `backend/lib/wireless` in the [Motor repository](https://github.com/gatework/motor/tree/main/backend/lib).

## Domain vocabulary

A command receipt belongs to one execution; a `Capture` holds its processed body and safe evidence metadata. Command failure and session failure have different lifetimes: an independent command may fail while the session remains usable, whereas `Reader#failure` retains the first cause that prevents further queries. `Capture#success?` describes execution, not parsing completeness or device health.

Cancellation during execution or response processing propagates and marks the reader with `command_aborted`. Later reads are skipped even if the borrowed session still reports connected; the host retains responsibility for closing or replacing it.

The clock must be callable and return `Time`. Mutable times and response bodies are copied before later callbacks can mutate them; frozen `Time` values are reused directly, and immutable bodies may be shared. The observation clock runs after the source fingerprint and body snapshot have been fixed, so its callback cannot mix two responses. Successful captures require a string body (including an empty string); failed captures have no body, and skipped captures require a failure without execution evidence. Wall-clock timestamps can move backwards and are not elapsed-time measurements.

## Development and tests

Name shared classes by their responsibility and use the namespace for platform context. Preserve filenames and class names that directly match device commands.

```sh
bundle install
bundle exec rake
bundle exec ruby examples/offline.rb
bundle exec rake build
```

`bundle exec rake` runs RSpec, RuboCop, and the offline examples. Tests live in `spec/`, following the existing project's RSpec convention; fixtures use synthetic or sanitized evidence. Add regression cases for successful, incomplete, unsupported, and malformed inputs when extending a parser. Offline tests do not certify all device versions or replace live integration checks.

Use the declared minimum Ruby version for compatibility checks. Document source methods and non-obvious business logic in concise Chinese, preserve public return/error contracts, and never add raw device captures or credentials to examples, fixtures, logs, or release archives.

Run `bundle exec ruby -Ilib benchmark/body.rb` to measure body decoding, or `bundle exec ruby -Ilib benchmark/reader.rb` for 10,000 sequential captures per trial. Both report allocations and elapsed time against synthetic output, with semantic checks. Compare versions under the same Ruby, input and host; these do not measure device network throughput.

## Release

This directory can be maintained as the independent [ctx_driver](https://github.com/gatework/ctx_driver) repository. Update `VERSION` and `CHANGELOG.md`, run the validation and build commands above, and inspect the packaged file list before tagging `vVERSION`.

CI runs tests, lint, examples, build, and an isolated installation on Linux and macOS. After CI passes on `main`, push `vVERSION` to run the release workflow. It publishes the tested Linux artifact to RubyGems and GitHub Releases, attaches `SHA256SUMS`, and verifies downloaded bytes. The GitHub `release` environment accepts a `RUBYGEMS_API_KEY` secret; without it, configure RubyGems Trusted Publishing for this repository, `release.yml`, and the `release` environment. Retry a failed publish job to reuse its CI artifact; an already published version must have identical bytes. See [release details](docs/release.md).

Publish dependency gems first. A Git tag, a successful build, or a workflow file does not establish that the gem has reached RubyGems; confirm the registry result separately. See [CHANGELOG.md](CHANGELOG.md) for release notes.

## License

MIT. See [LICENSE](LICENSE).


Receipt protocol: each completed step is `{ command: String }` with exactly the requested command bytes. Success requires one step; failure permits zero or one. Opaque placeholder steps are no longer accepted. Missing or mismatched identity yields `invalid_command_result` and stops later queries while retaining raw fingerprints. Session adapts native net-connector steps automatically.

本次使用 ctx_parser 0.4 系列契约；`Result` 新增 `covered_scopes`，单行命令统一由 `CtxParser::Commands.command_text` 校验。跨模块约定见 [ctx_runner 契约迁移](https://github.com/gatework/ctx_runner/blob/main/docs/contracts-2026-10-29.md)。
