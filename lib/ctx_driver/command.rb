# frozen_string_literal: true

module CtxDriver
  # 单条命令的值边界；只校验文本完整性，是否为只读查询由宿主决定。
  module Command
    # 校验并固定命令；已有冻结文本可以安全共享。
    def self.snapshot(value)
      unless value.is_a?(String) && !value.strip.empty? && !/[\x00-\x1f\x7f]/.match?(value)
        raise ArgumentError, "One command without control characters is required"
      end

      value.frozen? ? value : value.dup.freeze
    end
  end
  private_constant :Command
end
