# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe CtxDriver::Capture do
  let(:time) { Time.now }
  let(:attributes) { { command: "show test", body: "", started_at: time, completed_at: time } }

  it "rejects invalid receipt fields before constructing an immutable capture" do
    [ { command: nil }, { command: "" }, { command: "show test\nreload" }, { body: [] },
      { started_at: "time" }, { completed_at: 1 }, { evidence: nil }, { evidence: [ :error ] },
      { failure: false }, { failure: [] }, { skipped: "false" } ].each do |invalid|
      expect { described_class.new(**attributes.merge(invalid)) }.to raise_error(ArgumentError)
    end
  end

  it "distinguishes empty success, failure and skipped execution without contradictory evidence" do
    failure = { code: :session_closed, stage: :session }
    expect(described_class.new(**attributes)).to be_success
    [ { body: nil }, { failure: failure }, { skipped: true },
      { body: nil, failure: failure, skipped: true, evidence: [ { bytes: 0 } ] } ].each do |invalid|
      expect { described_class.new(**attributes.merge(invalid)) }.to raise_error(ArgumentError)
    end
    skipped = described_class.new(**attributes.merge(body: nil, failure: failure, skipped: true))
    expect(skipped).to be_skipped
    expect(skipped).not_to be_success
    expect(skipped.body).to be_nil
  end

  it "detaches all receipt metadata while keeping raw body access explicit" do
    command, body = +"show test", +"PRIVATE_BODY"
    evidence = [ { command: command, context: { tags: [ +"original" ] } } ]
    capture = described_class.new(**attributes.merge(command: command, body: body, evidence: evidence))
    command.clear
    body.clear
    evidence.first[:context][:tags].first.clear
    time.utc

    expect(capture.command).to eq("show test")
    expect(capture.body).to eq("PRIVATE_BODY")
    expect(capture.evidence.first[:context][:tags]).to eq([ "original" ])
    expect(capture.started_at).not_to equal(time)
    expect(capture.started_at).to be_frozen
    expect { capture.evidence.first[:context][:tags] << "changed" }.to raise_error(FrozenError)
    [ capture.to_h, capture.as_json, capture.inspect, capture.to_s ].each do |metadata|
      expect(metadata.to_s).not_to include("PRIVATE_BODY")
    end
  end
end
