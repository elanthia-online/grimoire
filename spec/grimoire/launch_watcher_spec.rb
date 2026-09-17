require 'spec_helper'
require 'json'
require 'tmpdir'

RSpec.describe Grimoire::LaunchWatcher do
  around do |example|
    Dir.mktmpdir do |dir|
      @session_dir = dir
      example.run
    end
  end

  let(:started_at) { Time.now }
  let(:now) { [500.0] }
  let(:exit_status) { nil }
  let(:launched) do
    instance_double(
      Grimoire::LaunchedLich,
      character: 'Sparrow', started_at: started_at, running?: exit_status.nil?, exit_status: exit_status,
      log_path: '/logs/lich-Sparrow.log', output_tail: "login failed\n"
    )
  end

  def watcher(timeout: 30)
    described_class.new(launched, session_dir: @session_dir, timeout: timeout, clock: -> { now.first })
  end

  def write_session(port, mtime: Time.now, name: 'Sparrow')
    path = File.join(@session_dir, "#{name}.session")
    File.write(path, { 'name' => name.downcase, 'host' => '127.0.0.1', 'port' => port }.to_json)
    File.utime(mtime, mtime, path)
  end

  it 'waits while there is no session file' do
    expect(watcher.check.state).to eq(:waiting)
  end

  it 'is ready once this launch writes a session file, with its host and port' do
    write_session(41_234)

    result = watcher.check

    expect(result.state).to eq(:ready)
    expect([result.host, result.port]).to eq(['127.0.0.1', 41_234])
  end

  it 'ignores a session file left behind before the launch' do
    write_session(41_234, mtime: started_at - 60)

    expect(watcher.check.state).to eq(:waiting)
  end

  it 'allows for coarse file timestamps just before the launch' do
    write_session(41_234, mtime: started_at - 1)

    expect(watcher.check.state).to eq(:ready)
  end

  it 'keeps waiting through a session file caught mid-write' do
    File.write(File.join(@session_dir, 'Sparrow.session'), '{"host":"127.0')

    expect(watcher.check.state).to eq(:waiting)
  end

  it 'ignores another character\'s session file' do
    write_session(41_234, name: 'Wren')

    expect(watcher.check.state).to eq(:waiting)
  end

  it 'times out once the deadline passes, saying Lich is still running' do
    checker = watcher(timeout: 30)
    now[0] += 30

    result = checker.check

    expect(result.state).to eq(:timed_out)
    expect(result.detail).to include('No session file after 30 seconds', 'still running')
  end

  it 'times out even when a fresh session file exists, so a refused connection cannot retry forever' do
    checker = watcher(timeout: 30)
    write_session(41_234)
    now[0] += 30

    expect(checker.check.state).to eq(:timed_out)
  end

  context 'when Lich has exited' do
    let(:exit_status) { instance_double(Process::Status, exitstatus: 1, termsig: nil) }

    it 'reports the exit with Lich\'s own last output' do
      result = watcher.check

      expect(result.state).to eq(:exited)
      expect(result.detail).to include('exited with status 1', 'login failed', '/logs/lich-Sparrow.log')
    end

    it 'reports the exit even if a session file was written' do
      write_session(41_234)

      expect(watcher.check.state).to eq(:exited)
    end
  end

  context 'when Lich was killed by a signal' do
    let(:exit_status) { instance_double(Process::Status, exitstatus: nil, termsig: 15) }

    it 'names the signal' do
      expect(watcher.check.detail).to include('on signal 15')
    end
  end
end
