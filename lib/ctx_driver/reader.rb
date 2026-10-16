# frozen_string_literal: true

require "digest"
require "time"
require_relative "capture"
require_relative "failure"
require_relative "net_connector_session"

module CtxDriver
  # 借用已打开会话逐条独立查询；连接归属与领域判断由外部负责。
  class Reader
    # 借用已打开会话，并初始化首个失败的跟踪状态。
    def initialize(session:, clock: -> { Time.now.utc })
      if defined?(Net::Connector::Base) && session.is_a?(Net::Connector::Base)
        session = NetConnectorSession.new(session)
      end
      unless session.respond_to?(:send_commands)
        raise ArgumentError, "Session must implement #send_commands for the command driver protocol"
      end

      @session, @clock = session, clock
      @unavailable = nil
    end

    # 执行一条经过校验的查询，保留独立结果或失败。
    def read(command)
      unless command.is_a?(String) && !command.strip.empty? && !/[\x00-\x1f\x7f]/.match?(command)
        raise ArgumentError, "One command without control characters is required"
      end
      command = command.dup.freeze
      started = @clock.call
      if failure
        return Capture.new(command: command, started_at: started, completed_at: @clock.call,
          failure: @unavailable, skipped: true)
      end

      acquire(command, started)
    end

    # 不发送命令即可检查会话可用性，并保留首次失败原因。
    def failure
      @unavailable ||= session_failure
    end

    private

    # 分离执行与回执校验；后续校验失败时仍保留已取得的证据。
    def acquire(command, started)
      stage, evidence, failure, body = :execute, [], nil, nil
      begin
        result = if preserves_rejection?
          @session.send_commands([ command ], preserve_session_on_rejection: true)
        else
          @session.send_commands([ command ])
        end
        stage = :response
        output = result.output
        raise TypeError, "Command output must be text" unless output.is_a?(String)

        evidence = [ { command: command, sha256: Digest::SHA256.hexdigest(output), bytes: output.bytesize,
          observed_at: @clock.call.getutc.iso8601(6) } ]
        success = result.success?
        unless [ true, false ].include?(success) && result.steps.is_a?(Array) && (!success || result.steps.one?)
          raise TypeError, "One query must return one completed command"
        end
        if success
          body = result.value!
          raise TypeError, "Command body must be text" unless body.is_a?(String)
        else
          failure = Failure.details(result.error, fallback: :command_failed, stage: :execute)
        end
      rescue StandardError => error
        fallback = stage == :execute ? :command_execution_failed : :invalid_command_result
        failure = Failure.details(error, fallback: fallback, stage: stage)
      end
      state_failure = session_failure
      # 单命令失败但会话仍可用时继续独立查询；断链或状态不明才阻止后续提交。
      @unavailable = failure || state_failure if state_failure
      Capture.new(command: command, body: failure ? nil : body, started_at: started, completed_at: @clock.call,
        evidence: evidence, failure: failure)
    end

    # 仅在明确支持时复用命令拒绝后的会话；未知提示符仍由连接器关闭处理。
    def preserves_rejection?
      @session.method(:send_commands).parameters.any? do |kind, name|
        %i[key keyreq].include?(kind) && name == :preserve_session_on_rejection
      end
    end

    # 连接状态不确定时视为不可用，后续跳过的查询保留首次失败原因。
    def session_failure
      state = @session.connected?
      raise TypeError, "Connection state must be boolean" unless [ true, false ].include?(state)

      state ? nil : { code: :session_closed, stage: :session }.freeze
    rescue StandardError => error
      Failure.details(error, fallback: :session_state_failed, stage: :session)
    end
  end
end
