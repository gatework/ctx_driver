# frozen_string_literal: true

require_relative "spec_helper"
require "json"

RSpec.describe CtxDriver::Source do
  it "rejects empty metadata, incomplete digests and ambiguous fields" do
    [ {}, { observed_at: Time.now }, { sha256: "a" * 64 }, { bytes: 0 },
      { sha256: "invalid", bytes: 0 }, { command: "show clock", status: nil },
      { command: "show clock", "command" => "show version" } ].each do |value|
      expect { described_class.coerce(value) }.to raise_error(ArgumentError)
    end
  end

  it "round trips JSON metadata and owns mutable context and timestamps" do
    context = { "ap_name" => +"AP-1" }
    source = described_class.new(command: "show clock", sha256: "a" * 64, bytes: 0,
      observed_at: Time.utc(2026, 10, 30), status: :complete, context: context)
    restored = described_class.coerce(JSON.parse(JSON.generate(source.to_h)))
    context["ap_name"].clear
    expect(restored).to eq(source)
    expect(source.context).to eq("ap_name" => "AP-1")
    expect(source).to be_verified
    expect { source.context.clear }.to raise_error(FrozenError)
    expect(source.with(status: :partial).status).to eq(:partial)
    expect { source.with(bytes: -1) }.to raise_error(ArgumentError)
    expect(source.inspect + source.to_s).not_to include("AP-1", "show clock")
  end
end
