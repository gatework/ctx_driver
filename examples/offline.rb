# frozen_string_literal: true

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
