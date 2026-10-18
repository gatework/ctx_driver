# frozen_string_literal: true

require "net/connector"
require "ctx_driver/session"
require "json"

# 合成回显与预期正文在计时前构造；测量三次解码，结束后校验正文。
puts RUBY_DESCRIPTION
puts "source=#{CtxDriver::Session.instance_method(:send_commands).source_location.first}"
[ 20_000, 100_000 ].each do |lines|
  expected = "  interface Ethernet1/1\n" * lines
  raw = "show test\n#{expected}router#"
  step = Net::Connector::Command::Result.new(command: Net::Connector::Command.new("show test"), output: raw, prompt: "router#", duration: 0.01)
  receipt = Net::Connector::Result.new(steps: [ step ])
  adapter = Object.new
  adapter.define_singleton_method(:connected?) { true }
  adapter.define_singleton_method(:current_prompt) { "router#" }
  adapter.define_singleton_method(:execute_operation) { |*args, **options| receipt }
  response = CtxDriver::Session.new(adapter).send_commands([ "show test" ])
  3.times do |trial|
    GC.start
    allocated = GC.stat(:total_allocated_objects)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    bodies = 3.times.map { response.value! }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    allocated = GC.stat(:total_allocated_objects) - allocated
    abort "Body semantics changed" unless bodies.all? { |body| body == expected }
    puts JSON.generate(lines: lines, bytes: raw.bytesize, iterations: 3, trial: trial + 1, seconds: elapsed, allocations: allocated)
  end
end
