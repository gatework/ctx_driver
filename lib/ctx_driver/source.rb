# frozen_string_literal: true

require "ctx_parser/immutable"
require "ctx_parser/values"
require_relative "command"

module CtxDriver
  # 来源身份与摘要是值；领域附加信息放入 context，不混入驱动字段。
  class Source < Data.define(:command, :sha256, :bytes, :reference, :observed_at, :status, :context)
    def self.coerce(value)
      return value if value.is_a?(self)
      raise ArgumentError, "Source must be a mapping" unless value.is_a?(Hash)
      attributes = value.each_with_object({}) do |(key, entry), result|
        unless (key.is_a?(String) || key.is_a?(Symbol)) && members.include?(key.to_sym) && !result.key?(key.to_sym)
          raise ArgumentError, "Source contains unknown or duplicate fields"
        end
        result[key.to_sym] = entry
      end
      raise ArgumentError, "Invalid source status" if attributes.key?(:status) && attributes[:status].nil?
      attributes[:status] = attributes[:status].to_sym if value.key?("status") && attributes[:status].is_a?(String)
      new(**attributes)
    end

    def initialize(command: nil, sha256: nil, bytes: nil, reference: nil, observed_at: nil, status: nil, context: {})
      command = Command.snapshot(command) unless command.nil?
      unless sha256.nil? && bytes.nil? || sha256.is_a?(String) && /\A[0-9a-f]{64}\z/.match?(sha256) && bytes.is_a?(Integer) && bytes >= 0
        raise ArgumentError, "Source requires a digest and nonnegative byte count together"
      end
      unless reference.nil? || reference.is_a?(String) && !reference.strip.empty? && !/[\x00-\x1f\x7f]/.match?(reference)
        raise ArgumentError, "Invalid source reference"
      end
      raise ArgumentError, "Source requires an identity or digest" unless command || reference || sha256
      unless status.nil? || %i[complete partial failed unsupported].include?(status)
        raise ArgumentError, "Invalid source status"
      end
      raise ArgumentError, "Source context must be a mapping" unless context.is_a?(Hash)
      observed_at = CtxParser::Values.timestamp(observed_at) if observed_at.is_a?(String)
      raise ArgumentError, "Source time must be a Time or nil" unless observed_at.nil? || observed_at.is_a?(Time)
      attributes = { command: command, sha256: sha256&.dup&.freeze, bytes: bytes, reference: reference&.dup&.freeze,
        observed_at: observed_at&.getutc&.freeze, status: status, context: CtxParser::Immutable.copy(context) }
      metadata = attributes.compact
      metadata.delete(:context) if context.empty?
      metadata[:observed_at] = attributes[:observed_at].iso8601(6).freeze if observed_at
      @metadata = metadata.freeze
      super(**attributes)
    end

    def verified? = !sha256.nil? && !bytes.nil?
    def to_h = @metadata.dup

    # 元数据映射访问沿用同一字段协议；所有更新重新经过构造校验。
    def [](key) = @metadata[key]
    def fetch(...) = @metadata.fetch(...)
    def key?(key) = @metadata.key?(key)
    def keys = @metadata.keys
    def merge(**attributes) = with(**attributes)
    def inspect = "#<#{self.class.name} verified=#{verified?}>"
    alias to_s inspect
    def pretty_print(printer) = printer.text(inspect)
  end
end
