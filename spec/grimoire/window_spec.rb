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

  # GtkTextView validates line heights lazily, and a bare
  # `Gtk.main_iteration while Gtk.events_pending?` (see #command_bar_height)
  # can return before that validation's own idle callbacks have even been
  # queued -- confirmed live, a single such pass left the adjustment
  # unchanged after a real append. Repeating it with a short sleep between
  # passes is what actually lets a real GtkScrolledWindow/GtkTextView finish
  # recomputing its extent, the same way the live app's own main loop does
  # between wire lines.
  def pump_gtk_events(iterations: 30)
    iterations.times do
      Gtk.main_iteration while Gtk.events_pending?
      sleep 0.01
    end
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

  describe 'auto-scroll pinning' do
    # A plain Struct stands in for @scroll_adjustment -- GtkScrolledWindow
    # re-derives its live adjustment's own upper/page_size from its child's
    # real layout, silently overwriting anything set directly on it
    # (confirmed live), so pinning exact geometry for these tests needs
    # something GTK is not also driving. #follow_to_bottom_if_pinned and
    # #update_pinned_from are exercised directly -- the same calls the
    # scroller's real 'changed' signal (content growth) and the view/
    # scrollbar's real 'scroll-event'/'change-value' signals (genuine user
    # input) make -- without needing a realized, laid-out widget.
    def stub_adjustment(value:, upper:, page_size:, lower: 0)
      adjustment = Struct.new(:value, :upper, :page_size, :lower).new(value, upper, page_size, lower)
      window.instance_variable_set(:@scroll_adjustment, adjustment)
      adjustment
    end

    describe '#follow_to_bottom_if_pinned' do
      it 'jumps straight to the true bottom while pinned (the default)' do
        adjustment = stub_adjustment(value: 0, upper: 100, page_size: 20)

        window.send(:follow_to_bottom_if_pinned)

        expect(adjustment.value).to eq(80)
      end

      it 'leaves the position alone once the user has scrolled away from the bottom' do
        adjustment = stub_adjustment(value: 30, upper: 100, page_size: 20)
        window.send(:update_pinned_from, 30)

        window.send(:follow_to_bottom_if_pinned)

        expect(adjustment.value).to eq(30)
      end

      it 'clamps at the lower bound rather than going negative for a page taller than the content' do
        adjustment = stub_adjustment(value: 0, upper: 10, page_size: 20, lower: 0)

        window.send(:follow_to_bottom_if_pinned)

        expect(adjustment.value).to eq(0)
      end
    end

    describe '#update_pinned_from' do
      it 'un-pins for a position away from the bottom' do
        stub_adjustment(value: 30, upper: 100, page_size: 20)

        window.send(:update_pinned_from, 30)

        expect(window.instance_variable_get(:@pinned_to_bottom)).to be(false)
      end

      it 'pins for a position within AT_BOTTOM_EPSILON of the true max' do
        stub_adjustment(value: 79.5, upper: 100, page_size: 20)

        window.send(:update_pinned_from, 79.5)

        expect(window.instance_variable_get(:@pinned_to_bottom)).to be(true)
      end

      it 're-pins once a later position lands back at the bottom' do
        stub_adjustment(value: 30, upper: 100, page_size: 20)
        window.send(:update_pinned_from, 30)

        window.send(:update_pinned_from, 80)

        expect(window.instance_variable_get(:@pinned_to_bottom)).to be(true)
      end
    end

    # Regression coverage for the actual bug reported live (2026-09-14):
    # auto-scroll would permanently stop, first reproduced at the exact
    # moment content first overflows the visible page. That happened because
    # an earlier implementation derived @pinned_to_bottom reactively from
    # the adjustment's own 'value-changed' signal, which also fires for
    # Gtk::TextView#scroll_to_mark's own validation-lag glitches -- see the
    # Window class comment for the full history. This exercises the real
    # Gtk::ScrolledWindow/Gtk::TextView pairing end to end (not a stubbed
    # adjustment) so a regression back to that approach would fail here.
    it 'keeps following to the bottom as real content grows past the visible page', :aggregate_failures do
      window.show

      pump_gtk_events

      45.times { |i| window.append_text("line #{i} " * 5 + "\n") }
      pump_gtk_events

      adjustment = window.instance_variable_get(:@scroll_adjustment)
      expect(adjustment.upper).to be > adjustment.page_size
      expect(adjustment.value + adjustment.page_size).to be_within(1.0).of(adjustment.upper)
    ensure
      window.to_gtk.destroy
    end
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

    it 'tags the indicator label with its own CSS class' do
      indicator_label = window.instance_variable_get(:@indicator_label)

      expect(indicator_label.style_context.has_class?('grimoire-indicator-label')).to be(true)
    end

    it 'spaces the vitals-bars/indicator-label gap using the global padding, not a fixed pixel value' do
      strip = window.to_gtk.child.children.first

      expect(strip.spacing).to eq(Grimoire::Theme::DEFAULT.padding)
    end
  end

  describe 'theming' do
    it 'tags the scrollback view and command entry with their own CSS classes' do
      expect(window.instance_variable_get(:@view).style_context.has_class?('grimoire-output')).to be(true)
      expect(window.instance_variable_get(:@entry).style_context.has_class?('grimoire-input')).to be(true)
    end

    it 'defaults to a black-bg, white-fg, Overpass Mono (falling back to monospace) 11pt theme' do
      css = window.send(:game_window_css)

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
      css = window.send(:game_window_css)
      outer_rule = css[/textview\.grimoire-output\s*\{[^}]*\}/]

      expect(outer_rule).not_to be_nil
      expect(outer_rule).to include('font-family: Overpass Mono, monospace')
      expect(outer_rule).to include('font-size: 11pt')
    end

    it 'renders a custom theme into the game-window CSS' do
      theme = Grimoire::Theme::DEFAULT.with(
        game_window_bg: Grimoire::Color.new(red: 10, green: 20, blue: 30),
        game_window_fg: Grimoire::Color.new(red: 250, green: 240, blue: 230),
        font_family: 'Fira Code',
        font_size: 14
      )
      themed_window = described_class.new(on_command: ->(_command) {}, theme: theme)

      css = themed_window.send(:game_window_css)

      expect(css).to include('background-color: rgb(10, 20, 30)')
      expect(css).to include('color: rgb(250, 240, 230)')
      expect(css).to include('font-family: Fira Code')
      expect(css).to include('font-size: 14pt')
    end

    it 'defaults the indicator label to white' do
      expect(window.send(:indicator_css)).to include('color: rgb(255, 255, 255)')
    end

    it 'renders a custom theme into the indicator-label CSS' do
      theme = Grimoire::Theme::DEFAULT.with(indicator_fg: Grimoire::Color.new(red: 200, green: 50, blue: 50))
      themed_window = described_class.new(on_command: ->(_command) {}, theme: theme)

      expect(themed_window.send(:indicator_css)).to include('color: rgb(200, 50, 50)')
    end

    it 'defaults the roundtime label to white' do
      expect(window.send(:roundtime_css)).to include('color: rgb(255, 255, 255)')
    end

    it 'renders a custom theme into the roundtime-label CSS' do
      theme = Grimoire::Theme::DEFAULT.with(roundtime_fg: Grimoire::Color.new(red: 10, green: 200, blue: 10))
      themed_window = described_class.new(on_command: ->(_command) {}, theme: theme)

      expect(themed_window.send(:roundtime_css)).to include('color: rgb(10, 200, 10)')
    end

    it 'passes a CSS font-family fallback list through untouched, rather than quoting the whole value' do
      theme = Grimoire::Theme::DEFAULT.with(font_family: '"Overpass Mono", monospace')
      themed_window = described_class.new(on_command: ->(_command) {}, theme: theme)

      css = themed_window.send(:game_window_css)

      expect(css).to include('font-family: "Overpass Mono", monospace;')
    end

    it 'renders the border color/width into the output/input CSS, defaulting to an invisible 0px border' do
      css = window.send(:game_window_css) + window.send(:command_bar_css)

      expect(css).to include('border-color: rgb(100, 100, 100)')
      expect(css.scan('border-width: 0px').length).to eq(2)
    end

    it 'renders a custom border into the output/input CSS' do
      theme = Grimoire::Theme::DEFAULT.with(
        border_color: Grimoire::Color.new(red: 255, green: 0, blue: 255),
        border_width: 2
      )
      themed_window = described_class.new(on_command: ->(_command) {}, theme: theme)

      css = themed_window.send(:game_window_css) + themed_window.send(:command_bar_css)

      expect(css).to include('border-color: rgb(255, 0, 255)')
      expect(css.scan('border-width: 2px').length).to eq(2)
    end

    it 'renders the global padding as inner content padding for the output/input widgets' do
      css = window.send(:game_window_css) + window.send(:command_bar_css)

      expect(css.scan('padding: 2px').length).to eq(2)
    end

    it 'renders a custom global padding into the output/input CSS' do
      theme = Grimoire::Theme::DEFAULT.with(padding: 10)
      themed_window = described_class.new(on_command: ->(_command) {}, theme: theme)

      css = themed_window.send(:game_window_css) + themed_window.send(:command_bar_css)

      expect(css.scan('padding: 10px').length).to eq(2)
    end

    it 'defaults the command bar to the same black-bg, white-fg, Overpass Mono 11pt theme as the game window' do
      css = window.send(:command_bar_css)

      expect(css).to include('background-color: rgb(0, 0, 0)')
      expect(css).to include('color: rgb(255, 255, 255)')
      expect(css).to include('font-family: Overpass Mono, monospace')
      expect(css).to include('font-size: 11pt')
    end

    it 'renders a custom command bar theme, independent of the game window' do
      theme = Grimoire::Theme::DEFAULT.with(
        command_bar_bg: Grimoire::Color.new(red: 10, green: 20, blue: 30),
        command_bar_fg: Grimoire::Color.new(red: 250, green: 240, blue: 230),
        command_bar_font_family: 'Fira Code',
        command_bar_font_size: 14
      )
      themed_window = described_class.new(on_command: ->(_command) {}, theme: theme)

      css = themed_window.send(:command_bar_css)
      game_window_css = themed_window.send(:game_window_css)

      expect(css).to include('background-color: rgb(10, 20, 30)')
      expect(css).to include('color: rgb(250, 240, 230)')
      expect(css).to include('font-family: Fira Code')
      expect(css).to include('font-size: 14pt')
      expect(game_window_css).to include('background-color: rgb(0, 0, 0)')
      expect(game_window_css).to include('font-family: Overpass Mono, monospace')
    end

    it 'installs a themed Gtk::HeaderBar as the window titlebar' do
      titlebar = window.to_gtk.titlebar

      expect(titlebar).to be_a(Gtk::HeaderBar)
      expect(titlebar.style_context.has_class?('grimoire-titlebar')).to be(true)
    end

    it 'defaults the title bar CSS to a dark charcoal bg, white fg' do
      css = window.send(:title_bar_css)

      expect(css).to include('background-color: rgb(26, 26, 26)')
      expect(css).to include('color: rgb(255, 255, 255)')
    end

    # Adwaita's own headerbar stylesheet carries a subtle inset highlight
    # (box-shadow) plus a bottom border-color for the separator against the
    # rest of the window -- left unreset, both rendered as a stray 1px light
    # line above and below the bar regardless of @theme's own colors,
    # reported live (2026-09-13).
    it 'resets the headerbar box-shadow/border so no stray line shows above/below it' do
      css = window.send(:title_bar_css)

      expect(css).to include('box-shadow: none')
      expect(css).to include('border-style: none')
    end

    it 'renders a custom title bar theme into the title-bar CSS' do
      theme = Grimoire::Theme::DEFAULT.with(
        title_bar_bg: Grimoire::Color.new(red: 30, green: 30, blue: 30),
        title_bar_fg: Grimoire::Color.new(red: 220, green: 220, blue: 220)
      )
      themed_window = described_class.new(on_command: ->(_command) {}, theme: theme)

      css = themed_window.send(:title_bar_css)

      expect(css).to include('background-color: rgb(30, 30, 30)')
      expect(css).to include('color: rgb(220, 220, 220)')
    end

    it 'tags the top-level window with its own CSS class' do
      expect(window.to_gtk.style_context.has_class?('grimoire-window')).to be(true)
    end

    it 'defaults the window (padding_bg) CSS to its own dark charcoal background' do
      css = window.send(:window_css)

      expect(css).to include('background-color: rgb(34, 34, 34)')
    end

    it 'renders a custom padding_bg into the window CSS' do
      theme = Grimoire::Theme::DEFAULT.with(padding_bg: Grimoire::Color.new(red: 40, green: 50, blue: 60))
      themed_window = described_class.new(on_command: ->(_command) {}, theme: theme)

      css = themed_window.send(:window_css)

      expect(css).to include('background-color: rgb(40, 50, 60)')
    end

    it 'renders the vitals border color/width into each vital bar trough, defaulting to invisible' do
      css = window.send(:vital_css, :health, Grimoire::Color.new(red: 200, green: 0, blue: 0))

      expect(css).to include('border-color: rgb(100, 100, 100)')
      expect(css).to include('border-width: 0px')
    end

    it 'insets the vital bar trough/fill by the global padding, shrinking min-height to keep the total height fixed' do
      css = window.send(:vital_css, :health, Grimoire::Color.new(red: 200, green: 0, blue: 0))

      expect(css).to include('padding: 2px')
      expect(css.scan('min-height: 16px').length).to eq(2)
    end

    it 'clamps the vital bar content height at 0 rather than going negative for a large padding' do
      theme = Grimoire::Theme::DEFAULT.with(padding: 20)
      themed_window = described_class.new(on_command: ->(_command) {}, theme: theme)

      css = themed_window.send(:vital_css, :health, Grimoire::Color.new(red: 200, green: 0, blue: 0))

      expect(css.scan('min-height: 0px').length).to eq(2)
    end

    it '#inset subtracts 2x the global padding from the target, clamped at 0' do
      theme = Grimoire::Theme::DEFAULT.with(padding: 5)
      themed_window = described_class.new(on_command: ->(_command) {}, theme: theme)

      expect(themed_window.send(:inset, 20)).to eq(10)
      expect(themed_window.send(:inset, 8)).to eq(0)
    end

    it 'insets the roundtime bar trough by the global padding, keeping its total size matched to the command bar height' do
      css = window.send(:roundtime_css)
      expected_inset = window.send(:inset, window.send(:command_bar_height))

      expect(css).to include('padding: 2px')
      expect(css).to include('min-width: 87px')
      expect(css.scan("min-height: #{expected_inset}px").length).to eq(3)
    end

    # The user's own spec (2026-09-13): the roundtime bar's height should
    # automatically track the command bar's real height rather than a fixed
    # pixel constant that silently drifts out of sync once command_bar gets
    # its own font settings.
    describe '#command_bar_height' do
      it 'measures a real, positive height for @entry' do
        expect(window.send(:command_bar_height)).to be_a(Integer)
        expect(window.send(:command_bar_height)).to be_positive
      end

      it 'is memoized -- the same value on repeated calls' do
        first  = window.send(:command_bar_height)
        second = window.send(:command_bar_height)

        expect(first).to eq(second)
      end

      it 'grows when command_bar_font_size grows, tracking the command bar automatically' do
        default_height = window.send(:command_bar_height)

        theme = Grimoire::Theme::DEFAULT.with(command_bar_font_size: 30)
        themed_window = described_class.new(on_command: ->(_command) {}, theme: theme)

        expect(themed_window.send(:command_bar_height)).to be > default_height
      end

      it 'drives the roundtime bar trough height, so the two stay in sync automatically' do
        theme = Grimoire::Theme::DEFAULT.with(command_bar_font_size: 30)
        themed_window = described_class.new(on_command: ->(_command) {}, theme: theme)

        css = themed_window.send(:roundtime_css)
        expected_inset = themed_window.send(:inset, themed_window.send(:command_bar_height))

        expect(css.scan("min-height: #{expected_inset}px").length).to eq(3)
      end
    end

    it 'renders a custom vitals border into the vital bar trough CSS' do
      theme = Grimoire::Theme::DEFAULT.with(
        vitals_border_color: Grimoire::Color.new(red: 0, green: 255, blue: 255),
        vitals_border_width: 1
      )
      themed_window = described_class.new(on_command: ->(_command) {}, theme: theme)

      css = themed_window.send(:vital_css, :health, Grimoire::Color.new(red: 200, green: 0, blue: 0))

      expect(css).to include('border-color: rgb(0, 255, 255)')
      expect(css).to include('border-width: 1px')
    end

    it 'defaults the vitals label text to white Overpass (not the mono family used elsewhere)' do
      css = window.send(:vital_css, :health, Grimoire::Color.new(red: 200, green: 0, blue: 0))
      text_rule = css[/progressbar\.vital-health text\s*\{[^}]*\}/]

      expect(text_rule).to include('color: rgb(255, 255, 255)')
      expect(text_rule).to include('font-family: Overpass, sans-serif')
    end

    it 'renders a custom vitals label text color, independent of the fill/border colors' do
      theme = Grimoire::Theme::DEFAULT.with(vitals_fg: Grimoire::Color.new(red: 10, green: 20, blue: 30))
      themed_window = described_class.new(on_command: ->(_command) {}, theme: theme)

      css = themed_window.send(:vital_css, :health, Grimoire::Color.new(red: 200, green: 0, blue: 0))
      text_rule = css[/progressbar\.vital-health text\s*\{[^}]*\}/]

      expect(text_rule).to include('color: rgb(10, 20, 30)')
    end

    it 'keeps the vitals label font family fixed at Overpass regardless of any other font setting' do
      theme = Grimoire::Theme::DEFAULT.with(font_family: 'Fira Code', command_bar_font_family: 'Fira Code')
      themed_window = described_class.new(on_command: ->(_command) {}, theme: theme)

      css = themed_window.send(:vital_css, :health, Grimoire::Color.new(red: 200, green: 0, blue: 0))
      text_rule = css[/progressbar\.vital-health text\s*\{[^}]*\}/]

      expect(text_rule).to include('font-family: Overpass, sans-serif')
    end

    it 'keeps every vital bar trough background fixed at #000000 regardless of any other color setting' do
      theme = Grimoire::Theme::DEFAULT.with(
        game_window_bg: Grimoire::Color.new(red: 200, green: 200, blue: 200),
        padding_bg: Grimoire::Color.new(red: 10, green: 60, blue: 10),
        vitals_border_color: Grimoire::Color.new(red: 0, green: 255, blue: 255)
      )
      themed_window = described_class.new(on_command: ->(_command) {}, theme: theme)

      css = themed_window.send(:vital_css, :health, Grimoire::Color.new(red: 200, green: 0, blue: 0))
      trough_rule = css[/progressbar\.vital-health trough\s*\{[^}]*\}/]

      expect(trough_rule).to include('background-color: rgb(0, 0, 0)')
    end

    it 'keeps the roundtime bar trough background fixed at #000000 regardless of any other color setting' do
      theme = Grimoire::Theme::DEFAULT.with(
        game_window_bg: Grimoire::Color.new(red: 200, green: 200, blue: 200),
        padding_bg: Grimoire::Color.new(red: 10, green: 60, blue: 10)
      )
      themed_window = described_class.new(on_command: ->(_command) {}, theme: theme)

      css = themed_window.send(:roundtime_css)
      trough_rule = css[/progressbar\.roundtime-bar trough\s*\{[^}]*\}/]

      expect(trough_rule).to include('background-color: rgb(0, 0, 0)')
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
