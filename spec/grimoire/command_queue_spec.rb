require 'spec_helper'

RSpec.describe Grimoire::CommandQueue do
  it 'rewrites and forwards commands to the connection in order' do
    sent       = Queue.new
    connection = instance_double(Grimoire::Connection)
    allow(connection).to receive(:send_line) { |line| sent << line }

    queue = described_class.new(connection: connection, rate: 1000)
    queue.start

    queue.enqueue('.foo')
    queue.enqueue('bar')

    expect(sent.pop).to eq(';foo')
    expect(sent.pop).to eq('bar')

    queue.stop
  end

  it 'stops delivering commands once stopped' do
    sent       = Queue.new
    connection = instance_double(Grimoire::Connection)
    allow(connection).to receive(:send_line) { |line| sent << line }

    queue = described_class.new(connection: connection, rate: 1000)
    queue.start
    queue.stop

    queue.enqueue('look')

    expect(sent.pop(timeout: 0.2)).to be_nil
  end

  it 'reports a failed send without stopping the queue' do
    sent       = Queue.new
    errors     = Queue.new
    connection = instance_double(Grimoire::Connection)
    call_count = 0
    allow(connection).to receive(:send_line) do |line|
      call_count += 1
      raise 'boom' if call_count == 1

      sent << line
    end

    queue = described_class.new(connection: connection, rate: 1000, on_error: ->(e) { errors << e })
    queue.start

    queue.enqueue('first')
    queue.enqueue('second')

    expect(errors.pop.message).to eq('boom')
    expect(sent.pop).to eq('second')

    queue.stop
  end
end
