# frozen_string_literal: true

require_relative "command"

module CtxDriver
  # 适配已加载的 net-connector；不连接、不提权，也不恢复已关闭的借用会话。
  class Session
    # 先交出原始回执，Reader 建立证据后才按需解码正文。
    Response = Data.define(:result) do
      # 不依赖原始回执自身的脱敏实现，默认检查不展开来源结果。
      def inspect = "#<#{self.class.name}>"

      # Data 的默认 to_s 保留原始成员检查实现，日志插值也须脱敏。
      def to_s = inspect

      # Data 的 PP 默认按成员展开，显式限制为安全表示。
      def pretty_print(printer) = printer.text(inspect)

      def output = result.output
      def steps = result.steps
      def success? = result.success?
      def error = result.error

      # 只移除匹配的首行命令回显；保留正文缩进及后续相同行。
      def value!
        # 成功路径无需再次拼接全部输出；失败仍交由连接器保留异常契约。
        result.value! unless result.success?
        step = result.steps.fetch(0)
        body = Net::Connector::Terminal::Text.render(step.output.delete_suffix(step.prompt.to_s))
        first = body.each_line("\n").first
        first && first.strip == step.command.text.strip ? body.delete_prefix(first) : body
      end
    end
    private_constant :Response

    # 保存调用方拥有的连接器；该可选适配器不主动加载 net-connector。
    def initialize(session)
      @session = session
    end

    # 不展开调用方拥有的连接器，也不查询连接状态。
    def inspect = "#<#{self.class.name}>"

    # 复用连接器的真实状态，避免失败后隐式重连。
    def connected? = @session.connected?

    # 单命令操作保护响应正文，并绑定当前完整提示符。
    def send_commands(commands)
      raise ArgumentError, "Expected one query" unless commands.is_a?(Array) && commands.one?

      text = Command.snapshot(commands.first)

      prompt = Net::Connector::Terminal::Text.render(@session.current_prompt.to_s).strip
      raise ArgumentError, "Session prompt is unavailable" if prompt.empty?

      pattern = /(?:\A|(?<=[\r\n]))[ \t\x00]*#{Regexp.escape(prompt)}[ \t\x00]*[\r\n]*\z/
      command = Net::Connector::Command.new(text, prompt: pattern, output_sensitive: true)
      result = @session.execute_operation(Net::Connector::Script.new([ command ]), name: :ctx_driver, privilege: false)
      Response.new(result)
    end
  end
end
