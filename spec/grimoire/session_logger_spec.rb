require 'spec_helper'
require 'tmpdir'

RSpec.describe Grimoire::SessionLogger do
  let(:clock) do
    Class.new do
      def self.now
        Time.new(2026, 9, 13, 10, 30, 0)
      end
    end
  end

  around do |example|
    Dir.mktmpdir { |dir| @tmp_dir = dir; example.run }
  end

  def new_logger(port: 8300, **overrides)
    described_class.new(dir: @tmp_dir, port: port, clock: clock, **overrides)
  end

  it 'creates a raw and parsed log file named with the port and a timestamp when no character is known' do
    new_logger

    expect(File).to exist(File.join(@tmp_dir, 'session-8300-20260913-103000-raw.log'))
    expect(File).to exist(File.join(@tmp_dir, 'session-8300-20260913-103000-parsed.log'))
  end

  describe 'naming by character' do
    # Ports are assigned by whichever Lich happened to bind first and say
    # nothing about who a log belongs to, so once several sessions can
    # share one process the character name is what makes the log files
    # readable -- see TASKS.md's "Multi-session shell" item 2.
    it 'names the pair with the character instead of the port when one is known' do
      new_logger(character: 'Sparrow')

      expect(File).to exist(File.join(@tmp_dir, 'session-Sparrow-20260913-103000-raw.log'))
      expect(File).to exist(File.join(@tmp_dir, 'session-Sparrow-20260913-103000-parsed.log'))
    end

    # Matches how SessionLocator already normalizes a name into lich-5's
    # own session-file name, so one character never produces two sets of
    # log files that differ only in case.
    it 'normalizes character name case the same way SessionLocator does' do
      new_logger(character: 'sPaRrOw')

      expect(File).to exist(File.join(@tmp_dir, 'session-Sparrow-20260913-103000-raw.log'))
    end

    it 'keeps two characters at the same timestamp from clobbering each other' do
      first  = new_logger(character: 'Sparrow')
      second = new_logger(character: 'Wren')
      first.raw('first character')
      second.raw('second character')
      first.close
      second.close

      expect(File.read(File.join(@tmp_dir, 'session-Sparrow-20260913-103000-raw.log'))).to eq('first character')
      expect(File.read(File.join(@tmp_dir, 'session-Wren-20260913-103000-raw.log'))).to eq('second character')
    end
  end

  describe 'character names that are not safe as filenames' do
    # --character NAME is arbitrary user input on its way into a file path.
    it 'strips path separators and traversal sequences rather than trusting them' do
      logger = new_logger(character: '../../etc/passwd')
      logger.close

      expect(Dir.children(@tmp_dir)).to contain_exactly(
        'session-Etcpasswd-20260913-103000-raw.log',
        'session-Etcpasswd-20260913-103000-parsed.log'
      )
    end

    it 'writes nothing outside the log directory even for an absolute-path name' do
      logger = new_logger(character: '/tmp/grimoire-escape')
      logger.close

      expect(Dir.children(@tmp_dir).all? { |name| name.start_with?('session-') }).to be(true)
      expect(File).not_to exist('/tmp/grimoire-escape')
    end

    it 'falls back to the port when nothing usable survives sanitizing' do
      new_logger(character: '///')

      expect(File).to exist(File.join(@tmp_dir, 'session-8300-20260913-103000-raw.log'))
    end

    it 'falls back to the port for an empty character name' do
      new_logger(character: '')

      expect(File).to exist(File.join(@tmp_dir, 'session-8300-20260913-103000-raw.log'))
    end
  end

  it 'creates the directory if it does not exist yet' do
    nested = File.join(@tmp_dir, 'nested', 'log')

    described_class.new(dir: nested, port: 8300, clock: clock)

    expect(Dir).to exist(nested)
  end

  it 'writes raw chunks to the raw log, appending across multiple calls' do
    logger = new_logger
    logger.raw("<prompt time=\"1\">&gt;</prompt>\r\n")
    logger.raw("You swing your sword.\r\n")
    logger.close

    expect(File.read(File.join(@tmp_dir, 'session-8300-20260913-103000-raw.log')))
      .to eq("<prompt time=\"1\">&gt;</prompt>\r\nYou swing your sword.\r\n")
  end

  it 'writes parsed narrative text to the parsed log, separately from raw' do
    logger = new_logger
    logger.parsed('You swing your sword.')
    logger.close

    expect(File.read(File.join(@tmp_dir, 'session-8300-20260913-103000-parsed.log'))).to eq('You swing your sword.')
    expect(File.read(File.join(@tmp_dir, 'session-8300-20260913-103000-raw.log'))).to eq('')
  end

  it 'keeps two loggers created at different times from clobbering each other' do
    later_clock = Class.new do
      def self.now
        Time.new(2026, 9, 13, 10, 31, 0)
      end
    end

    first  = new_logger
    second = described_class.new(dir: @tmp_dir, port: 8300, clock: later_clock)
    first.raw('first session')
    second.raw('second session')
    first.close
    second.close

    expect(File.read(File.join(@tmp_dir, 'session-8300-20260913-103000-raw.log'))).to eq('first session')
    expect(File.read(File.join(@tmp_dir, 'session-8300-20260913-103100-raw.log'))).to eq('second session')
  end

  it 'keeps two loggers for different ports at the same timestamp from clobbering each other' do
    first  = new_logger(port: 8300)
    second = new_logger(port: 8301)
    first.raw('first port')
    second.raw('second port')
    first.close
    second.close

    expect(File.read(File.join(@tmp_dir, 'session-8300-20260913-103000-raw.log'))).to eq('first port')
    expect(File.read(File.join(@tmp_dir, 'session-8301-20260913-103000-raw.log'))).to eq('second port')
  end
end
