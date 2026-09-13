require_relative 'command_rewrite'

module Grimoire
  # Paces outgoing commands to respect the server-side rate limit (roughly
  # 3/sec). Applies CommandRewrite to each command before it is queued.
  class CommandQueue
    DEFAULT_RATE = 3.0 # commands per second

    def initialize(connection:, rate: DEFAULT_RATE, on_error: nil)
      @connection = connection
      @interval   = 1.0 / rate
      @queue      = Queue.new
      @thread     = nil
      @on_error   = on_error
    end

    def start
      @thread = Thread.new { run }
    end

    def enqueue(command)
      @queue << CommandRewrite.call(command)
    end

    def stop
      @thread&.kill
    end

    private

    def run
      loop do
        command = @queue.pop
        begin
          @connection.send_line(command)
        rescue StandardError => e
          # A bad send must not kill this thread -- later, unrelated
          # commands still deserve their shot at going out.
          @on_error&.call(e)
        end
        sleep @interval
      end
    end
  end
end
