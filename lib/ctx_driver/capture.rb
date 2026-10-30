# frozen_string_literal: true

require "ctx_parser/immutable"
require_relative "command"
require_relative "source"

module CtxDriver
  # 原始正文须显式读取；默认检查与序列化仅展示采集元数据。
  class Capture
    attr_reader :command, :body, :started_at, :completed_at, :evidence, :failure

    # 冻结单条命令回执及其正文、时间、证据和失败元数据。
    def initialize(command:, body: nil, started_at:, completed_at:, evidence: [], failure: nil, skipped: false)
      command = Command.snapshot(command)
      raise ArgumentError, "Capture body must be text or nil" unless body.nil? || body.is_a?(String)
      unless started_at.is_a?(Time) && completed_at.is_a?(Time)
        raise ArgumentError, "Capture timestamps must be Time values"
      end
      unless evidence.is_a?(Array) && evidence.all? { |entry| (entry.is_a?(Hash) || entry.is_a?(Source)) }
        raise ArgumentError, "Capture evidence must be hashes"
      end
      raise ArgumentError, "Capture failure must be a hash or nil" unless failure.nil? || failure.is_a?(Hash)
      raise ArgumentError, "Skipped must be boolean" unless [ true, false ].include?(skipped)
      raise ArgumentError, "Successful captures require a body" if failure.nil? && body.nil?
      raise ArgumentError, "Failed captures cannot contain a body" if failure && !body.nil?
      raise ArgumentError, "Skipped captures require failure without evidence" if skipped && (failure.nil? || evidence.any?)

      @command = command
      @body = body.nil? || body.frozen? ? body : body.dup.freeze
      @started_at = started_at.frozen? ? started_at : started_at.dup.freeze
      @completed_at = completed_at.frozen? ? completed_at : completed_at.dup.freeze
      @evidence = evidence.map { |entry| Source.coerce(entry) }.freeze
      @failure = CtxParser::Immutable.copy(failure)
      @skipped = skipped
      freeze
    end

    # 判断命令是否完成且未捕获失败。
    def success? = failure.nil?
    # 判断是否因会话不可用而抑制了本次执行。
    def skipped? = @skipped

    # 返回公开的数据结构，并保留状态与诊断信息。
    def to_h
      { command: command, started_at: started_at, completed_at: completed_at,
        evidence: evidence.map(&:to_h), failure: failure, skipped: skipped? }
    end

    # 序列化诊断元数据，不包含原始来源文本。
    def as_json(*) = to_h
    # 展示对象身份与状态，避免泄露原始回显或凭据。
    def inspect = "#<#{self.class.name} success=#{success?} skipped=#{skipped?}>"
  end
end
