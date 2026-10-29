# frozen_string_literal: true

require "ctx_driver"
require "json"

# 合成响应复用不可变正文，分别观察 Reader 与 Capture 的元数据分配；不测网络吞吐。
body = ("interface Ethernet1/1 up\n" * 200).freeze
receipt = Data.define(:output, :steps) do
  def success? = true
  def value! = output
end.new(output: body, steps: [ { command: "show interfaces" } ])
session = Object.new
session.define_singleton_method(:connected?) { true }
session.define_singleton_method(:send_commands) { |_| receipt }
time = Time.utc(2026, 1, 1).freeze
reader = CtxDriver::Reader.new(session: session, clock: -> { time })

puts RUBY_DESCRIPTION
puts "source=#{CtxDriver::Reader.instance_method(:read).source_location.first}"
3.times do |trial|
  GC.start
  allocated = GC.stat(:total_allocated_objects)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  capture = nil
  10_000.times { capture = reader.read("show interfaces") }
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  abort "Capture semantics changed" unless capture.success? && capture.body == body && capture.body.frozen?
  abort "Evidence changed" unless capture.evidence.first[:sha256] == Digest::SHA256.hexdigest(body)

  puts JSON.generate(trial: trial + 1, iterations: 10_000, bytes: body.bytesize,
    seconds: elapsed, allocations: GC.stat(:total_allocated_objects) - allocated)
end
