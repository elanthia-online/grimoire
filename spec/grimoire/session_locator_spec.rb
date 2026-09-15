require 'spec_helper'
require 'tmpdir'

RSpec.describe Grimoire::SessionLocator do
  around do |example|
    Dir.mktmpdir do |dir|
      @session_dir = dir
      example.run
    end
  end

  def write_session(name, contents)
    File.write(File.join(@session_dir, "#{name}.session"), contents)
  end

  def locator(character, **opts)
    described_class.new(character, session_dir: @session_dir, retries: 0, **opts)
  end

  it 'locates a valid session file, matching lich-5s downcase.capitalize naming' do
    write_session('Nexushealbot', '{"name":"nexushealbot","host":"127.0.0.1","port":8100}')

    result = locator('nexushealbot').locate

    expect(result).to eq(host: '127.0.0.1', port: 8100)
  end

  it 'raises NotFound when no session file exists' do
    expect { locator('nexushealbot').locate }.to raise_error(described_class::NotFound, /no session file for 'nexushealbot'/)
  end

  it 'retries the given number of times before raising NotFound' do
    attempts = 0
    allow(File).to receive(:file?).and_wrap_original do |original, path|
      attempts += 1
      original.call(path)
    end

    expect { locator('nexushealbot', retries: 3, retry_interval: 0).locate }.to raise_error(described_class::NotFound)
    expect(attempts).to eq(4)
  end

  it 'raises InvalidSession on malformed JSON' do
    write_session('Nexushealbot', 'not json')

    expect { locator('nexushealbot').locate }.to raise_error(described_class::InvalidSession, /malformed session file/)
  end

  it 'raises InvalidSession when a required field is missing' do
    write_session('Nexushealbot', '{"name":"nexushealbot","host":"127.0.0.1"}')

    expect { locator('nexushealbot').locate }.to raise_error(described_class::InvalidSession, /missing field\(s\) port/)
  end

  it 'raises InvalidSession when port is not a valid integer' do
    write_session('Nexushealbot', '{"name":"nexushealbot","host":"127.0.0.1","port":"eight thousand"}')

    expect { locator('nexushealbot').locate }.to raise_error(described_class::InvalidSession, /port must be an integer/)
  end

  it 'raises InvalidSession when port is out of range' do
    write_session('Nexushealbot', '{"name":"nexushealbot","host":"127.0.0.1","port":70000}')

    expect { locator('nexushealbot').locate }.to raise_error(described_class::InvalidSession, /port must be an integer/)
  end

  it 'raises InvalidSession when host is empty' do
    write_session('Nexushealbot', '{"name":"nexushealbot","host":"","port":8100}')

    expect { locator('nexushealbot').locate }.to raise_error(described_class::InvalidSession, /host must be a non-empty string/)
  end

  describe '.list' do
    it 'returns an empty array when the session directory has no session files' do
      expect(described_class.list(session_dir: @session_dir)).to eq([])
    end

    it 'lists valid sessions, keyed by filename rather than the JSON body' do
      write_session('Nexushealbot', '{"name":"nexushealbot","host":"127.0.0.1","port":8100}')

      sessions = described_class.list(session_dir: @session_dir)

      expect(sessions).to contain_exactly(
        have_attributes(character: 'Nexushealbot', host: '127.0.0.1', port: 8100, error: nil, valid?: true)
      )
    end

    it 'reports a malformed session file instead of skipping it' do
      write_session('Brokenbot', 'not json')

      sessions = described_class.list(session_dir: @session_dir)

      expect(sessions).to contain_exactly(
        have_attributes(character: 'Brokenbot', host: nil, port: nil, valid?: false, error: /malformed session file/)
      )
    end

    it 'reports a session file missing host/port as invalid' do
      write_session('Halfbot', '{"name":"halfbot"}')

      sessions = described_class.list(session_dir: @session_dir)

      expect(sessions).to contain_exactly(
        have_attributes(character: 'Halfbot', valid?: false, error: 'missing or invalid host/port field')
      )
    end

    it 'sorts multiple sessions by filename' do
      write_session('Zeta', '{"host":"127.0.0.1","port":8100}')
      write_session('Alpha', '{"host":"127.0.0.1","port":8101}')

      sessions = described_class.list(session_dir: @session_dir)

      expect(sessions.map(&:character)).to eq(%w[Alpha Zeta])
    end

    it 'ignores non-.session files in the directory' do
      write_session('Nexushealbot', '{"host":"127.0.0.1","port":8100}')
      File.write(File.join(@session_dir, 'notasession.txt'), 'irrelevant')

      sessions = described_class.list(session_dir: @session_dir)

      expect(sessions.map(&:character)).to eq(['Nexushealbot'])
    end
  end
end
