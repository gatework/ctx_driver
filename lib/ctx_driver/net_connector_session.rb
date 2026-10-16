# frozen_string_literal: true

module CtxDriver
  # 适配已加载的 net-connector；不连接、不提权，也不恢复已关闭的借用会话。
  class NetConnectorSession
    # 先交出原始回执，Reader 建立证据后才按需解码正文。
    Response = Data.define(:result) do
      def output = result.output
      def steps = result.steps
      def success? = result.success?
      def error = result.error

      # 只移除匹配的首行命令回显；保留正文缩进及后续相同行。
      def value!
        result.value!
        step = result.steps.fetch(0)
        body = Net::Connector::TerminalText.render(step.output.delete_suffix(step.prompt.to_s))
        first = body.lines.first
        first && first.strip == step.command.text ? body.delete_prefix(first) : body
      end
    end
    private_constant :Response

    # 保存调用方拥有的连接器；该可选适配器不主动加载 net-connector。
    def initialize(session)
      @session = session
    end

    # 复用连接器的真实状态，避免失败后隐式重连。
    def connected? = @session.connected?

    # 单命令操作保护响应正文，并绑定当前完整提示符。
    def send_commands(commands)
      raise ArgumentError, "Expected one query" unless commands.one?

      prompt = Net::Connector::TerminalText.render(@session.current_prompt.to_s).strip
      raise ArgumentError, "Session prompt is unavailable" if prompt.empty?

      pattern = /(?:\A|(?<=[\r\n]))[ \t\x00]*#{Regexp.escape(prompt)}[ \t\x00]*[\r\n]*\z/
      command = Net::Connector::Command.new(commands.first, prompt: pattern, output_sensitive: true)
      result = @session.execute_operation(Net::Connector::Script.new([ command ]), name: :ctx_driver, privilege: false)
      Response.new(result)
    end
  end
end
