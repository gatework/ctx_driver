# ctx_driver 开发指南

本文件适用于本仓库。用户指令优先；更深目录的 AGENTS.md 可细化局部约定。

## 职责与结构

这是借用会话的顺序命令采集层，依赖 ctx_parser 的快照能力。它不拥有连接生命周期、不选择健康策略、不解释厂商业务事实。

- `lib/ctx_driver/command.rb`：单命令校验及文本快照。
- `reader.rb`：顺序执行、回执校验、摘要、时钟及首次会话失败跟踪。
- `capture.rb`：不可变正文、时间、证据和失败元数据。
- `session.rb`：可选 net-connector 原生会话适配；不主动 require 连接器。
- `failure.rb`：安全诊断词表及连接错误识别。
- `examples/connector.rb`、`spec/session_spec.rb`：本地 PTY 的原生适配验证。

## 必须保持的契约

- Reader 借用实现 `send_commands` 和 `connected?` 的会话；只发送经过校验的单条命令，不隐式连接、重连、提权或关闭它。
- 一次查询只对应一条命令。成功回执恰好一个已完成步骤；失败可无已完成步骤，不能混入其他命令的步骤。
- 独立命令失败且会话可用时允许后续查询；断链、取消或同步状态未知时保留首个失败并跳过后续命令，不重放。
- Interrupt、线程终止等不能被 StandardError rescue 吞掉；未完成回执后的同步状态应视为未知。
- 原始 output 的 SHA256/bytes 与解码 body 分开。正文解码失败也保留已取得的来源摘要。
- 在时钟或其他外部回调前保存正文与证据；时钟必须返回 Time。复制可变 Time，允许复用冻结值。
- 原生适配只移除匹配的首行命令回显和已确认的末尾提示符，保留正文缩进、重复命令行及空正文。
- Capture 成功必须有正文，失败不能有正文，skipped 必须有失败且无执行证据。不要把空字符串误判为失败。
- inspect/to_s/pretty_print 不遍历借用会话、时钟或原始回执；诊断不携带异常消息、凭据和设备正文。原始正文仅通过显式接口访问。

## 开发约定

- 使用 `.ruby-version`、gemspec 和锁文件规定的运行时与依赖；当前 Ruby 最低版本和 CI 版本为 4.0.6。修改版本策略时同步检查这三处及 CI。
- 遵循 `.rubocop.yml`：两空格缩进、snake_case 方法和文件、UpperCamelCase 类型、`frozen_string_literal`。代码注释沿用中文，RSpec 示例及 Changelog 沿用英文。
- 厂商 CLI 命令解析器的文件名、类名及目录应继续镜像原命令；必要修复不受限制。命名清理优先针对语义不清的适配器和辅助对象。
- 先查调用者和既有同类实现。抽象应保护业务不变量或隔离协议，不因文件长度或方法数量机械拆分。
- 区分缺失、nil、false、非法和未知。异常只在负责的边界处理；不能用空集合、零值或成功状态掩盖失败。
- 不依赖 Ruby 全局分隔符 `$;`、`$/`、`$,`；拆分、逐行读取和拼接须指定分隔符。处理配置时保留来源原文及换行。
- 在外部回调前固定已校验输入和证据。不要冻结调用方的可变对象；`Data.define` 和外层 `freeze` 不等于成员深度不可变。
- 保留暂存、未暂存和未跟踪改动；不覆盖无关工作，不执行 reset/clean/stash。审查与本地修复本身不代表获得提交、推送或发布授权。

## 验证与交付

在本仓库根目录执行：

```sh
ruby -v
bundle exec rake
bundle exec rake build
```

`rake` 默认包含 RSpec、RuboCop 和全部 examples；examples 使用本地合成数据，不需连接设备。若非交互 shell 误用 macOS 系统 Ruby 2.6，在当前环境使用 `zsh -ic 'bundle exec rake'`；不要为此降级锁文件或修改依赖。

- 缺陷先用最小回归复现，再修复；优先复用已有测试。测试断言实际输出、错误隔离和副作用，不镜像内部实现。
- 性能改动使用 `benchmark/` 中的脚本，记录输入规模、Ruby 版本、代码来源、耗时和分配量；比较前后语义。合成结果不能证明网络吞吐或实机兼容性。
- 公共行为变化记录在 `CHANGELOG.md` 的 Unreleased。当前代码、README 和验证脚本是依据；`docs/architecture-zh.md` 含历史 Motor 宿主记录，不能当成当前 gem 的运行能力。
- 跨仓库联调与锁定依赖测试分别运行并报告。`RUBYLIB` 联调通过不证明已发布依赖兼容；使用 `script/verify_package.rb` 在隔离安装中验证候选包。
- 只有明确要求发布时才执行交付流程，顺序为 ctx_parser → ctx_driver → ctx_checker；核对精确提交的 CI、制品、校验和及安装读回结果。仓库可见性仅按当前授权调整。

独立安装验证：`ruby script/verify_package.rb pkg/ctx_driver-*.gem`；脚本可接收显式依赖候选包，并在独立 GEM_HOME 中验证安装。修改原生适配时运行完整 rake 中的 PTY 测试。基准入口：`bundle exec ruby -Ilib benchmark/reader.rb`、`benchmark/body.rb`。

联调当前相邻 parser 源码：

```sh
RUBYLIB=../ctx_parser/lib bundle exec rake
```

同时保留不带 RUBYLIB 的锁定依赖验证。
