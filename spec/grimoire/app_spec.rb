require 'spec_helper'

RSpec.describe Grimoire::App do
  # App#initialize only sets up collaborators (Connection#initialize does
  # not touch the network, CommandQueue#initialize does not start its
  # thread) so it is safe to build here without a real Lich process.
  #
  # Since the per-character stack moved out into Session (see
  # spec/grimoire/session_spec.rb, which covers its behavior against a
  # plain fake view), what is left here is App's own job: wiring one real
  # Window to one Session and passing construction options through. The
  # examples that drive a real Window are kept deliberately as end-to-end
  # coverage that the session actually reaches real widgets, not just a
  # test double.
  def pump_idle
    context = GLib::MainContext.default
    context.iteration(false) while context.pending?
  end

  def scrollback_text(app)
    app.instance_variable_get(:@window).instance_variable_get(:@buffer).text
  end

  def health_bar(app)
    window = app.instance_variable_get(:@window)
    window.instance_variable_get(:@command_vital_bars)[:health]
  end

  def roundtime_bar_text(app)
    window = app.instance_variable_get(:@window)
    window.instance_variable_get(:@roundtime_label).text
  end

  describe 'wiring the window to the session' do
    # The window's on_command callback is built before the session exists
    # (the session needs the window as its view), so it closes over
    # @session rather than referencing it directly -- this pins down that
    # the deferred reference actually resolves when a command is submitted.
    it 'routes a command submitted in the window through to the session' do
      app = described_class.new(host: '127.0.0.1', port: 0)
      allow(app.session).to receive(:send_command)

      app.instance_variable_get(:@window).instance_variable_get(:@on_command).call('look')

      expect(app.session).to have_received(:send_command).with('look')
    end

    it 'gives the session the real window as its view' do
      app = described_class.new(host: '127.0.0.1', port: 0)

      expect(app.session.instance_variable_get(:@view)).to be(app.instance_variable_get(:@window))
    end
  end

  describe 'end-to-end through a real window' do
    it 'echoes a submitted command into the real scrollback' do
      app = described_class.new(host: '127.0.0.1', port: 0)

      app.session.send_command('look')
      pump_idle

      expect(scrollback_text(app)).to eq("\n> look\n")
    end

    # A bare self-closing <progressBar> line carries no narrative text at
    # all, so this pins down that command_vitals still refreshes even
    # though the scrollback append is skipped for it.
    # show_command_vitals defaults true (2026-09-15), so no theme override
    # is needed here.
    it 'refreshes command_vitals from a line that produces no narrative text' do
      app = described_class.new(host: '127.0.0.1', port: 0)

      app.session.send(:handle_line, "<progressBar id='health' value='87' text='health 310/355'/>\r\n")
      pump_idle

      expect(health_bar(app).fraction).to eq(0.87)
      expect(scrollback_text(app)).to eq('')
    end

    it 'reflects a captured roundTime tag in the roundtime bar as soon as the line arrives' do
      app = described_class.new(host: '127.0.0.1', port: 0)
      future_end = Time.now.to_i + 30

      app.session.send(:handle_line, "<roundTime value='#{future_end}'/>\r\n")
      pump_idle

      expect(roundtime_bar_text(app)).to match(/\ART: \d+\z/)
    end

    # Session#tick is what #run wires to a repeating GLib::Timeout so the
    # countdown keeps moving between lines, not just when new traffic
    # arrives -- #run itself is not exercised here since it blocks on
    # Gtk.main, same as the rest of this file staying below that layer.
    it 'refreshes vitals (and any live roundtime countdown) on each tick' do
      app    = described_class.new(host: '127.0.0.1', port: 0)
      window = app.instance_variable_get(:@window)
      allow(window).to receive(:update_vitals)

      app.session.tick

      expect(window).to have_received(:update_vitals).with(app.session.narrative.vitals_state)
    end
  end

  describe 'construction options passed through to the session' do
    it 'passes the character name through' do
      app = described_class.new(host: '127.0.0.1', port: 0, character: 'Sparrow')

      expect(app.session.character).to eq('Sparrow')
    end

    it 'passes a custom prompt character through' do
      app = described_class.new(host: '127.0.0.1', port: 0, prompt_char: '$')

      app.session.send_command('look')
      pump_idle

      expect(scrollback_text(app)).to eq("\n$ look\n")
    end

    # Pinned explicitly because the `grimoire` executable's own --log-dir
    # default previously hardcoded 'log' and always passed it through, so
    # this default silently went untested and unnoticed until it drifted
    # out of sync with .gitignore's /logs/ entry.
    it 'defaults --autolog output to the logs/ directory' do
      logger = instance_double(Grimoire::SessionLogger, raw: nil, parsed: nil, close: nil)
      expect(Grimoire::SessionLogger).to receive(:new).with(dir: 'logs', port: 0, character: nil).and_return(logger)

      described_class.new(host: '127.0.0.1', port: 0, autolog: true)
    end

    it 'passes a custom log directory through' do
      logger = instance_double(Grimoire::SessionLogger, raw: nil, parsed: nil, close: nil)
      expect(Grimoire::SessionLogger).to receive(:new).with(dir: 'elsewhere', port: 0, character: nil).and_return(logger)

      described_class.new(host: '127.0.0.1', port: 0, autolog: true, log_dir: 'elsewhere')
    end
  end
end
