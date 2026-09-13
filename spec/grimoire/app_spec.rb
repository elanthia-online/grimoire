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
