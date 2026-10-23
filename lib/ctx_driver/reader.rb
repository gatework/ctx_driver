# frozen_string_literal: true

require "digest"
require "time"
require_relative "capture"
require_relative "failure"
require_relative "session"

module CtxDriver
  # 借用已打开会话逐条独立查询；连接归属与领域判断由外部负责。
  class Reader
    # 借用已打开会话，并初始化首个失败的跟踪状态。
    def initialize(session:, clock: -> { Time.now.utc })
      if defined?(Net::Connector::Base) && session.is_a?(Net::Connector::Base)
        session = Session.new(session)
      end
      unless session.respond_to?(:send_commands)
        raise ArgumentError, "Session must implement #send_commands for the command driver protocol"
      end
      raise ArgumentError, "Session must implement #connected?" unless session.respond_to?(:connected?)
      raise ArgumentError, "Clock must be callable" unless clock.respond_to?(:call)

      @session, @clock = session, clock
      @session_failure = nil
    end

    # 执行一条经过校验的查询，保留独立结果或失败。
    def read(command)
      command = Command.snapshot(command)
      started_at = current_time
      if failure
        return Capture.new(command: command, started_at: started_at, completed_at: current_time,
          failure: @session_failure, skipped: true)
      end

      capture_command(command, started_at)
    end

    # 不发送命令即可检查会话可用性，并保留首次失败原因。
    def failure
      @session_failure ||= detect_session_failure
    end

    # 仅显示边界类型，避免遍历借用会话、时钟或触发外部状态查询。
    def inspect = "#<#{self.class.name}>"

    private

    # 立即保存时钟快照，避免后续用户回调改变已记录的时区或时间。
    def current_time
      time = @clock.call
      raise TypeError, "Clock must return a Time" unless time.is_a?(Time)

      time.frozen? ? time : time.dup.freeze
    end

    # 分离执行与回执校验；后续校验失败时仍保留已取得的证据。
    def capture_command(command, started_at)
      stage, evidence, command_failure, body = :execute, [], nil, nil
      capture_completed = false
      receipt_validated = false
      begin
        receipt = @session.send_commands([ command ])
        stage = :response
        output = receipt.output
        raise TypeError, "Command output must be text" unless output.is_a?(String)

        evidence = [ { command: command, sha256: Digest::SHA256.hexdigest(output), bytes: output.bytesize } ]
        success = receipt.success?
        steps = receipt.steps
        unless [ true, false ].include?(success) && steps.is_a?(Array) && (success ? steps.one? : steps.size <= 1)
          raise TypeError, "One query must return one completed command"
        end
        receipt_validated = true
        if success
          body = receipt.value!
          raise TypeError, "Command body must be text" unless body.is_a?(String)

          body = body.dup.freeze unless body.frozen?
        else
          command_failure = Failure.details(receipt.error, fallback: :command_failed, stage: :execute)
        end
      rescue StandardError => error
        fallback = stage == :execute ? :command_execution_failed : :invalid_command_result
        command_failure = Failure.details(error, fallback: fallback, stage: stage)
        # 在线状态不能证明畸形回执对应的单命令边界；不复用未知同步状态。
        @session_failure ||= command_failure if stage == :response && !receipt_validated
      end
      # 外部时钟回调只在正文与摘要固定后调用，不能复用本条响应缓冲区。
      begin
        unless evidence.empty?
          observed_at = current_time.getutc.iso8601(6)
          evidence = [ evidence.first.merge(observed_at: observed_at) ]
        end
      rescue StandardError => error
        evidence = []
        command_failure ||= Failure.details(error, fallback: :invalid_command_result, stage: :response)
      end
      state_failure = detect_session_failure
      # 单命令失败但会话仍可用时继续独立查询；断链或状态不明才阻止后续提交。
      @session_failure = command_failure || state_failure if state_failure
      capture = Capture.new(command: command, body: command_failure ? nil : body, started_at: started_at, completed_at: current_time,
        evidence: evidence, failure: command_failure)
      capture_completed = true
      capture
    ensure
      # Interrupt 与 Thread.kill 不经过 StandardError；未完成回执时禁止继续使用未知同步状态。
      @session_failure ||= command_failure || { code: :command_aborted, stage: stage || :execute }.freeze unless capture_completed
    end

    # 连接状态不确定时视为不可用，后续跳过的查询保留首次失败原因。
    def detect_session_failure
      state = @session.connected?
      raise TypeError, "Connection state must be boolean" unless [ true, false ].include?(state)

      state ? nil : { code: :session_closed, stage: :session }.freeze
    rescue StandardError => error
      Failure.details(error, fallback: :session_state_failed, stage: :session)
    end
  end
end
