require 'spec_helper'

RSpec.describe Grimoire::Window do
  let(:commands) { [] }
  let(:clock) { class_double(Time, now: Time.new(2026, 9, 13, 12, 0, 0)) }
  subject(:window) { described_class.new(on_command: ->(command) { commands << command }, clock: clock) }

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

  def roundtime_bar(window)
    window.instance_variable_get(:@roundtime_bar)
  end

  def roundtime_text(window)
    window.instance_variable_get(:@roundtime_label).text
  end

  def roundtime_color(window)
    style = roundtime_bar(window).style_context
    return :hard if style.has_class?('roundtime-hard')
    return :cast if style.has_class?('roundtime-cast')

    :none
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

    it 'shows RT: 0 with an empty, uncolored bar when neither lock has ever been seen' do
      window.update_vitals(vitals_state)

      expect(roundtime_text(window)).to eq('RT: 0')
      expect(roundtime_bar(window).fraction).to eq(0.0)
      expect(roundtime_color(window)).to eq(:none)
    end

    it 'shows the seconds remaining and health-red while hard roundtime is running' do
      vitals_state.roundtime_end = clock.now.to_i + 3

      window.update_vitals(vitals_state)

      expect(roundtime_text(window)).to eq('RT: 3')
      expect(roundtime_bar(window).fraction).to eq(0.3)
      expect(roundtime_color(window)).to eq(:hard)
    end

    it 'shows the seconds remaining and mana-blue while only cast roundtime is running' do
      vitals_state.cast_roundtime_end = clock.now.to_i + 5

      window.update_vitals(vitals_state)

      expect(roundtime_text(window)).to eq('RT: 5')
      expect(roundtime_bar(window).fraction).to eq(0.5)
      expect(roundtime_color(window)).to eq(:cast)
    end

    it 'falls back to RT: 0 once the running lock has already elapsed' do
      vitals_state.roundtime_end = clock.now.to_i - 1

      window.update_vitals(vitals_state)

      expect(roundtime_text(window)).to eq('RT: 0')
      expect(roundtime_color(window)).to eq(:none)
    end

    it 'caps the fraction at 1.0 (full) for 10 or more seconds remaining' do
      vitals_state.roundtime_end = clock.now.to_i + 30

      window.update_vitals(vitals_state)

      expect(roundtime_text(window)).to eq('RT: 30')
      expect(roundtime_bar(window).fraction).to eq(1.0)
    end

    # The user's own worked example: 3s hard roundtime running alongside a
    # longer 5s cast roundtime displays the greater number (5), colored red
    # for as long as hard roundtime itself is still running.
    it 'displays the greater of hard/cast remaining, colored red while hard roundtime still has any left' do
      vitals_state.roundtime_end = clock.now.to_i + 3
      vitals_state.cast_roundtime_end = clock.now.to_i + 5

      window.update_vitals(vitals_state)

      expect(roundtime_text(window)).to eq('RT: 5')
      expect(roundtime_color(window)).to eq(:hard)
    end

    # Continuing the same example forward in time: once hard roundtime's own
    # 3 seconds have elapsed, the bar switches to blue and keeps counting
    # down cast roundtime's own remaining time (2 of its original 5).
    it 'switches from red to blue once hard roundtime ends while cast roundtime continues' do
      vitals_state.roundtime_end = clock.now.to_i + 3
      vitals_state.cast_roundtime_end = clock.now.to_i + 5
      window.update_vitals(vitals_state)

      allow(clock).to receive(:now).and_return(clock.now + 3)
      window.update_vitals(vitals_state)

      expect(roundtime_text(window)).to eq('RT: 2')
      expect(roundtime_color(window)).to eq(:cast)
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

    it 'tags the roundtime bar with its own base CSS class' do
      expect(roundtime_bar(window).style_context.has_class?('roundtime-bar')).to be(true)
    end
  end

  describe 'theming' do
    it 'tags the scrollback view and command entry with their own CSS classes' do
      expect(window.instance_variable_get(:@view).style_context.has_class?('grimoire-output')).to be(true)
      expect(window.instance_variable_get(:@entry).style_context.has_class?('grimoire-input')).to be(true)
    end

    it 'defaults to a black-background, white-text, Overpass Mono (falling back to monospace) 11pt theme' do
      css = window.send(:main_css)

      expect(css).to include('background-color: rgb(0, 0, 0)')
      expect(css).to include('color: rgb(255, 255, 255)')
      expect(css).to include('font-family: Overpass Mono, monospace')
      expect(css).to include('font-size: 11pt')
    end

    # GtkTextView's Pango layout resolves its font from the widget's own
    # ("textview") CSS node via gtk_widget_get_pango_context, NOT from its
    # "text" child node -- confirmed live against a real GtkTextView
    # (2026-09-13): a font-family/font-size rule on "text" alone changes
    # nothing about the rendered glyphs, only "text"'s own colors apply.
    # A regression back to a font rule on "text" alone would leave every
    # config.yml font override silently doing nothing, exactly as reported
    # live, so this locks the outer-node rule in specifically.
    it 'sets font-family/font-size on the outer textview node, not just its text child' do
      css = window.send(:main_css)
      outer_rule = css[/textview\.grimoire-output\s*\{[^}]*\}/]

      expect(outer_rule).not_to be_nil
      expect(outer_rule).to include('font-family: Overpass Mono, monospace')
      expect(outer_rule).to include('font-size: 11pt')
    end

    it 'renders a custom theme into the main-window CSS' do
      theme = Grimoire::Theme::DEFAULT.with(
        main_background: Grimoire::Color.new(red: 10, green: 20, blue: 30),
        main_foreground: Grimoire::Color.new(red: 250, green: 240, blue: 230),
        font_family: 'Fira Code',
        font_size: 14
      )
      themed_window = described_class.new(on_command: ->(_command) {}, theme: theme)

      css = themed_window.send(:main_css)

      expect(css).to include('background-color: rgb(10, 20, 30)')
      expect(css).to include('color: rgb(250, 240, 230)')
      expect(css).to include('font-family: Fira Code')
      expect(css).to include('font-size: 14pt')
    end

    it 'passes a CSS font-family fallback list through untouched, rather than quoting the whole value' do
      theme = Grimoire::Theme::DEFAULT.with(font_family: '"Overpass Mono", monospace')
      themed_window = described_class.new(on_command: ->(_command) {}, theme: theme)

      css = themed_window.send(:main_css)

      expect(css).to include('font-family: "Overpass Mono", monospace;')
    end
  end

  describe 'roundtime bar layout' do
    it 'packs the roundtime overlay to the left of the command entry, in the same row' do
      command_row = window.to_gtk.child.children.last
      roundtime_widget = command_row.children.first

      expect(roundtime_widget).to be_a(Gtk::Overlay)
      expect(command_row.children.last).to equal(window.instance_variable_get(:@entry))
    end

    it 'draws the bar and its label as the overlay base/overlay pair' do
      command_row = window.to_gtk.child.children.last
      roundtime_widget = command_row.children.first

      expect(roundtime_widget.child).to equal(roundtime_bar(window))
      expect(roundtime_widget.children).to include(window.instance_variable_get(:@roundtime_label))
    end

    it 'left-justifies and vertically centers the roundtime label' do
      label = window.instance_variable_get(:@roundtime_label)

      expect(label.halign).to eq(:start)
      expect(label.valign).to eq(:center)
    end

    it 'tags the roundtime label with its own bold/white CSS class' do
      label = window.instance_variable_get(:@roundtime_label)

      expect(label.style_context.has_class?('roundtime-text')).to be(true)
    end
  end
end
