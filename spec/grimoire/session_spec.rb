require 'spec_helper'
require 'tmpdir'

RSpec.describe Grimoire::Session do
  # Session#initialize only sets up collaborators (Connection#initialize
  # does not touch the network, CommandQueue#initialize does not start its
  # thread) so it is safe to build here without a real Lich process.
  # #send_command's echo goes through #display, which defers the actual
  # view write to a GLib idle callback -- pump_idle runs the main loop just
  # enough to flush it, same as TASKS.md's manual GLib-pumped confirmation
  # of the GTK wiring.
  def pump_idle
    context = GLib::MainContext.default
    context.iteration(false) while context.pending?
  end

  # Stands in for Window, which is the real implementation of the contract
  # Session writes through (#append_text/#update_vitals). Using a plain
  # recorder here rather than a real Window is the point of the session
  # extraction: nothing below the view boundary needs GTK widgets to be
  # exercised. See the "only calls methods Window actually defines" example
  # below for the guard that keeps this fake honest.
  def fake_view
    Class.new do
      attr_reader :appended, :vitals_updates

      def initialize
        @appended       = +''
        @vitals_updates = []
      end

      def append_text(text)
        @appended << text
      end

      def update_vitals(vitals_state)
        @vitals_updates << vitals_state
      end
    end.new
  end

  def build_session(view: fake_view, **overrides)
    described_class.new(host: '127.0.0.1', port: 0, view: view, **overrides)
  end

  describe 'character name' do
    # The name is what item 2 of TASKS.md's "Multi-session shell" phase
    # keys session logs off, and what a tab is eventually labelled with --
    # App only ever received host/port before this extraction, with the
    # name living in the grimoire executable's --character flag.
    it 'carries the character name it was built with' do
      expect(build_session(character: 'Sparrow').character).to eq('Sparrow')
    end

    it 'leaves the character name nil when pointed at a raw host/port' do
      expect(build_session.character).to be_nil
    end
  end

  describe '#send_command' do
    it 'echoes a submitted command to the view using the default prompt character' do
      view = fake_view
      session = build_session(view: view)

      session.send_command('look')
      pump_idle

      expect(view.appended).to eq("\n> look\n")
    end

    it 'echoes using a custom prompt character when given one' do
      view = fake_view
      session = build_session(view: view, prompt_char: '$')

      session.send_command('look')
      pump_idle

      expect(view.appended).to eq("\n$ look\n")
    end

    it 'still forwards the command to the command queue after echoing it' do
      session = build_session
      queue   = session.instance_variable_get(:@command_queue)
      allow(queue).to receive(:enqueue)

      session.send_command('look')

      expect(queue).to have_received(:enqueue).with('look')
    end

    # Regression: #display (#send_command's echo path) used to update only
    # the view, never the session logger -- since Lich never echoes a
    # submitted command back over the wire (see the comment on
    # #send_command), a real captured session showed the command's
    # *response* in the parsed log with no record of the command that
    # caused it. Caught 2026-09-15 by diffing a real captured
    # session-*-parsed.log against the same session's raw.log.
    it 'writes the command echo into the parsed session log as well as the view' do
      logger = instance_double(Grimoire::SessionLogger, raw: nil, parsed: nil, close: nil)
      allow(Grimoire::SessionLogger).to receive(:new).and_return(logger)
      session = build_session(autolog: true)

      session.send_command('group')

      expect(logger).to have_received(:parsed).with("\n> group\n")
    end
  end

  describe 'auto-sent look on the first prompt' do
    # The auto-sent `look` (see docs/decisions.md and the "Auto-send `look`
    # on first prompt" item in TASKS.md) goes through the same
    # #send_command path as a user-typed one, so it is echoed too -- pinned
    # down here deliberately, as an examined choice rather than an
    # unnoticed side effect of sharing that path.
    it 'echoes the auto-sent look on the first prompt notification, same as a typed command' do
      view    = fake_view
      session = build_session(view: view)
      queue   = session.instance_variable_get(:@command_queue)
      allow(queue).to receive(:enqueue)

      session.send(:handle_prompt, '1789336233')
      pump_idle

      expect(view.appended).to eq("\n> look\n")
      expect(queue).to have_received(:enqueue).with('look')
    end

    it 'only auto-sends (and echoes) look once, even if handle_prompt fires again' do
      session = build_session
      queue   = session.instance_variable_get(:@command_queue)
      allow(queue).to receive(:enqueue)

      session.send(:handle_prompt, '1789336233')
      session.send(:handle_prompt, '1789336234')

      expect(queue).to have_received(:enqueue).once
    end
  end

  describe 'incoming lines' do
    # A bare self-closing <progressBar> line carries no narrative text at
    # all, so this pins down that the vitals refresh still fires even
    # though the scrollback append is skipped for it (see the comment on
    # #handle_line).
    it 'refreshes vitals from a line that produces no narrative text' do
      view    = fake_view
      session = build_session(view: view)

      session.send(:handle_line, "<progressBar id='health' value='87' text='health 310/355'/>\r\n")
      pump_idle

      expect(view.vitals_updates.last.health.percent).to eq(87)
      expect(view.appended).to eq('')
    end

    it 'appends narrative text and refreshes vitals for a line that carries both' do
      view    = fake_view
      session = build_session(view: view)

      session.send(:handle_line, "You see nothing unusual.\r\n")
      pump_idle

      expect(view.appended).to include('You see nothing unusual.')
      expect(view.vitals_updates).not_to be_empty
    end

    it 'routes a captured roundTime tag into vitals state as soon as the line arrives' do
      view       = fake_view
      session    = build_session(view: view)
      future_end = Time.now.to_i + 30

      session.send(:handle_line, "<roundTime value='#{future_end}'/>\r\n")
      pump_idle

      expect(view.vitals_updates.last.roundtime_end).to eq(future_end)
    end
  end

  describe '#tick' do
    # #tick is what App wires to a repeating GLib::Timeout so the countdown
    # keeps moving between lines, not just when new traffic arrives.
    it 'refreshes the view from the live vitals state' do
      view    = fake_view
      session = build_session(view: view)

      session.tick

      expect(view.vitals_updates).to eq([session.narrative.vitals_state])
    end

    # Pinned because #tick is deliberately the one view write that does not
    # marshal through GLib::Idle.add -- its caller is already on the GTK
    # main thread (a GLib::Timeout callback, not a socket thread).
    it 'writes to the view synchronously, with no idle pump needed' do
      view = fake_view

      build_session(view: view).tick

      expect(view.vitals_updates).not_to be_empty
    end
  end

  describe 'disconnect' do
    it 'reports the reason to the view and closes the session log' do
      logger = instance_double(Grimoire::SessionLogger, raw: nil, parsed: nil, close: nil)
      allow(Grimoire::SessionLogger).to receive(:new).and_return(logger)
      view    = fake_view
      session = build_session(view: view, autolog: true)

      session.send(:handle_disconnect, :eof)
      pump_idle

      expect(view.appended).to eq("\n[disconnected: eof]\n")
      expect(logger).to have_received(:close)
    end

    # Regression (found 2026-09-15 while double-checking the extraction,
    # pre-dating it -- the same ordering was in App before the move):
    # #handle_disconnect closed the session log *before* calling #display,
    # whose own `@session_logger&.parsed(text)` then wrote to a closed file
    # and raised IOError. That lost the disconnect notice before it reached
    # the view (the raise happens ahead of the GLib::Idle.add) and
    # propagated into Connection#read_loop's rescue, which called
    # on_disconnect again, raised again inside the rescue, and killed the
    # read thread. Deliberately uses a real SessionLogger writing to a real
    # tmpdir: the instance_double used by the examples above accepts
    # #parsed after #close in any order, which is precisely why this hid.
    it 'still reports the disconnect to the view when a real session log is open' do
      Dir.mktmpdir do |dir|
        view    = fake_view
        session = build_session(view: view, autolog: true, log_dir: dir, character: 'Sparrow')

        expect { session.send(:handle_disconnect, :eof) }.not_to raise_error
        pump_idle

        expect(view.appended).to eq("\n[disconnected: eof]\n")
        parsed = Dir.glob(File.join(dir, '*parsed.log')).first
        expect(File.read(parsed)).to include('[disconnected: eof]')
      end
    end

    it 'includes the error message when the disconnect carried one' do
      view    = fake_view
      session = build_session(view: view)

      session.send(:handle_disconnect, :error, StandardError.new('connection reset'))
      pump_idle

      expect(view.appended).to eq("\n[disconnected: error - connection reset]\n")
    end
  end

  describe 'session logging' do
    it 'defaults --autolog output to the logs/ directory' do
      logger = instance_double(Grimoire::SessionLogger, raw: nil, parsed: nil, close: nil)
      expect(Grimoire::SessionLogger).to receive(:new).with(dir: 'logs', port: 0, character: nil).and_return(logger)

      build_session(autolog: true)
    end

    # Item 2 of TASKS.md's "Multi-session shell" phase -- the session's own
    # character name is what its log files are named after, so several
    # sessions sharing one process produce readable logs instead of ones
    # told apart only by whichever port Lich happened to bind.
    it 'hands the session character name to the logger' do
      logger = instance_double(Grimoire::SessionLogger, raw: nil, parsed: nil, close: nil)
      expect(Grimoire::SessionLogger).to receive(:new)
        .with(dir: 'logs', port: 0, character: 'Sparrow').and_return(logger)

      build_session(autolog: true, character: 'Sparrow')
    end

    it 'builds no logger at all unless autolog was asked for' do
      expect(Grimoire::SessionLogger).not_to receive(:new)

      build_session
    end
  end

  # Guards the fake view above from drifting away from the real view
  # contract: a verifying double fails if Session ever calls something
  # Window does not actually define. Matters most for TASKS.md's item 3,
  # which changes Window from a top-level window into an embeddable widget.
  it 'only calls methods Window actually defines' do
    view = instance_double(Grimoire::SessionView, append_text: nil, update_vitals: nil)
    session = build_session(view: view)

    session.send_command('look')
    session.send(:handle_line, "<progressBar id='health' value='87' text='health 310/355'/>\r\n")
    session.tick
    pump_idle

    expect(view).to have_received(:update_vitals).at_least(:once)
  end
end
