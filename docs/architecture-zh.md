> 本文保留模块从 Motor 提取前的领域设计、覆盖范围、限制与验证记录，供兼容迁移和故障分析使用。
> 当前独立 gem 的安装、依赖、开发与发布入口以 [README-zh.md](../README-zh.md) 为准。
> 涉及 `Motor::*`、`Sync`、`Baseline::Check`、数据库、Rails、Rake 运维任务及私有实机证据的内容均属于 Motor 宿主集成，不随 gem 提供；历史验证记录不代表当前用户设备已经验证。

# 独立命令采集边界

`CtxDriver` 是 `ctx_checker`、`vxlan` 和 `wireless` 共用的纯 Ruby 执行组件。
它借用已打开的会话，一次执行一条已声明查询，不连接、关闭、重试或选择设备命令。
领域 Collector 继续负责准备步骤、命令分组、发现依赖、解析与 Observation 状态。

```ruby
require "ctx_driver"

reader = CtxDriver::Reader.new(session: session)
capture = reader.read("show interfaces")
if capture.success?
  # 正文仅显式用于解析；to_h / as_json / inspect 不包含正文。
  result = parser.parse(capture.body, complete: true)
else
  capture.failure # { code:, stage:, error_type: (有异常时) }
  capture.skipped?
end
capture.evidence # command / sha256 / bytes / observed_at
```

会话协议为 `connected?` 和 `send_commands([command])`。返回值须提供 `output`、布尔 `success?`、数组 `steps`；
成功必须只有一个步骤，`value!` 必须返回正文字符串，失败通过 `error` 提供原因。
`output` 用于原始来源摘要，`value!` 是连接器处理后的正文，两者不要求相等。
自定义协议由宿主清理正文；原生 `Net::Connector::Base` 由可选适配器绑定当前完整提示符，并在证据摘要生成后去除命令回显及提示符。适配器不主动加载 net-connector，不连接、不提权。调用方只传目录中已批准的查询。

只有会话方法显式声明 `preserve_session_on_rejection:` 时，才传 `true`。
原生 net-connector 关闭拒绝命令后的会话时，Reader 保留该关闭状态；自定义适配器只有确认会话仍可用，才允许下一条独立命令。
断线或状态未知时记忆首个原因，后续命令返回 skipped，不自动重连或重放。
`reader.failure` 可供不提交命令的分支检查会话状态。

响应处理异常保留此前取得的 SHA256、字节数与时间。没有回执时不伪造摘要。
`Capture` 的正文与元数据分别复制、冻结；正常序列化不包含正文、异常对象、消息或凭据。
字段 `started_at/completed_at` 为采集阶段时间；证据的 `observed_at` 为实际收到响应的时间。
命令失败与领域健康状态分开，Reader 不产生 pass/fail 或完整库存判断。

`StandardError` 在单命令执行、响应验证和状态查询边界转换为安全诊断；取消信号继续抛出。
解析异常由领域 Collector 在本条命令或本次 AP 子任务内隔离。
调用方须顺序使用同一个 Reader；跨设备并发各自建立 Reader。

运行依赖由 gemspec 声明；会话所有权与命令来源响应时间契约保持不变。没有环境变量、数据库表或调度入口。
