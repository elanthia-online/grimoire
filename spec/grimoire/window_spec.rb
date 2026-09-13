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

  def vital_bar(window, field)
    window.instance_variable_get(:@vital_bars)[field]
  end

  def stance_bar(window)
    window.instance_variable_get(:@stance_bar)
  end

  def indicator_text(window)
    window.instance_variable_get(:@indicator_label).text
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

  describe '#update_vitals' do
    let(:vitals_state) { Grimoire::VitalsState.new }

    it 'leaves every bar at its unlabeled default when nothing has been set yet' do
      window.update_vitals(vitals_state)

      expect(vital_bar(window, :health).fraction).to eq(0.0)
      expect(vital_bar(window, :health).text).to eq('Health')
      expect(stance_bar(window).fraction).to eq(0.0)
      expect(indicator_text(window)).to eq('')
    end

    it 'sets a vital bar fraction and text from a percent/text pair' do
      vitals_state.health = Grimoire::VitalsState::Vital.new(percent: 98, text: 'health 351/355')

      window.update_vitals(vitals_state)

      expect(vital_bar(window, :health).fraction).to eq(0.98)
      expect(vital_bar(window, :health).text).to eq('health 351/355')
    end

    it 'sets the stance bar from a bare percent, with a synthesized label' do
      vitals_state.stance = 80

      window.update_vitals(vitals_state)

      expect(stance_bar(window).fraction).to eq(0.8)
      expect(stance_bar(window).text).to eq('Stance 80%')
    end

    it 'clamps an out-of-range percent instead of over/underflowing the bar fraction' do
      vitals_state.health = Grimoire::VitalsState::Vital.new(percent: 150, text: 'health 999/355')

      window.update_vitals(vitals_state)

      expect(vital_bar(window, :health).fraction).to eq(1.0)
    end

    it 'lists only currently-visible indicators, with the Icon prefix stripped' do
      vitals_state.set_indicator('IconBLEEDING', false)
      vitals_state.set_indicator('IconSTANDING', true)
      vitals_state.set_indicator('IconKNEELING', true)

      window.update_vitals(vitals_state)

      expect(indicator_text(window)).to eq('STANDING KNEELING')
    end
  end

  describe 'vitals strip colorization' do
    it 'tags each vital bar with its own vital-<field> CSS class' do
      Grimoire::Window::VITAL_LABELS.each_key do |field|
        expect(vital_bar(window, field).style_context.has_class?("vital-#{field}")).to be(true)
      end
    end

    it 'tags the stance bar with its own CSS class' do
      expect(stance_bar(window).style_context.has_class?('vital-stance')).to be(true)
    end
  end
end
