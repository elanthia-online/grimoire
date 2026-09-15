require 'spec_helper'

RSpec.describe Grimoire::App do
  # App#initialize only sets up collaborators (Connection#initialize does
  # not touch the network, CommandQueue#initialize does not start its
  # thread) so it is safe to build here without a real Lich process.
  # handle_command's echo goes through #display, which defers the actual
  # widget write to a GLib idle callback -- pump_idle runs the main loop
  # just enough to flush it, same as TASKS.md's manual GLib-pumped
  # confirmation of the GTK wiring.
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

  it 'echoes a submitted command to the window using the default prompt character' do
    app = described_class.new(host: '127.0.0.1', port: 0)

    app.send(:handle_command, 'look')
    pump_idle

    expect(scrollback_text(app)).to eq("\n> look\n")
  end

  it 'echoes using a custom prompt character when given one' do
    app = described_class.new(host: '127.0.0.1', port: 0, prompt_char: '$')

    app.send(:handle_command, 'look')
    pump_idle

    expect(scrollback_text(app)).to eq("\n$ look\n")
  end

  # Regression: display (handle_command's echo path) used to update only
  # the window, never the session logger -- since Lich never echoes a
  # submitted command back over the wire (see the comment on
  # #handle_command), a real captured session showed the command's
  # *response* in the parsed log with no record of the command that
  # caused it. Caught 2026-09-15 by diffing a real captured
  # session-*-parsed.log against the same session's raw.log.
  it 'writes the command echo into the parsed session log as well as the window' do
    logger = instance_double(Grimoire::SessionLogger, raw: nil, parsed: nil, close: nil)
    allow(Grimoire::SessionLogger).to receive(:new).and_return(logger)
    app = described_class.new(host: '127.0.0.1', port: 0, autolog: true)

    app.send(:handle_command, 'group')

    expect(logger).to have_received(:parsed).with("\n> group\n")
  end

  it 'still forwards the command to the command queue after echoing it' do
    app   = described_class.new(host: '127.0.0.1', port: 0)
    queue = app.instance_variable_get(:@command_queue)
    allow(queue).to receive(:enqueue)

    app.send(:handle_command, 'look')

    expect(queue).to have_received(:enqueue).with('look')
  end

  # handle_prompt's auto-sent `look` (see docs/decisions.md and the
  # "Auto-send `look` on first prompt" item in TASKS.md) goes through the
  # same handle_command path as a user-typed one, so it is echoed too --
  # pinned down here deliberately, as an examined choice rather than an
  # unnoticed side effect of sharing that path.
  it 'echoes the auto-sent look on the first prompt notification, same as a typed command' do
    app   = described_class.new(host: '127.0.0.1', port: 0)
    queue = app.instance_variable_get(:@command_queue)
    allow(queue).to receive(:enqueue)

    app.send(:handle_prompt, '1789336233')
    pump_idle

    expect(scrollback_text(app)).to eq("\n> look\n")
    expect(queue).to have_received(:enqueue).with('look')
  end

  it 'only auto-sends (and echoes) look once, even if handle_prompt fires again' do
    app   = described_class.new(host: '127.0.0.1', port: 0)
    queue = app.instance_variable_get(:@command_queue)
    allow(queue).to receive(:enqueue)

    app.send(:handle_prompt, '1789336233')
    app.send(:handle_prompt, '1789336234')

    expect(queue).to have_received(:enqueue).once
  end

  # A bare self-closing <progressBar> line carries no narrative text at
  # all, so this pins down that command_vitals still refreshes even though
  # handle_line's scrollback append is skipped for it (see the comment on
  # App#handle_line). show_command_vitals defaults true (2026-09-15), so
  # no theme override is needed here.
  it 'refreshes command_vitals from a line that produces no narrative text' do
    app = described_class.new(host: '127.0.0.1', port: 0)

    app.send(:handle_line, "<progressBar id='health' value='87' text='health 310/355'/>\r\n")
    pump_idle

    expect(health_bar(app).fraction).to eq(0.87)
    expect(scrollback_text(app)).to eq('')
  end

  # tick_roundtime is what #run wires to a repeating GLib::Timeout so the
  # countdown keeps moving between lines, not just when new traffic
  # arrives -- #run itself is not exercised here since it blocks on
  # Gtk.main, same as the rest of this file staying below that layer.
  it 'refreshes vitals (and any live roundtime countdown) on each tick' do
    app    = described_class.new(host: '127.0.0.1', port: 0)
    window = app.instance_variable_get(:@window)
    allow(window).to receive(:update_vitals)

    app.send(:tick_roundtime)

    expect(window).to have_received(:update_vitals).with(app.instance_variable_get(:@narrative).vitals_state)
  end

  it 'reflects a captured roundTime tag in the roundtime bar as soon as the line arrives' do
    app = described_class.new(host: '127.0.0.1', port: 0)
    future_end = Time.now.to_i + 30

    app.send(:handle_line, "<roundTime value='#{future_end}'/>\r\n")
    pump_idle

    expect(roundtime_bar_text(app)).to match(/\ART: \d+\z/)
  end

  # Pinned explicitly because the `grimoire` executable's own --log-dir
  # default previously hardcoded 'log' and always passed it through, so
  # App's default silently went untested and unnoticed until it drifted
  # out of sync with .gitignore's /logs/ entry.
  it 'defaults --autolog output to the logs/ directory' do
    logger = instance_double(Grimoire::SessionLogger, raw: nil, parsed: nil, close: nil)
    expect(Grimoire::SessionLogger).to receive(:new).with(dir: 'logs', port: 0).and_return(logger)

    described_class.new(host: '127.0.0.1', port: 0, autolog: true)
  end
end
