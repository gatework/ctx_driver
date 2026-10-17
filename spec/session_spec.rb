# frozen_string_literal: true

require_relative "spec_helper"
require "net/connector"
require "ctx_driver"

RSpec.describe CtxDriver::Session do
  let(:session) { Net::Connector.build(:cisco_ios, host: "192.0.2.1", username: "test-user") }

  def result_for(output)
    step = Net::Connector::CommandResult.new(command: Net::Connector::Command.new("show test"),
      output: output, prompt: "router#", duration: 0.01)
    Net::Connector::Result.new(steps: [ step ])
  end

  before do
    allow(session).to receive(:connected?).and_return(true)
    allow(session).to receive(:current_prompt).and_return("router#")
    expect(session).not_to receive(:connect)
    expect(session).not_to receive(:close)
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

  it "retains completed source evidence when body decoding fails" do
    raw = "show test\r\ninvalid \xff\r\nrouter#".b
    allow(session).to receive(:execute_operation).and_return(result_for(raw))
    capture = CtxDriver::Reader.new(session: session).read("show test")
    expect(capture.failure).to include(code: :invalid_output_encoding, stage: :response)
    expect(capture.evidence.first).to include(sha256: Digest::SHA256.hexdigest(raw), bytes: raw.bytesize)
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

  it "preserves a native timeout receipt and skips later queries after disconnection" do
    error = Net::Connector::CommandTimeout.new("private timeout", code: :command_timeout)
    result = Net::Connector::Result.new(error: error)
    allow(session).to receive(:connected?).and_return(true, false)
    expect(session).to receive(:execute_operation).once.and_return(result)
    reader = CtxDriver::Reader.new(session: session)

    capture = reader.read("show first")
    expect(capture.failure).to eq(code: :command_timeout, stage: :execute, error_type: "Net::Connector::CommandTimeout")
    expect(capture.body).to be_nil
    expect(capture.evidence.first).to include(bytes: 0, sha256: Digest::SHA256.hexdigest(""))
    expect(capture.to_h.to_s).not_to include("private timeout")
    skipped = reader.read("show next")
    expect(skipped).to be_skipped
    expect(skipped.failure).to eq(capture.failure)
    expect(skipped.evidence).to be_empty
  end
end
