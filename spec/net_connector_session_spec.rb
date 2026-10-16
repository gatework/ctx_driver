# frozen_string_literal: true

require_relative "spec_helper"
require "net/connector"
require "ctx_driver"

RSpec.describe CtxDriver::NetConnectorSession do
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
end
