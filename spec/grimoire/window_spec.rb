require 'spec_helper'

RSpec.describe Grimoire::Window do
  let(:commands) { [] }
  subject(:window) { described_class.new(on_command: ->(command) { commands << command }) }

  def scrollback_text(window)
    window.instance_variable_get(:@buffer).text
  end

  def entry_text(window)
    window.instance_variable_get(:@entry).text
  end

  def type(window, text)
    window.instance_variable_get(:@entry).text = text
  end

  it 'appends text to the scrollback' do
    window.append_text('You are standing in a field.')

    expect(scrollback_text(window)).to eq('You are standing in a field.')
  end

  it 'appends multiple runs in order' do
    window.append_text('first ')
    window.append_text('second')

    expect(scrollback_text(window)).to eq('first second')
  end

  it 'does nothing for an empty append' do
    window.append_text('first')
    window.append_text('')

    expect(scrollback_text(window)).to eq('first')
  end

  it 'submits the entry text as a command and clears the entry' do
    type(window, 'look')
    window.submit_command

    expect(commands).to eq(['look'])
    expect(entry_text(window)).to eq('')
  end

  it 'does not submit an empty command' do
    type(window, '')
    window.submit_command

    expect(commands).to be_empty
  end

  it 'recalls the most recent command on history_up' do
    type(window, 'north')
    window.submit_command
    type(window, 'look')
    window.submit_command

    window.history_up

    expect(entry_text(window)).to eq('look')
  end

  it 'walks further back in history on repeated history_up' do
    type(window, 'north')
    window.submit_command
    type(window, 'look')
    window.submit_command

    window.history_up
    window.history_up

    expect(entry_text(window)).to eq('north')
  end

  it 'does not walk past the oldest command' do
    type(window, 'north')
    window.submit_command

    window.history_up
    window.history_up
    window.history_up

    expect(entry_text(window)).to eq('north')
  end

  it 'walks forward again on history_down, then clears past the newest' do
    type(window, 'north')
    window.submit_command
    type(window, 'look')
    window.submit_command

    window.history_up
    window.history_up
    window.history_down

    expect(entry_text(window)).to eq('look')

    window.history_down

    expect(entry_text(window)).to eq('')
  end

  it 'does nothing on history_down with no active recall' do
    type(window, 'north')
    window.submit_command

    window.history_down

    expect(entry_text(window)).to eq('')
  end

  it 'does nothing on history_up with no history yet' do
    window.history_up

    expect(entry_text(window)).to eq('')
  end
end
