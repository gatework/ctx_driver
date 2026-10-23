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
自定义协议由宿主清理正文；net-connector 0.13.0 及以上版本的原生 `Net::Connector::Base` 由可选适配器绑定当前完整提示符，并在证据摘要生成后去除命令回显及提示符。适配器不主动加载 net-connector，不连接、不提权。调用方只传目录中已批准的查询。

失败回执最多包含一个完成步骤。回执输出、状态或步骤数量非法时，连接在线不能证明同步状态，Reader 保留首个失败并跳过后续查询；回执有效后的本地解码或时钟错误仍按单命令失败隔离。
原生 net-connector 关闭拒绝命令后的会话时，Reader 保留该关闭状态；自定义适配器只有确认会话仍可用，才允许下一条独立命令。
断线或状态未知时记忆首个原因，后续命令返回 skipped，不自动重连或重放。
`reader.failure` 可供不提交命令的分支检查会话状态。

响应处理异常保留此前取得的 SHA256、字节数与时间。没有回执时不伪造摘要。
`Capture` 的正文与元数据分别复制、冻结；正常序列化不包含正文、异常对象、消息或凭据。
字段 `started_at/completed_at` 为采集阶段时间；证据的 `observed_at` 为响应快照固定后的观察时间，不等同于传输层最后一个字节的到达时间。
命令失败与领域健康状态分开，Reader 不产生 pass/fail 或完整库存判断。

`StandardError` 在单命令执行、响应验证和状态查询边界转换为安全诊断；取消信号继续抛出。执行或响应处理未能完成回执时，ensure 保留原有失败或记录 `command_aborted`，包括不进入 rescue 的 Thread.kill。此 Reader 后续只返回 skipped，不关闭借用会话、不重放命令。

开始时间在执行回调之前保存副本，正文和来源摘要在观察时钟及后续状态回调之前固定；已经冻结的字符串和时间允许安全共享。注入时钟必须可调用并返回 Time；时间允许因墙上时钟校准而回拨。`Capture` 拒绝类型错误以及成功/失败/跳过状态与正文或证据矛盾的回执。

原生适配器只读取渲染后正文的首行来判断回显，不构造全部行数组；成功路径不再调用连接器 `value!` 重复拼接输出，失败仍由连接器原样抛出错误。`benchmark/body.rb` 使用合成回显验证内容、耗时和分配量，不提供真实设备网络性能结论。
解析异常由领域 Collector 在本条命令或本次 AP 子任务内隔离。
调用方须顺序使用同一个 Reader；跨设备并发各自建立 Reader。

运行依赖由 gemspec 声明；会话所有权与命令来源响应时间契约保持不变。没有环境变量、数据库表或调度入口。


## 当前执行边界

内部 `Command` 模块统一 Reader、Capture 与原生 Session 的单行命令校验及不可变文本快照，不判断命令是否只读。宿主仍决定批准的查询与会话所有权。

来源摘要先固定，正文提取失败仍保留有效证据；观察时钟在正文快照之后调用。时钟响应无效时返回 response 阶段失败并不发布缺少时间的证据，取消则传播并抑制后续查询。适配器仅在首行和命令去除首尾空白后相等时去除回显，正文缩进和后续同名行保留。

`script/verify_package.rb` 先验证不含 net-connector 的安装和离线示例，再独立安装可选连接器，通过包内本地 PTY 示例验证适配器，避免工作区或旧锁文件掩盖已发布依赖的接口变化。
