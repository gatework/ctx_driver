# frozen_string_literal: true

require_relative "spec_helper"
require "json"
require "open3"
require "rbconfig"
require "bundler"
require "ctx_driver"

RSpec.describe CtxDriver::Reader do
  let(:time) { Time.new(2026, 10, 16, 12, 0, 0, "+08:00").freeze }
  let(:session) { double(:session, connected?: true) }
  let(:reader) { described_class.new(session: session, clock: -> { time }) }
  let(:body) { +"private command body" }
  let(:output) { +"show test\n#{body}\ndevice#" }
  let(:receipt) { double(:receipt, output: output, success?: true, steps: [ Object.new ], value!: body) }

  it "rejects unsupported connector protocols before any query can be classified as a device failure" do
    legacy_session = double(:legacy_session, connected?: true)
    expect(legacy_session).not_to receive(:connected?)

    expect { described_class.new(session: legacy_session) }
      .to raise_error(ArgumentError, "Session must implement #send_commands for the command driver protocol")
  end

  it "reads once and exposes immutable provenance separately from the private body" do
    expect(session).to receive(:send_commands).with([ "show test" ]).once.and_return(receipt)
    expect(session).not_to receive(:connect)
    expect(session).not_to receive(:close)
    capture = reader.read("show test")
    body.replace("changed")
    expect(capture).to be_success
    expect(capture.body).to eq("private command body")
    expect(capture.body).to be_frozen
    expect(capture.evidence).to eq([ { command: "show test", sha256: Digest::SHA256.hexdigest(output),
      bytes: output.bytesize, observed_at: "2026-10-16T04:00:00.000000Z" } ])
    expect { capture.evidence.first[:bytes] = 0 }.to raise_error(FrozenError)
    expect([ capture.to_h, capture.as_json, capture.inspect ].to_json).not_to include("private command body", "device#")
    expect(time.utc_offset).to eq(28_800)
  end

  it "continues after an independent execution failure without replaying the failed query" do
    expect(session).to receive(:send_commands).with([ "show first" ]).once.and_raise(IOError, "private exception")
    expect(session).to receive(:send_commands).with([ "show next" ]).once.and_return(receipt)
    failed = reader.read("show first")
    expect(failed.failure).to eq(code: :command_execution_failed, stage: :execute, error_type: "IOError")
    expect(failed.to_h.to_json).not_to include("private exception")
    expect(reader.read("show next")).to be_success
  end

  it "only enables rejection preservation when the adapter explicitly declares the option" do
    calls = []
    adapter = Object.new
    adapter.define_singleton_method(:connected?) { true }
    result = receipt
    adapter.define_singleton_method(:send_commands) do |commands, preserve_session_on_rejection: false|
      calls << [ commands, preserve_session_on_rejection ]
      result
    end
    expect(described_class.new(session: adapter).read("show test")).to be_success
    expect(calls).to eq([ [ [ "show test" ], true ] ])
  end

  it "does not infer rejection support from a generic keyword sink" do
    adapter = Object.new
    adapter.define_singleton_method(:connected?) { true }
    result = receipt
    adapter.define_singleton_method(:send_commands) do |_commands, **options|
      raise "unexpected options" unless options.empty?
      result
    end
    expect(described_class.new(session: adapter).read("show test")).to be_success
  end

  it "preserves the first disconnect cause and skips all later queries" do
    allow(session).to receive(:connected?).and_return(true, false)
    expect(session).to receive(:send_commands).with([ "show first" ]).once.and_raise(IOError, "transport private")
    expect(session).not_to receive(:send_commands).with([ "show next" ])
    first = reader.read("show first")
    skipped = reader.read("show next")
    expect(skipped).to be_skipped
    expect(skipped.failure).to eq(first.failure)
    expect(skipped.evidence).to be_empty
    expect { reader.failure[:code] = :changed }.to raise_error(FrozenError)
  end

  it "keeps a completed capture when the subsequent state check fails" do
    expect(session).to receive(:connected?).ordered.and_return(true)
    expect(session).to receive(:send_commands).ordered.and_return(receipt)
    expect(session).to receive(:connected?).ordered.and_raise(IOError, "state private")
    expect(reader.read("show first")).to be_success
    expect(reader.read("show next").failure).to eq(code: :session_state_failed, stage: :session, error_type: "IOError")
  end

  [ nil, "connected", 1 ].each do |state|
    it "does not execute with an ambiguous #{state.inspect} connection state" do
      allow(session).to receive(:connected?).and_return(state)
      expect(session).not_to receive(:send_commands)
      expect(reader.read("show test").failure).to include(code: :session_state_failed)
    end
  end

  [ [], [ Object.new, Object.new ], nil ].each do |steps|
    it "rejects a successful receipt with #{steps&.size.inspect} completed steps and retains provenance" do
      allow(receipt).to receive(:steps).and_return(steps)
      expect(session).to receive(:send_commands).and_return(receipt)
      expect(receipt).not_to receive(:value!)
      capture = reader.read("show test")
      expect(capture.failure).to include(code: :invalid_command_result, stage: :response)
      expect(capture.evidence.first[:sha256]).to eq(Digest::SHA256.hexdigest(output))
    end
  end

  it "keeps source evidence when clean body extraction raises" do
    expect(session).to receive(:send_commands).and_return(receipt)
    allow(receipt).to receive(:value!).and_raise(ArgumentError, "body secret")
    capture = reader.read("show test")
    expect(capture.failure).to include(code: :invalid_command_result, stage: :response)
    expect(capture.evidence).not_to be_empty
    expect(capture.body).to be_nil
  end

  it "rejects invalid commands before consulting or executing the session" do
    expect(session).not_to receive(:connected?)
    expect(session).not_to receive(:send_commands)
    [ "", "  ", "show test\nreload", nil ].each do |command|
      expect { reader.read(command) }.to raise_error(ArgumentError)
    end
  end

  it "does not swallow cancellation" do
    expect(session).to receive(:send_commands).and_raise(Interrupt)
    expect { reader.read("show test") }.to raise_error(Interrupt)
  end

  it "stops reuse after cancellation during execution or response decoding" do
    [ :execute, :response ].each do |stage|
      adapter = Object.new
      adapter.define_singleton_method(:connected?) { true }
      result = receipt
      adapter.define_singleton_method(:send_commands) do |_commands|
        raise Interrupt if stage == :execute
        result
      end
      allow(receipt).to receive(:value!).and_raise(Interrupt) if stage == :response
      driver = described_class.new(session: adapter)

      expect { driver.read("show first") }.to raise_error(Interrupt)
      expect(adapter).not_to receive(:send_commands)
      skipped = driver.read("show next")
      expect(skipped).to be_skipped
      expect(skipped.failure).to eq(code: :command_aborted, stage: stage)
      expect(skipped.evidence).to be_empty
    end
  end

  it "marks an abandoned query unusable even when Thread kill bypasses rescue" do
    entered, release = Queue.new, Queue.new
    adapter = Object.new
    adapter.define_singleton_method(:connected?) { true }
    adapter.define_singleton_method(:send_commands) do |_commands|
      entered << :executing
      release.pop
    end
    driver = described_class.new(session: adapter)
    worker = Thread.new { driver.read("show first") }
    expect(entered.pop(timeout: 2)).to eq(:executing)
    worker.kill
    expect(worker.join(2)).to equal(worker)
    expect(adapter).not_to receive(:send_commands)

    skipped = driver.read("show next")
    expect(skipped).to be_skipped
    expect(skipped.failure).to eq(code: :command_aborted, stage: :execute)
  ensure
    worker&.kill
    worker&.join(2)
  end

  it "snapshots the body before the next session callback can reuse its buffer" do
    expect(session).to receive(:send_commands).and_return(receipt)
    checks = 0
    allow(session).to receive(:connected?) do
      checks += 1
      body.replace("next response") if checks > 1
      true
    end

    capture = reader.read("show test")
    expect(capture.body).to eq("private command body")
    expect(body).to eq("next response")
    expect(body).not_to be_frozen
  end

  it "snapshots the start timestamp before executing caller code" do
    shared_time = Time.new(2026, 10, 16, 12, 0, 0, "+08:00")
    expect(session).to receive(:send_commands) do
      shared_time.utc
      receipt
    end
    capture = described_class.new(session: session, clock: -> { shared_time }).read("show test")

    expect(capture.started_at.utc_offset).to eq(28_800)
    expect(capture.completed_at.utc_offset).to eq(0)
    expect(shared_time).not_to be_frozen
  end

  it "rejects incomplete session and clock protocols without querying the device" do
    missing_state = Object.new
    missing_state.define_singleton_method(:send_commands) { |_| raise "must not execute" }
    expect { described_class.new(session: missing_state) }.to raise_error(ArgumentError, /connected/)
    adapter = Object.new
    adapter.define_singleton_method(:connected?) { raise "must not query state" }
    adapter.define_singleton_method(:send_commands) { |_| raise "must not execute" }
    expect { described_class.new(session: adapter, clock: nil) }.to raise_error(ArgumentError, /callable/)
    driver = described_class.new(session: adapter, clock: -> { "invalid time" })
    expect { driver.read("show test") }.to raise_error(TypeError, "Clock must return a Time")
  end

  it "loads and captures without Rails, net-connector or business domains" do
    library = File.expand_path("../lib", __dir__)
    script = <<~RUBY
      require "ctx_driver"
      abort "unexpected dependency" if defined?(Rails) || defined?(Net::Connector::Result) || defined?(CtxChecker::Collector) || defined?(Vxlan::Collector)
      result = Data.define(:output, :steps) do
        def success? = true
        def value! = "body"
      end.new(output: "raw", steps: [1])
      session = Object.new
      session.define_singleton_method(:connected?) { true }
      session.define_singleton_method(:send_commands) { |_| result }
      puts CtxDriver::Reader.new(session: session).read("show test").success?
    RUBY
    output, status = Open3.capture2e(RbConfig.ruby, "-rbundler/setup", "-I", library, "-e", script)
    expect(status.success?).to be(true), output
    expect(output).to eq("true\n")
  end
end

RSpec.describe CtxDriver::Failure do
  it "does not replace the original failure when a connector declares a non-exception Error constant" do
    [ nil, "error", Object ].each do |value|
      type = Class.new
      type.const_set(:Error, value)
      connector = type.new
      expect(described_class.connection_error?(IOError.new, connector)).to be(true)
      expect(described_class.connection_error?(ArgumentError.new, connector)).to be(false)
    end
  end

  it "recognizes an inherited connector error without swallowing unrelated programming errors" do
    parent = Class.new
    parent.const_set(:Error, Class.new(StandardError))
    connector = Class.new(parent).new

    expect(described_class.connection_error?(parent::Error.new, connector)).to be(true)
    expect(described_class.connection_error?(IOError.new, connector)).to be(true)
    expect(described_class.connection_error?(ArgumentError.new, connector)).to be(false)
  end
end
