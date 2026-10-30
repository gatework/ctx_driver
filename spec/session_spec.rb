# frozen_string_literal: true

require_relative "spec_helper"
require "net/connector"
require "ctx_driver"
require "pp"

RSpec.describe CtxDriver::Session do
  let(:session) { Net::Connector.build(:cisco_ios, host: "192.0.2.1", username: "test-user") }

  def result_for(output)
    step = Net::Connector::Command::Result.new(command: Net::Connector::Command.new("show test"),
      output: output, prompt: "router#", duration: 0.01)
    Net::Connector::Result.new(steps: [ step ])
  end

  before do
    allow(session).to receive(:connected?).and_return(true)
    allow(session).to receive(:current_prompt).and_return("router#")
    expect(session).not_to receive(:connect)
    expect(session).not_to receive(:close)
  end

  it "refuses configuration writes on a closed borrowed session without reconnecting" do
    allow(session).to receive(:connected?).and_return(false)
    expect(session).not_to receive(:execute_command)
    expect { described_class.new(session).write_command("configure terminal") }.to raise_error(IOError)
  end

  it "returns a verifiable single-command receipt for sensitive configuration writes" do
    expect(session).to receive(:execute_command).with("show test", output_sensitive: true).once.and_return(result_for("show test\r\nrouter#"))
    response = described_class.new(session).write_command("show test")
    expect(CtxDriver::Receipt.validate(response, command: "show test")).to be(true)
  end

  it "hides borrowed connector internals without consulting its state during inspection", :aggregate_failures do
    borrowed = Object.new
    borrowed.instance_variable_set(:@password, "PASSWORD_SENTINEL")
    borrowed.define_singleton_method(:connected?) { raise "must not query" }
    adapter = described_class.new(borrowed)

    [ adapter.inspect, PP.pp(adapter, +"") ].each do |display|
      expect(display).to include("CtxDriver::Session")
      expect(display).not_to include("PASSWORD_SENTINEL", "@session")
    end
  end

  it "hides raw response internals during inspection while keeping explicit output access", :aggregate_failures do
    raw = "show test\r\nRAW_SENTINEL\r\nrouter#"
    steps = result_for(raw).steps
    result = Object.new
    result.instance_variable_set(:@raw, raw)
    result.define_singleton_method(:output) { raw }
    result.define_singleton_method(:steps) { steps }
    result.define_singleton_method(:success?) { true }
    allow(session).to receive(:execute_operation).and_return(result)
    response = described_class.new(session).send_commands([ "show test" ])

    [ response.inspect, response.to_s, PP.pp(response, +"") ].each do |display|
      expect(display).to include("CtxDriver::Session::Response")
      expect(display).not_to include("RAW_SENTINEL", "router#", "@raw", "result=")
    end
    expect(response.steps).to eq([ { command: "show test" } ])
    expect(response.output).to eq(raw)
    expect(response.value!).to eq("RAW_SENTINEL\n")
  end

  it "removes the matching echo and prompt while retaining indentation and repeated body lines" do
    raw = "show test\r\n  body\r\nshow test\r\nrouter#"
    expect(session).to receive(:execute_operation) do |script, **options|
      expect(options).to eq(name: :ctx_driver, privilege: false)
      expect(script.to_a.first).to be_output_sensitive
      result_for(raw)
    end
    capture = CtxDriver::Reader.new(session: session).read("show test")
    expect(capture).to be_success
    expect(capture.body).to eq("  body\nshow test\n")
    expect(capture.evidence.first[:sha256]).to eq(Digest::SHA256.hexdigest(raw))
  end

  it "removes a padded command echo without changing body indentation" do
    command = "  show test  "
    raw = "  show test\r\n  body\r\nrouter#"
    step = Net::Connector::Command::Result.new(command: Net::Connector::Command.new(command),
      output: raw, prompt: "router#", duration: 0.01)
    allow(session).to receive(:execute_operation).and_return(Net::Connector::Result.new(steps: [ step ]))
    capture = CtxDriver::Reader.new(session: session).read(command)

    expect(capture).to be_success
    expect(capture.command).to eq(command)
    expect(capture.body).to eq("  body\n")
  end

  it "retains completed source evidence when body decoding fails" do
    raw = "show test\r\ninvalid \xff\r\nrouter#".b
    allow(session).to receive(:execute_operation).and_return(result_for(raw))
    capture = CtxDriver::Reader.new(session: session).read("show test")
    expect(capture.failure).to include(code: :invalid_output_encoding, stage: :response)
    expect(capture.evidence.first.to_h).to include(sha256: Digest::SHA256.hexdigest(raw), bytes: raw.bytesize)
    expect(capture.body).to be_nil
  end

  it "preserves empty bodies and does not remove an unrelated first line" do
    { "router#" => "", "show test\r\nrouter#" => "",
      "  actual body\r\nrouter#" => "  actual body\n" }.each do |raw, expected|
      allow(session).to receive(:execute_operation).and_return(result_for(raw))
      capture = CtxDriver::Reader.new(session: session).read("show test")
      expect(capture).to be_success
      expect(capture.body).to eq(expected)
    end
  end

  it "retains the connector exception when a failed adapter response is decoded directly" do
    error = Net::Connector::Error.new("private failure")
    result = Net::Connector::Result.new(error: error)
    allow(session).to receive(:execute_operation).and_return(result)
    response = described_class.new(session).send_commands([ "show test" ])

    expect { response.value! }.to raise_error { |raised| expect(raised).to equal(error) }
  end

  it "validates exactly one command before consulting the borrowed connector" do
    expect(session).not_to receive(:current_prompt)
    expect(session).not_to receive(:execute_operation)
    [ nil, "show test", [], [ "first", "second" ], [ nil ], [ "show test\nreload" ] ].each do |commands|
      expect { described_class.new(session).send_commands(commands) }.to raise_error(ArgumentError)
    end
  end

  it "preserves a native timeout receipt and skips later queries after disconnection" do
    error = Net::Connector::CommandTimeout.new("private timeout", code: :command_timeout)
    result = Net::Connector::Result.new(error: error)
    allow(session).to receive(:connected?).and_return(true, false)
    expect(session).to receive(:execute_operation).once.and_return(result)
    reader = CtxDriver::Reader.new(session: session)

    capture = reader.read("show first")
    expect(capture.failure).to eq(code: :command_timeout, stage: :execute, error_type: "Net::Connector::CommandTimeout")
    expect(capture.body).to be_nil
    expect(capture.evidence.first.to_h).to include(bytes: 0, sha256: Digest::SHA256.hexdigest(""))
    expect(capture.to_h.to_s).not_to include("private timeout")
    skipped = reader.read("show next")
    expect(skipped).to be_skipped
    expect(skipped.failure).to eq(capture.failure)
    expect(skipped.evidence).to be_empty
  end
end
