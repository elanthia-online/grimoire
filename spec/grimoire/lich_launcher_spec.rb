require 'spec_helper'
require 'fileutils'
require 'tmpdir'

RSpec.describe Grimoire::LichLauncher do
  # Stands in for lich.rbw: reports what it was started with, then behaves
  # according to the character name it was asked to log in, so each
  # example can pick an outcome without environment variables (which the
  # launcher deliberately does not pass through unchanged).
  def fake_lich_source
    <<~'RUBY'
      $stdout.sync = true
      puts "argv=#{ARGV.join(' ')}"
      puts "cwd=#{Dir.pwd}"
      puts "bundle_gemfile=#{ENV['BUNDLE_GEMFILE'].inspect}"
      puts "rubyopt=#{ENV['RUBYOPT'].inspect}"
      puts "stdin=#{$stdin.read.inspect}"
      warn 'written to stderr'
      exit 3 if ARGV.include?('Crasher')
      sleep 30 if ARGV.include?('Sleeper')
    RUBY
  end

  around do |example|
    Dir.mktmpdir do |dir|
      @lich_dir = File.join(dir, 'lich-5')
      @log_dir  = File.join(dir, 'logs')
      FileUtils.mkdir_p(File.join(@lich_dir, 'data'))
      File.write(File.join(@lich_dir, 'lich.rbw'), fake_lich_source)
      File.write(File.join(@lich_dir, 'data', 'entry.yaml'), "accounts: {}\n")
      example.run
    ensure
      @launcher&.launched&.each do |process|
        process.stop
        process.wait(5)
      end
    end
  end

  let(:install) { Grimoire::LichInstall.new(@lich_dir) }
  let(:clock) { class_double(Time, now: Time.new(2026, 9, 16, 12, 34, 56)) }

  def entry(char_name, game_code = 'GS3')
    Grimoire::LichInstall::Entry.new(
      user_id: 'ALPHA', char_name: char_name, game_code: game_code, game_name: nil, favorite: true, favorite_order: nil
    )
  end

  def launcher
    @launcher = described_class.new(install: install, log_dir: @log_dir, clock: clock)
  end

  describe '#command' do
    it 'runs lich.rbw with the current Ruby, logging in headless on a port Lich picks' do
      expect(launcher.command(entry('Zephyr'))).to eq(
        [RbConfig.ruby, File.join(@lich_dir, 'lich.rbw'), '--login', 'Zephyr', '--headless', 'auto', '--gemstone']
      )
    end

    {
      'GS3' => %w[--gemstone],
      'GST' => %w[--gemstone --test],
      'GSF' => %w[--gemstone --shattered],
      'DR'  => %w[--dragonrealms],
      'DRX' => %w[--dragonrealms --platinum],
      'DRT' => %w[--dragonrealms --test],
      'DRF' => %w[--dragonrealms --fallen],
    }.each do |code, flags|
      it "passes #{flags.join(' ')} for #{code}" do
        expect(launcher.command(entry('Zephyr', code)).last(flags.size)).to eq(flags)
      end
    end

    it 'accepts a lowercase game code' do
      expect(launcher.command(entry('Zephyr', 'gsf')).last(2)).to eq(%w[--gemstone --shattered])
    end

    it 'refuses a closed game by name' do
      expect { launcher.command(entry('Zephyr', 'GSX')) }
        .to raise_error(described_class::Error, /Zephyr: GemStone IV Platinum \(GSX\) has closed/)
    end

    it 'refuses a game code Lich cannot log in to' do
      expect { launcher.command(entry('Zephyr', 'XYZ')) }
        .to raise_error(described_class::Error, /cannot log in to game code "XYZ"/)
    end
  end

  describe '#launch' do
    it 'starts Lich in its own directory and records it' do
      process = launcher.launch(entry('Zephyr'))
      expect(process.wait(10)).to be_success

      output = File.read(process.log_path)
      expect(output).to include('argv=--login Zephyr --headless auto --gemstone')
      expect(output).to include("cwd=#{File.realpath(@lich_dir)}")
      expect(process.character).to eq('Zephyr')
      expect(@launcher.launched).to eq([process])
    end

    it 'captures stdout and stderr in one log named after the character' do
      process = launcher.launch(entry('Zephyr'))
      process.wait(10)

      expect(process.log_path).to eq(File.join(@log_dir, 'lich-Zephyr-20260916-123456.log'))
      expect(File.read(process.log_path)).to include('stdin=""', 'written to stderr')
    end

    it 'sanitizes the character name in the log file name' do
      process = launcher.launch(entry('../Ze/phyr'))
      process.wait(10)

      expect(File.dirname(process.log_path)).to eq(@log_dir)
      expect(File.basename(process.log_path)).to eq('lich-Zephyr-20260916-123456.log')
    end

    # rspec itself runs under `bundle exec` here, so these variables are set
    # in this process; Lich must not inherit grimoire's bundle.
    it 'does not pass Bundler variables on to Lich' do
      process = launcher.launch(entry('Zephyr'))
      process.wait(10)

      output = File.read(process.log_path)
      expect(output).to include('bundle_gemfile=nil')
      expect(output).not_to match(%r{rubyopt=.*bundler/setup})
    end

    it 'detects a failed exit and reports it through on_exit' do
      exited = Queue.new
      process = launcher.launch(entry('Crasher'), on_exit: ->(launched) { exited << launched })

      expect(exited.pop(timeout: 10)).to be(process)
      expect(process).not_to be_running
      expect(process.exit_status.exitstatus).to eq(3)
      expect(process.output_tail).to include('written to stderr')
    end

    it 'stops a running Lich' do
      process = launcher.launch(entry('Sleeper'))
      expect(process).to be_running

      expect(process.stop).to be(true)
      expect(process.wait(10)).not_to be_nil
      expect(process).not_to be_running
      expect(process.stop).to be(false)
    end

    it 'starts Lich in its own process group' do
      skip 'process groups are POSIX-only' if Gem.win_platform?

      process = launcher.launch(entry('Sleeper'))

      expect(Process.getpgid(process.pid)).to eq(process.pid)
    end

    it 'refuses to launch from an unusable install, starting nothing' do
      FileUtils.rm(install.lich_rbw_path)

      expect { launcher.launch(entry('Zephyr')) }.to raise_error(described_class::Error, /lich\.rbw: not found/)
      expect(@launcher.launched).to be_empty
    end

    it 'refuses a closed game before creating a log' do
      expect { launcher.launch(entry('Zephyr', 'GSX')) }.to raise_error(described_class::Error, /has closed/)
      expect(Dir.exist?(@log_dir)).to be(false)
    end

    it 'raises Error when the Ruby interpreter cannot be started' do
      @launcher = described_class.new(install: install, log_dir: @log_dir, ruby: File.join(@lich_dir, 'no-such-ruby'))

      expect { @launcher.launch(entry('Zephyr')) }.to raise_error(described_class::Error, /could not start/)
      expect(@launcher.launched).to be_empty
    end
  end
end
