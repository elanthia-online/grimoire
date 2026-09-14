require 'spec_helper'
require 'socket'

RSpec.describe Grimoire::Connection do
  def with_server
    server = TCPServer.new('127.0.0.1', 0)
    port   = server.addr[1]
    yield server, port
  ensure
    server.close
  end

  it 'connects successfully to a listening server' do
    with_server do |server, port|
      connection = described_class.new(host: '127.0.0.1', port: port, on_line: ->(_line) {})
      connection.connect
      expect(connection).to be_connected
      server.accept
      connection.close
    end
  end

  it 'raises ConnectError when nothing is listening' do
    server = TCPServer.new('127.0.0.1', 0)
    port   = server.addr[1]
    server.close

    connection = described_class.new(host: '127.0.0.1', port: port, on_line: ->(_line) {})
    expect { connection.connect }.to raise_error(Grimoire::Connection::ConnectError)
  end

  it 'delivers incoming lines to on_line' do
    with_server do |server, port|
      received   = Queue.new
      connection = described_class.new(host: '127.0.0.1', port: port, on_line: ->(line) { received << line })
      connection.connect
      accepted = server.accept
      connection.start_reading

      accepted.puts('hello')
      expect(received.pop).to eq("hello\n")

      accepted.close
      connection.close
    end
  end

  it 'reports :eof when the remote end closes the connection cleanly' do
    with_server do |server, port|
      disconnects = Queue.new
      connection  = described_class.new(
        host: '127.0.0.1',
        port: port,
        on_line: ->(_line) {},
        on_disconnect: ->(reason, *) { disconnects << reason }
      )
      connection.connect
      accepted = server.accept
      connection.start_reading

      accepted.close
      expect(disconnects.pop).to eq(:eof)

      connection.close
    end
  end

  it 'sends lines to the server' do
    with_server do |server, port|
      connection = described_class.new(host: '127.0.0.1', port: port, on_line: ->(_line) {})
      connection.connect
      accepted = server.accept

      connection.send_line('look')
      expect(accepted.gets).to eq("look\n")

      accepted.close
      connection.close
    end
  end

  it 'sends the SET_FRONTEND_PID identify line' do
    with_server do |server, port|
      connection = described_class.new(host: '127.0.0.1', port: port, on_line: ->(_line) {})
      connection.connect
      accepted = server.accept

      connection.identify(pid: 12_345)
      expect(accepted.gets).to eq("SET_FRONTEND_PID 12345\n")

      accepted.close
      connection.close
    end
  end

  it 'defaults the identify line to the current process pid' do
    with_server do |server, port|
      connection = described_class.new(host: '127.0.0.1', port: port, on_line: ->(_line) {})
      connection.connect
      accepted = server.accept

      connection.identify
      expect(accepted.gets).to eq("SET_FRONTEND_PID #{Process.pid}\n")

      accepted.close
      connection.close
    end
  end

  it 'reports :error instead of dying silently when on_line raises' do
    with_server do |server, port|
      disconnects = Queue.new
      connection  = described_class.new(
        host: '127.0.0.1',
        port: port,
        on_line: ->(_line) { raise 'boom' },
        on_disconnect: ->(reason, error = nil) { disconnects << [reason, error] }
      )
      connection.connect
      accepted = server.accept
      connection.start_reading

      accepted.puts('hello')
      reason, error = disconnects.pop
      expect(reason).to eq(:error)
      expect(error.message).to eq('boom')

      accepted.close
      connection.close
    end
  end

  it 'does nothing when sending without a connection' do
    connection = described_class.new(host: '127.0.0.1', port: 1, on_line: ->(_line) {})
    expect { connection.send_line('look') }.not_to raise_error
  end

  it 'does nothing when closing without ever connecting' do
    connection = described_class.new(host: '127.0.0.1', port: 1, on_line: ->(_line) {})
    expect { connection.close }.not_to raise_error
  end

  it 'is safe to close twice' do
    with_server do |server, port|
      connection = described_class.new(host: '127.0.0.1', port: port, on_line: ->(_line) {})
      connection.connect
      server.accept

      connection.close
      expect { connection.close }.not_to raise_error
    end
  end
end
