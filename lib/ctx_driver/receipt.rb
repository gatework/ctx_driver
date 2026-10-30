# frozen_string_literal: true

module CtxDriver
  # 读取与配置写入共用单命令回执身份，成功恰好对应一个完成步骤。
  module Receipt
    def self.validate(receipt, command:)
      success, steps = receipt.success?, receipt.steps
      unless [ true, false ].include?(success) && steps.is_a?(Array) && (success ? steps.one? : steps.size <= 1)
        raise TypeError, "One query must return one completed command"
      end
      unless steps.all? { |step| step.is_a?(Hash) && step[:command].is_a?(String) && step[:command].b == command.b }
        raise TypeError, "Completed step must belong to the requested command"
      end
      success
    end
  end
end
