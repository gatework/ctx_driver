# frozen_string_literal: true

module CtxDriver
  # 命令诊断保留阶段与安全类型，不携带设备正文、异常消息或凭据。
  module Failure
    ERROR_TYPE = /\A(?:[A-Z][A-Za-z0-9_]*::)*[A-Z][A-Za-z0-9_]*\z/

    # 将异常归纳为安全错误元数据，不暴露异常消息。
    def self.details(error, fallback:, stage:)
      details = { code: code(error, fallback), stage: stage }
      if error
        name = error.class.name
        details[:error_type] = name.is_a?(String) && ERROR_TYPE.match?(name) ? name.dup.freeze : "StandardError"
      end
      details.freeze
    end

    # 识别传输异常，不要求特定连接器实现。
    def self.connection_error?(error, owner)
      (defined?(Net::Connector::Error) && error.is_a?(Net::Connector::Error)) ||
        (owner.class.const_defined?(:Error) && error.is_a?(owner.class.const_get(:Error))) ||
        error.is_a?(IOError)
    end

    # 已加载 net-connector 时复用其稳定诊断词表，否则使用调用方的回退代码。
    def self.code(error, fallback)
      value = error.code if error.respond_to?(:code)
      defined?(Net::Connector::ErrorMetadata) ? Net::Connector::ErrorMetadata.code(value) || fallback : fallback
    rescue StandardError
      fallback
    end
  end
end
