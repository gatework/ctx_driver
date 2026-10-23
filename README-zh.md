# ctx_driver

[English](README.md) | [源码](https://github.com/gatework/ctx_driver) | [变更记录](CHANGELOG.md)

借用网络会话的单命令执行边界，验证连接器回执、保存安全证据，并在会话不可用后保留首个原因，将后续命令明确标记为跳过。

## 能力

- `Reader` 通过注入会话逐条执行已声明命令。
- `Capture` 将命令正文与安全元数据、指纹分开。
- 单命令拒绝后，已确认同步的会话可以继续执行其他查询。
- 会话断开后停止提交，不自动重连或重放。

## 安装

要求 **Ruby 4.0.6 或更新版本**。在应用的 `Gemfile` 中添加：

```ruby
gem "ctx_driver"
```

然后执行 `bundle install`；也可直接执行 `gem install ctx_driver`。Ruby 加载入口为 `ctx_driver`，公开命名空间为 `CtxDriver`；gem 包名与 Ruby 命名空间分别维护。

模块运行依赖：[`ctx_parser`](https://github.com/gatework/ctx_parser)。 共享 Gatework 依赖要求兼容的 0.2.x API；应用应提交自己的 `Gemfile.lock`，保持部署可复现。使用本库不需要启动 Rails 或配置兄弟模块的本地路径。

发布产物和校验值见 [GitHub Releases](https://github.com/gatework/ctx_driver/releases)，已发布版本以 [RubyGems](https://rubygems.org/gems/ctx_driver) 为准。

## 离线示例

在开发检出目录安装依赖后执行：

```sh
bundle exec ruby examples/offline.rb
```

示例使用合成数据，不访问网络。完整代码见 [examples/offline.rb](examples/offline.rb)：

```ruby
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
```

## 公开契约与限制

`Reader.new(session:, clock:).read(command)` 返回 `Capture`。通过 `success?`、`skipped?`、`failure`、`evidence` 检查结果；正文仅显式通过 `body` 读取，`to_h`、`as_json`、`inspect` 不包含正文。`Reader`、借用会话适配器 `Session` 及其回执的 `inspect`/`PP` 不展开调用方对象，也不查询连接状态；回执的字符串插值同样安全。原始输出与解码正文仍可通过回执的显式 API 访问。

自定义会话实现 `connected?` 和 `send_commands([command])`。回执提供 `output`、布尔 `success?`、数组 `steps`、成功正文 `value!` 及失败时的 `error`。成功读取必须只有一个完成步骤。失败回执最多包含一个完成步骤。输出、状态或步骤数量非法时，即使连接仍在线也会跳过后续查询；回执有效后的本地解码或时钟失败不改变会话同步状态。

net-connector 仍为可选依赖，使用适配器的宿主需自行声明 `gem "net-connector", ">= 0.13.0"`。`examples/connector.rb` 通过本地 PTY 子进程验证已安装连接器，不连接网络设备。

单个 reader 顺序使用；跨设备并发分别创建 reader。连接、关闭、凭据和批准命令选择由宿主负责，Reader 不判断任意命令是否只读。普通执行/回执异常转为安全诊断，取消信号继续传播。执行或响应处理被中断后，当前 Reader 记录 `command_aborted`，后续查询跳过；不会凭 `connected?` 仍为 true 就复用同步状态未知的会话，也不会替宿主关闭连接。

时钟必须可调用且返回 Time，可变时间在取得时保存副本，已冻结的 Time 直接复用。正文和来源摘要在观察时钟及会话状态回调之前固定，避免回调复用缓冲区后混入另一条响应。`Capture` 校验字段与状态：成功必须有字符串正文（允许空串），失败没有正文，跳过必须有失败原因且没有执行证据。墙上时钟可能回拨，时间字段不用于推断单调耗时。

详细厂商语义、历史验证记录和 Motor 专用集成说明保留在[架构参考](docs/architecture-zh.md)。其中宿主集成代码需要 Motor，不属于独立 gem API。适配层位于 [Motor 仓库](https://github.com/gatework/motor/tree/main/backend/lib) 的 `backend/lib/baseline`、`backend/lib/vxlan` 和 `backend/lib/wireless`。

net-connector **0.13.0 及以上版本**的原生 `Net::Connector::Base` 会话通过 `execute_operation` 自动适配，不连接、不提权。只去除已匹配的提示符和首行命令回显；连接器因拒绝命令而关闭时，后续读取跳过，不自动重连。自定义会话仍可实现 `send_commands` 协议。

## 领域术语

命令回执属于一次执行，`Capture` 保留处理后的正文和安全证据元数据。命令失败与会话失败具有不同生命周期：独立命令失败后会话仍可能可用，`Reader#failure` 则保留阻止后续查询的首个原因。`Capture#success?` 表示执行结果，不表示解析完整性或设备健康。

## 开发与测试

共享类按实际职责命名，平台信息放在命名空间中。直接对应设备命令的解析器保留文件名和类名。

```sh
bundle install
bundle exec rake
bundle exec ruby examples/offline.rb
bundle exec rake build
```

`bundle exec rake` 执行 RSpec、RuboCop 及离线示例。测试放在 `spec/`，沿用项目 RSpec 约定；样例采用合成或脱敏证据。新增会话适配时补充成功、拒绝、断链、取消、非法回执及证据保留回归。离线测试不代表所有设备版本均通过实机验证。

`bundle exec ruby -Ilib benchmark/body.rb` 测量正文解码，`bundle exec ruby -Ilib benchmark/reader.rb` 每轮测量 10,000 次顺序采集；两者均输出合成回显下的耗时与对象分配，并校验内容。比较版本时保持 Ruby、输入和主机一致，不据此推断设备网络吞吐。

使用声明的最低 Ruby 版本检查兼容性。方法用途统一使用简明中文注释；复杂实现还需说明业务规则、实现思路及关键分支。保持公开返回值与错误契约。真实回显和凭据不可进入示例、fixture、日志或发布包。

## 发布

本目录可独立维护为 [ctx_driver](https://github.com/gatework/ctx_driver) 仓库。更新 `VERSION` 和 `CHANGELOG.md`，运行上述验证与构建命令，检查包内文件，再创建 `vVERSION` 标签。

CI 在 Linux、macOS 上执行测试、lint、示例、构建和隔离安装。`main` 的 CI 通过后推送 `vVERSION` 标签，工作流将已验证的 Linux 产物发布到 RubyGems 和 GitHub Release，附带 `SHA256SUMS` 并回读下载字节。GitHub `release` environment 可配置 `RUBYGEMS_API_KEY` secret；未配置时使用 RubyGems Trusted Publishing，绑定本仓库、`release.yml` 和 `release` environment。失败时重跑失败的发布 job，以复用原 CI 产物；同版本已存在时必须校验字节一致。详见[发布说明](docs/release.md)。

先发布依赖模块。标签、构建成功或工作流文件都不等于已经发布，需单独确认 RubyGems 的实际结果。版本变化见 [CHANGELOG.md](CHANGELOG.md)。

## 许可证

MIT，见 [LICENSE](LICENSE)。
