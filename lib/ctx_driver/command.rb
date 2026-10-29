# frozen_string_literal: true

require "ctx_parser/commands"

module CtxDriver
  # 单条命令的值边界；只校验文本完整性，是否为只读查询由宿主决定。
  module Command
    # 校验并固定命令；已有冻结文本可以安全共享。
    def self.snapshot(value) = CtxParser::Commands.command_text(value)
  end
  private_constant :Command
end
