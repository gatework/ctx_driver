# frozen_string_literal: true

require "ctx_driver"
require "net/connector"

# 用本地 PTY 驱动已安装连接器的完整会话；不连接网络设备。
class ExampleConnectorTransport < Net::Connector::Transports::Pty
  # 子进程先给出提示符，随后逐条回显查询和合成正文。
  def argv
    [ RbConfig.ruby, "-e", '$stdout.sync = true; print "device>"; while (line = gets); print line, "  interface Ethernet1/1 up\r\ndevice>"; end' ]
  end
end

configuration = Net::Connector::Configuration.new(host: "192.0.2.1", username: "audit", command_timeout: 2, login_timeout: 2)
device = Net::Connector.build(:cisco_ios, configuration: configuration, transport: ExampleConnectorTransport.new(configuration))
begin
  device.connect
  reader = CtxDriver::Reader.new(session: device)
  2.times do
    capture = reader.read("  show interfaces  ")
    abort "Connector capture failed" unless capture.success? && capture.body == "  interface Ethernet1/1 up\n"
    abort "Connector evidence missing" unless capture.evidence.one? && capture.evidence.first[:bytes].positive?
    abort "Borrowed session was closed" unless device.connected?
  end
  puts "Connector adapter: PTY, command echo, evidence and borrowed ownership passed"
ensure
  device.close
end
