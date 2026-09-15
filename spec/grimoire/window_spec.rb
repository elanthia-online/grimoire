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

  def command_vital_bar(window, field)
    window.instance_variable_get(:@command_vital_bars)[field]
  end

  def command_vital_label(window, field)
    window.instance_variable_get(:@command_vital_labels)[field]
  end

  def command_row(window)
    window.to_gtk.child.children.last
  end

  # Found by identity (the command_row child containing @entry), not
  # position -- command_row.children.last used to reliably mean
  # command_stack, but show_indicators now defaults true (2026-09-15), so
  # an indicator block is the last child by default instead whenever it is
  # built.
  def command_stack(window)
    entry = window.instance_variable_get(:@entry)
    command_row(window).children.find { |child| child.children.include?(entry) }
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

    it 'shows RT: 0 with an empty, uncolored bar when neither lock has ever been seen' do
      window.update_vitals(vitals_state)

      expect(roundtime_text(window)).to eq('RT: 0')
      expect(roundtime_bar(window).fraction).to eq(0.0)
      expect(roundtime_color(window)).to eq(:none)
    end

    # Fraction is seconds / @theme.roundtime_min_rt (default 5, down from
    # a fixed 10 before that became configurable, 2026-09-15) -- 3/5, not
    # 3/10.
    it 'shows the seconds remaining and health-red while hard roundtime is running' do
      vitals_state.roundtime_end = clock.now.to_i + 3

      window.update_vitals(vitals_state)

      expect(roundtime_text(window)).to eq('RT: 3')
      expect(roundtime_bar(window).fraction).to eq(0.6)
      expect(roundtime_color(window)).to eq(:hard)
    end

    # 5 seconds remaining now exactly matches the default roundtime_min_rt
    # (5), so the bar reads full (1.0), not 0.5 as it did under the old
    # fixed 10-second threshold.
    it 'shows the seconds remaining and mana-blue while only cast roundtime is running' do
      vitals_state.cast_roundtime_end = clock.now.to_i + 5

      window.update_vitals(vitals_state)

      expect(roundtime_text(window)).to eq('RT: 5')
      expect(roundtime_bar(window).fraction).to eq(1.0)
      expect(roundtime_color(window)).to eq(:cast)
    end

    it 'falls back to RT: 0 once the running lock has already elapsed' do
      vitals_state.roundtime_end = clock.now.to_i - 1

      window.update_vitals(vitals_state)

      expect(roundtime_text(window)).to eq('RT: 0')
      expect(roundtime_color(window)).to eq(:none)
    end

    it 'caps the fraction at 1.0 (full) for roundtime_min_rt (5) or more seconds remaining' do
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

    # Regression coverage for the user's own report (2026-09-15): the
    # entry's rendered height used to depend entirely on the ambient GTK
    # theme's own undocumented floor, which varied by platform/GTK version
    # for the identical default 11pt font (36px in one environment, 34px
    # reported live in another). Pinning min-height to inset(ICON_SIZE)
    # removes that variance -- the entry now measures exactly 32px by
    # default on any platform.
    it 'pins the command bar min-height to inset(ICON_SIZE), giving a deterministic 32px default height' do
      css = window.send(:command_bar_css)

      expect(css).to include('min-height: 28px')
      expect(window.send(:command_bar_height)).to eq(32)
    end

    it 'keeps the min-height floor at ICON_SIZE regardless of padding, the same #inset pattern every sized widget uses' do
      theme = Grimoire::Theme::DEFAULT.with(padding: 5)
      themed_window = described_class.new(on_command: ->(_command) {}, theme: theme)

      expect(themed_window.send(:command_bar_css)).to include('min-height: 22px')
      expect(themed_window.send(:command_bar_height)).to eq(32)
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

    it 'renders the vitals border color/width into each command_vitals bar trough, defaulting to invisible' do
      css = window.send(:command_vital_css, :health, Grimoire::Color.new(red: 200, green: 0, blue: 0))

      expect(css).to include('border-color: rgb(100, 100, 100)')
      expect(css).to include('border-width: 0px')
    end

    it 'insets the command_vitals bar trough/fill by the global padding, shrinking min-height to keep the total height fixed' do
      css = window.send(:command_vital_css, :health, Grimoire::Color.new(red: 200, green: 0, blue: 0))

      expect(css).to include('padding: 2px')
      expect(css.scan('min-height: 28px').length).to eq(2)
    end

    it 'clamps the command_vitals bar content height at 0 rather than going negative for a large padding' do
      theme = Grimoire::Theme::DEFAULT.with(padding: 20)
      themed_window = described_class.new(on_command: ->(_command) {}, theme: theme)

      css = themed_window.send(:command_vital_css, :health, Grimoire::Color.new(red: 200, green: 0, blue: 0))

      expect(css.scan('min-height: 0px').length).to eq(2)
    end

    it '#inset subtracts 2x the global padding from the target, clamped at 0' do
      theme = Grimoire::Theme::DEFAULT.with(padding: 5)
      themed_window = described_class.new(on_command: ->(_command) {}, theme: theme)

      expect(themed_window.send(:inset, 20)).to eq(10)
      expect(themed_window.send(:inset, 8)).to eq(0)
    end

    # show_command_vitals explicitly off -- it defaults true (2026-09-15)
    # and would otherwise make #command_area_height (which #roundtime_css
    # actually uses) taller than plain #command_bar_height, which is what
    # this test means to isolate.
    it 'insets the roundtime bar trough by the global padding, keeping its total size matched to the command bar height' do
      themed_window = described_class.new(
        on_command: ->(_command) {}, theme: Grimoire::Theme::DEFAULT.with(show_command_vitals: false)
      )
      css = themed_window.send(:roundtime_css)
      expected_inset = themed_window.send(:inset, themed_window.send(:command_bar_height))

      expect(css).to include('padding: 2px')
      expect(css).to include('min-width: 130px')
      expect(css.scan("min-height: #{expected_inset}px").length).to eq(3)
    end

    # Regression coverage for the user's own report (2026-09-15): the
    # roundtime bar used to be narrower than a 4x1 indicator row
    # (ROUNDTIME_BAR_WIDTH alone, 91px pre-2026-09-15), leaving empty
    # space when the two sat side by side or stacked
    # (status_indicators_location: :left). #roundtime_bar_target_width
    # adds the indicator row's own 3 inter-icon padding gaps back in, so
    # the two now match exactly regardless of @theme.padding.
    describe '#roundtime_bar_target_width' do
      it 'is ROUNDTIME_BAR_WIDTH (4 * ICON_SIZE = 128) plus 3 gaps of @theme.padding' do
        expect(window.send(:roundtime_bar_target_width)).to eq(128 + (3 * Grimoire::Theme::DEFAULT.padding))
      end

      it 'grows with padding, unlike a plain #inset-preserved size' do
        theme = Grimoire::Theme::DEFAULT.with(padding: 5)
        themed_window = described_class.new(on_command: ->(_command) {}, theme: theme)

        expect(themed_window.send(:roundtime_bar_target_width)).to eq(128 + (3 * 5))
      end

      it 'renders into #roundtime_css as the trough min-width, inset by the global padding' do
        css = window.send(:roundtime_css)
        expected_inset = window.send(:inset, window.send(:roundtime_bar_target_width))

        expect(css).to include("min-width: #{expected_inset}px")
      end

      it 'exactly matches a real 4x1 indicator row\'s own rendered width' do
        theme = Grimoire::Theme::DEFAULT.with(show_indicators: true, show_command_vitals: false)
        themed_window = described_class.new(on_command: ->(_command) {}, theme: theme)
        themed_window.show
        Gtk.main_iteration while Gtk.events_pending?

        indicator_row = themed_window.instance_variable_get(:@indicator_images).values.first.parent.parent
        expect(indicator_row.allocation.width).to eq(themed_window.send(:roundtime_bar_target_width))
      ensure
        themed_window.to_gtk.destroy
      end
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
        theme = Grimoire::Theme::DEFAULT.with(command_bar_font_size: 30, show_command_vitals: false)
        themed_window = described_class.new(on_command: ->(_command) {}, theme: theme)

        css = themed_window.send(:roundtime_css)
        expected_inset = themed_window.send(:inset, themed_window.send(:command_bar_height))

        expect(css.scan("min-height: #{expected_inset}px").length).to eq(3)
      end
    end

    it 'renders a custom vitals border into the command_vitals bar trough CSS' do
      theme = Grimoire::Theme::DEFAULT.with(
        vitals_border_color: Grimoire::Color.new(red: 0, green: 255, blue: 255),
        vitals_border_width: 1
      )
      themed_window = described_class.new(on_command: ->(_command) {}, theme: theme)

      css = themed_window.send(:command_vital_css, :health, Grimoire::Color.new(red: 200, green: 0, blue: 0))

      expect(css).to include('border-color: rgb(0, 255, 255)')
      expect(css).to include('border-width: 1px')
    end

    it 'defaults the command_vitals number label text to white Overpass (not the mono family used elsewhere)' do
      css = window.send(:command_vitals_text_css)

      expect(css).to include('color: rgb(255, 255, 255)')
      expect(css).to include('font-family: Overpass, sans-serif')
    end

    it 'keeps the command_vitals number label font family fixed at Overpass regardless of any other font setting' do
      theme = Grimoire::Theme::DEFAULT.with(font_family: 'Fira Code', command_bar_font_family: 'Fira Code')
      themed_window = described_class.new(on_command: ->(_command) {}, theme: theme)

      css = themed_window.send(:command_vitals_text_css)

      expect(css).to include('font-family: Overpass, sans-serif')
    end

    it 'keeps every command_vitals bar trough background fixed at #000000 regardless of any other color setting' do
      theme = Grimoire::Theme::DEFAULT.with(
        game_window_bg: Grimoire::Color.new(red: 200, green: 200, blue: 200),
        padding_bg: Grimoire::Color.new(red: 10, green: 60, blue: 10),
        vitals_border_color: Grimoire::Color.new(red: 0, green: 255, blue: 255)
      )
      themed_window = described_class.new(on_command: ->(_command) {}, theme: theme)

      css = themed_window.send(:command_vital_css, :health, Grimoire::Color.new(red: 200, green: 0, blue: 0))
      trough_rule = css[/progressbar\.command-vital-health trough\s*\{[^}]*\}/]

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
    # status_indicators_location explicit here -- it defaults :left as of
    # 2026-09-15, which (with show_command_vitals also on by default)
    # stacks the indicator block beneath the roundtime bar in its own
    # wrapping column instead of leaving the bar as command_row's own
    # first child directly. This whole describe block is about the
    # roundtime bar's own structure, not the location feature's
    # interaction with it, so :right (the original, unwrapped placement)
    # keeps these tests agnostic to that default.
    let(:window) do
      described_class.new(
        on_command: ->(command) { commands << command }, clock: clock,
        theme: Grimoire::Theme::DEFAULT.with(status_indicators_location: :right)
      )
    end

    # The command entry lives inside command_stack (a vertical Box), not
    # directly in command_row any more -- command_stack is what
    # command_vitals gets packed beneath once show_command_vitals is on,
    # see 'command_vitals' below. The roundtime bar still sits beside that
    # whole stack, in the same row.
    # command_stack.children is [entry] alone only when show_command_vitals
    # is off; it defaults true (2026-09-15), so checking the entry is
    # first (not the stack's only child) keeps this test agnostic to that
    # default.
    it 'packs the roundtime overlay to the left of the command entry, in the same row' do
      roundtime_widget = command_row(window).children.first

      expect(roundtime_widget).to be_a(Gtk::Overlay)
      expect(command_stack(window).children.first).to equal(window.instance_variable_get(:@entry))
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

    it 'tags the roundtime bar with its own base CSS class' do
      expect(roundtime_bar(window).style_context.has_class?('roundtime-bar')).to be(true)
    end
  end

  describe 'widget visibility toggles' do
    def build_window(theme)
      described_class.new(on_command: ->(_command) {}, clock: clock, theme: theme)
    end

    it 'skips building the roundtime bar when show_roundtime_bar is false' do
      # show_indicators/show_command_vitals explicitly off too, isolating
      # this test to just the roundtime toggle -- both default true
      # (2026-09-15) and would otherwise leave extra children in
      # command_row/command_stack.
      themed_window = build_window(
        Grimoire::Theme::DEFAULT.with(show_roundtime_bar: false, show_indicators: false, show_command_vitals: false)
      )

      expect(themed_window.instance_variable_get(:@roundtime_bar)).to be_nil
      expect(command_row(themed_window).children).to eq([command_stack(themed_window)])
      expect(command_stack(themed_window).children).to eq([themed_window.instance_variable_get(:@entry)])
    end

    it 'does not update the roundtime widget when it was never built' do
      themed_window = build_window(Grimoire::Theme::DEFAULT.with(show_roundtime_bar: false))
      vitals_state = Grimoire::VitalsState.new
      vitals_state.health = Grimoire::VitalsState::Vital.new(percent: 50, text: 'health 50%')

      expect { themed_window.update_vitals(vitals_state) }.not_to raise_error
    end

    it 'does not build the debug panel by default' do
      expect(window.instance_variable_get(:@debug_rows)).to be_nil
    end

    it 'leaves the main layout unwrapped when the debug menu is off, matching the pre-debug-panel widget tree' do
      expect(window.to_gtk.child).to be_a(Gtk::Box)
      expect(window.to_gtk.child.orientation).to eq(:vertical)
    end

    describe 'debug panel' do
      subject(:themed_window) { build_window(Grimoire::Theme::DEFAULT.with(show_debug_menu: true)) }

      def debug_rows(window)
        window.instance_variable_get(:@debug_rows)
      end

      def debug_value(window, field)
        debug_rows(window)[field][1]
      end

      it 'docks the debug panel to the right of the main (vertical) content' do
        content = themed_window.to_gtk.child

        expect(content.orientation).to eq(:horizontal)
        expect(content.children.first.orientation).to eq(:vertical)
        expect(content.children.last).to be_a(Gtk::ScrolledWindow)
      end

      # Regression coverage for the user's own report (2026-09-15): a plain
      # Gtk::Box has no drag handle between its children at all, so the
      # debug panel could not be resized once show_debug_menu shipped.
      # Gtk::Paned is what actually gives the user a draggable divider.
      it 'uses a draggable Gtk::Paned split, not a plain fixed-width Box, so the panel itself can be resized' do
        expect(themed_window.to_gtk.child).to be_a(Gtk::Paned)
      end

      # Regression coverage for the user's other report (2026-09-15): both
      # TreeViewColumns defaulted to GTK3's own non-resizable header, so a
      # long value (e.g. "98% (health 351/355)") clipped with no way to
      # widen the column to read it.
      it 'lets the user drag-resize both the variable and value columns' do
        view = themed_window.to_gtk.child.children.last.child

        expect(view.columns.map(&:resizable?)).to eq([true, true])
      end

      it 'builds one row per DEBUG_ROWS field, blank until the first update' do
        expect(debug_rows(themed_window).keys).to eq(Grimoire::Window::DEBUG_ROWS.map(&:first))
        Grimoire::Window::DEBUG_ROWS.each do |field, _label|
          expect(debug_value(themed_window, field)).to eq('')
        end
      end

      it 'updates a vital field to its percent/text pair on update_vitals' do
        vitals_state = Grimoire::VitalsState.new
        vitals_state.health = Grimoire::VitalsState::Vital.new(percent: 98, text: 'health 351/355')

        themed_window.update_vitals(vitals_state)

        expect(debug_value(themed_window, :health)).to eq('98% (health 351/355)')
      end

      it 'updates stance as a bare percent' do
        vitals_state = Grimoire::VitalsState.new
        vitals_state.stance = 80

        themed_window.update_vitals(vitals_state)

        expect(debug_value(themed_window, :stance)).to eq('80%')
      end

      it 'updates roundtime_end/cast_roundtime_end as raw epoch values' do
        vitals_state = Grimoire::VitalsState.new
        vitals_state.roundtime_end = 1_788_826_158
        vitals_state.cast_roundtime_end = 1_788_826_200

        themed_window.update_vitals(vitals_state)

        expect(debug_value(themed_window, :roundtime_end)).to eq('1788826158')
        expect(debug_value(themed_window, :cast_roundtime_end)).to eq('1788826200')
      end

      it 'updates indicators as a comma-joined list of only the currently-visible ids' do
        vitals_state = Grimoire::VitalsState.new
        vitals_state.set_indicator('IconBLEEDING', false)
        vitals_state.set_indicator('IconSTANDING', true)
        vitals_state.set_indicator('IconKNEELING', true)

        themed_window.update_vitals(vitals_state)

        expect(debug_value(themed_window, :indicators)).to eq('IconSTANDING, IconKNEELING')
      end

      it 'dynamically updates on repeated calls rather than only ever showing the first value' do
        vitals_state = Grimoire::VitalsState.new
        vitals_state.health = Grimoire::VitalsState::Vital.new(percent: 98, text: 'health 351/355')
        themed_window.update_vitals(vitals_state)

        vitals_state.health = Grimoire::VitalsState::Vital.new(percent: 40, text: 'health 140/355')
        themed_window.update_vitals(vitals_state)

        expect(debug_value(themed_window, :health)).to eq('40% (health 140/355)')
      end
    end
  end

  describe 'command_vitals' do
    def build_window(theme)
      described_class.new(on_command: ->(_command) {}, clock: clock, theme: theme)
    end

    # Revised from an initial *false* default -- the user's own later spec
    # (2026-09-15): command_vitals should default enabled, the same
    # revision status_indicators already got.
    it 'is built by default (show_command_vitals defaults to true)' do
      expect(window.instance_variable_get(:@command_vital_bars)).not_to be_nil
    end

    it 'is not built when show_command_vitals is explicitly false' do
      themed_window = build_window(Grimoire::Theme::DEFAULT.with(show_command_vitals: false))

      expect(themed_window.instance_variable_get(:@command_vital_bars)).to be_nil
    end

    it 'does not raise when update_vitals is called and it was never built' do
      themed_window = build_window(Grimoire::Theme::DEFAULT.with(show_command_vitals: false))
      vitals_state = Grimoire::VitalsState.new
      vitals_state.health = Grimoire::VitalsState::Vital.new(percent: 50, text: 'health 50%')

      expect { themed_window.update_vitals(vitals_state) }.not_to raise_error
    end

    describe 'when show_command_vitals is true' do
      subject(:themed_window) { build_window(Grimoire::Theme::DEFAULT.with(show_command_vitals: true)) }

      it 'builds exactly health/mana/stamina/spirit, left to right, no mind/encumbrance/stance' do
        expect(themed_window.instance_variable_get(:@command_vital_bars).keys).to eq(
          [:health, :mana, :stamina, :spirit]
        )
      end

      it 'stacks the command_vitals row beneath the command entry, inside command_stack' do
        entry = themed_window.instance_variable_get(:@entry)
        stack = command_stack(themed_window)

        expect(stack.children.first).to equal(entry)
        expect(stack.children.last).to be_a(Gtk::Box)
        expect(stack.children.last.orientation).to eq(:horizontal)
      end

      it 'sets each bar fraction and its number label from the matching Vital, with the label word stripped' do
        vitals_state = Grimoire::VitalsState.new
        vitals_state.health = Grimoire::VitalsState::Vital.new(percent: 72, text: 'health 255/355')

        themed_window.update_vitals(vitals_state)

        expect(command_vital_bar(themed_window, :health).fraction).to eq(0.72)
        expect(command_vital_label(themed_window, :health).text).to eq('255/355')
      end

      it 'leaves a bar at 0 and its label blank when that vital has not been seen yet' do
        vitals_state = Grimoire::VitalsState.new

        themed_window.update_vitals(vitals_state)

        expect(command_vital_bar(themed_window, :mana).fraction).to eq(0.0)
        expect(command_vital_label(themed_window, :mana).text).to eq('')
      end

      it 'defaults the number label to center justification' do
        expect(command_vital_label(themed_window, :health).halign).to eq(:center)
      end

      it 'tags each bar with its own command-vital-<field> CSS class' do
        expect(command_vital_bar(themed_window, :health).style_context.has_class?('command-vital-health')).to be(true)
      end

      # Regression coverage for the user's own correction (2026-09-15):
      # a brief fill: false + COMMAND_VITAL_MIN_WIDTH-capped-width design
      # (same day) left the four bars stopping short of the command
      # entry's own width. expand: true, fill: true (the original packing,
      # restored) makes the bars collectively span exactly the same width
      # as the entry above them; COMMAND_VITAL_MIN_WIDTH now only matters
      # as a floor for a window too narrow to give each bar its full share.
      it 'fills all available width -- the four bars together span exactly the command entry\'s own width' do
        themed_window.show
        Gtk.main_iteration while Gtk.events_pending?

        entry_width = themed_window.instance_variable_get(:@entry).allocation.width
        first_bar = command_vital_bar(themed_window, :health)
        last_bar = command_vital_bar(themed_window, :spirit)
        span = (last_bar.allocation.x + last_bar.allocation.width) - first_bar.allocation.x

        expect(span).to eq(entry_width)
      ensure
        themed_window.to_gtk.destroy
      end

      # The user's own spec (2026-09-15): exactly 3 gaps of @theme.padding
      # between the 4 bars -- already the row's own Gtk::Box spacing
      # (set on the box itself, not any one child's pack_start padding),
      # unaffected by fill: true/false, but confirmed here against the
      # real rendered gap between one bar's right edge and the next one's
      # left edge, not just the constructor argument.
      it 'spaces the four bars with exactly @theme.padding between them (3 gaps)' do
        themed_window.show
        Gtk.main_iteration while Gtk.events_pending?

        bars = [:health, :mana, :stamina, :spirit].map { |field| command_vital_bar(themed_window, field) }
        gaps = bars.each_cons(2).map { |left, right| right.allocation.x - (left.allocation.x + left.allocation.width) }

        expect(gaps).to eq([Grimoire::Theme::DEFAULT.padding] * 3)
      ensure
        themed_window.to_gtk.destroy
      end
    end

    # A left/center/right justify option existed briefly (2026-09-15) but
    # was removed the same day, the user's own spec: centered only, no
    # configurable alignment -- Theme has no command_vitals_number_justify
    # field to even pass one.
    it 'always centers the number label -- justify is not configurable' do
      themed_window = build_window(Grimoire::Theme::DEFAULT.with(show_command_vitals: true))

      expect(command_vital_label(themed_window, :health).halign).to eq(:center)
      expect(Grimoire::Theme::DEFAULT).not_to respond_to(:command_vitals_number_justify)
    end

    # The label is only built at all when numbers are enabled (not built
    # and hidden) -- see #build_command_vital_bar's own comment on why:
    # Gtk::Widget#show_all (called from #show) would force a #visible =
    # false label back on.
    it 'builds no number labels at all when command_vitals_show_numbers is false, though the bars still update' do
      themed_window = build_window(
        Grimoire::Theme::DEFAULT.with(show_command_vitals: true, command_vitals_show_numbers: false)
      )
      vitals_state = Grimoire::VitalsState.new
      vitals_state.health = Grimoire::VitalsState::Vital.new(percent: 72, text: 'health 255/355')

      themed_window.update_vitals(vitals_state)

      expect(themed_window.instance_variable_get(:@command_vital_labels)).to eq({})
      expect(command_vital_bar(themed_window, :health).fraction).to eq(0.72)
    end

    describe 'roundtime bar height' do
      it 'matches the plain command_bar_height when show_command_vitals is off (unchanged from before)' do
        themed_window = build_window(Grimoire::Theme::DEFAULT.with(show_command_vitals: false))

        expect(themed_window.send(:command_area_height)).to eq(themed_window.send(:command_bar_height))
      end

      # The user's own spec (2026-09-15): the roundtime bar grows taller to
      # span the whole command area (entry + the padding gap + the
      # ICON_SIZE-tall command_vitals row) once command_vitals is on.
      it 'grows by padding + ICON_SIZE (32) when show_command_vitals is on' do
        themed_window = build_window(Grimoire::Theme::DEFAULT.with(show_command_vitals: true))

        expected = themed_window.send(:command_bar_height) + Grimoire::Theme::DEFAULT.padding + 32
        expect(themed_window.send(:command_area_height)).to eq(expected)
      end

      # status_indicators_location explicit -- it defaults :left, which
      # (with the roundtime bar also on by default) triggers the
      # "stacked beneath" case instead, where the roundtime bar's own
      # height reverts to plain command_bar_height -- see the
      # 'status_indicators_location' describe block below for that case.
      it 'drives the roundtime bar trough height via command_area_height, not command_bar_height, once command_vitals is on' do
        themed_window = build_window(
          Grimoire::Theme::DEFAULT.with(show_command_vitals: true, status_indicators_location: :right)
        )

        css = themed_window.send(:roundtime_css)
        expected_inset = themed_window.send(:inset, themed_window.send(:command_area_height))

        expect(css.scan("min-height: #{expected_inset}px").length).to eq(3)
      end
    end

    describe 'theming' do
      it 'defaults every command_vitals bar to its own theme fill color' do
        css = window.send(:command_vital_css, :health, Grimoire::Theme::DEFAULT.command_vitals_colors[:health])

        expect(css).to include("background-color: #{Grimoire::Theme::DEFAULT.command_vitals_colors[:health].to_css}")
      end

      it 'keeps the trough background fixed at #000000 regardless of any other color setting' do
        css = window.send(:command_vital_css, :health, Grimoire::Theme::DEFAULT.command_vitals_colors[:health])
        trough_rule = css[/progressbar\.command-vital-health trough\s*\{[^}]*\}/]

        expect(trough_rule).to include('background-color: rgb(0, 0, 0)')
      end

      it 'insets COMMAND_VITAL_MIN_WIDTH (96px) by the global padding, the same #inset pattern as every other size' do
        css = window.send(:command_vital_css, :health, Grimoire::Theme::DEFAULT.command_vitals_colors[:health])

        expect(css.scan('min-width: 92px').length).to eq(2)
      end

      it 'keeps the min-width floor at 96px regardless of padding' do
        theme = Grimoire::Theme::DEFAULT.with(padding: 10)
        themed_window = build_window(theme)

        css = themed_window.send(:command_vital_css, :health, Grimoire::Theme::DEFAULT.command_vitals_colors[:health])

        expect(css.scan('min-width: 76px').length).to eq(2)
      end

      it 'renders a custom command_vitals fill color into the CSS' do
        theme = Grimoire::Theme::DEFAULT.with(
          command_vitals_colors: Grimoire::Theme::DEFAULT.command_vitals_colors.merge(
            health: Grimoire::Color.new(red: 9, green: 8, blue: 7)
          )
        )
        themed_window = build_window(theme)

        css = themed_window.send(:command_vital_css, :health, theme.command_vitals_colors[:health])

        expect(css).to include('background-color: rgb(9, 8, 7)')
      end

      it 'colors the number label from vitals_fg, independent of the fill colors' do
        theme = Grimoire::Theme::DEFAULT.with(vitals_fg: Grimoire::Color.new(red: 10, green: 20, blue: 30))
        themed_window = build_window(theme)

        expect(themed_window.send(:command_vitals_text_css)).to include('color: rgb(10, 20, 30)')
      end
    end
  end

  describe 'indicator block' do
    def build_window(theme)
      described_class.new(on_command: ->(_command) {}, clock: clock, theme: theme)
    end

    def indicator_image(window, slot_name)
      window.instance_variable_get(:@indicator_images)[slot_name]
    end

    def blank?(window, slot_name)
      indicator_image(window, slot_name).pixbuf.equal?(window.send(:blank_indicator_pixbuf))
    end

    # Revised from an initial *false* default -- the user's own later spec
    # (2026-09-15): status_indicators should default enabled.
    it 'is built by default (show_indicators defaults to true)' do
      expect(window.instance_variable_get(:@indicator_images)).not_to be_nil
    end

    it 'is not built when show_indicators is explicitly false' do
      themed_window = build_window(Grimoire::Theme::DEFAULT.with(show_indicators: false))

      expect(themed_window.instance_variable_get(:@indicator_images)).to be_nil
    end

    it 'does not raise when update_vitals is called and it was never built' do
      themed_window = build_window(Grimoire::Theme::DEFAULT.with(show_indicators: false))
      vitals_state = Grimoire::VitalsState.new
      vitals_state.set_indicator('IconKNEELING', true)

      expect { themed_window.update_vitals(vitals_state) }.not_to raise_error
    end

    describe 'when show_indicators is true and show_command_vitals is false (4x1)' do
      # show_command_vitals explicit now -- it defaults true (2026-09-15),
      # so this describe's own stated premise needs stating outright.
      # status_indicators_location explicit too -- it defaults :left as of
      # 2026-09-15; the dedicated 'status_indicators_location' describe
      # block below covers that default, this one is about the original
      # :right-docked shape.
      subject(:themed_window) do
        build_window(
          Grimoire::Theme::DEFAULT.with(
            show_indicators: true, show_command_vitals: false, status_indicators_location: :right
          )
        )
      end

      def indicator_block(window)
        window.to_gtk.child.children.last.children.last
      end

      it 'lays out a single horizontal row, one box per slot' do
        block = indicator_block(themed_window)

        expect(block).to be_a(Gtk::Box)
        expect(block.orientation).to eq(:horizontal)
        expect(block.children.length).to eq(4)
      end

      it 'keeps the original 4x1 slot order: posture, group, stealth, status' do
        expect(themed_window.instance_variable_get(:@indicator_images).keys).to eq(
          [:posture, :group, :stealth, :status]
        )
      end

      it 'tags every icon box with the fixed-black-background CSS class' do
        indicator_block(themed_window).children.each do |box|
          expect(box.style_context.has_class?('grimoire-indicator-icon-box')).to be(true)
        end
      end

      it 'starts every slot blank until the first update' do
        %i[posture group stealth status].each do |slot_name|
          expect(blank?(themed_window, slot_name)).to be(true)
        end
      end

      it 'is packed to the right of command_stack in command_row' do
        command_row = themed_window.to_gtk.child.children.last

        expect(command_row.children.last).to equal(indicator_block(themed_window))
      end
    end

    describe 'when show_indicators and show_command_vitals are both true (2x2)' do
      # status_indicators_location explicit -- it defaults :left as of
      # 2026-09-15, which (with the roundtime bar also on by default)
      # forces 4x1 instead of 2x2 (see the 'status_indicators_location'
      # describe block below for that case).
      subject(:themed_window) do
        build_window(
          Grimoire::Theme::DEFAULT.with(
            show_indicators: true, show_command_vitals: true, status_indicators_location: :right
          )
        )
      end

      def indicator_block(window)
        window.to_gtk.child.children.last.children.last
      end

      it 'lays out a 2x2 grid: a vertical box of two horizontal rows' do
        block = indicator_block(themed_window)

        expect(block).to be_a(Gtk::Box)
        expect(block.orientation).to eq(:vertical)
        expect(block.children.length).to eq(2)
        block.children.each do |row|
          expect(row).to be_a(Gtk::Box)
          expect(row.orientation).to eq(:horizontal)
          expect(row.children.length).to eq(2)
        end
      end

      it 'puts stealth/status on top, posture/group on the bottom -- a later, separate spec from the 4x1 order' do
        top_row, bottom_row = indicator_block(themed_window).children

        expect(top_row.children.map { |box| box.children.first }).to eq(
          [indicator_image(themed_window, :stealth), indicator_image(themed_window, :status)]
        )
        expect(bottom_row.children.map { |box| box.children.first }).to eq(
          [indicator_image(themed_window, :posture), indicator_image(themed_window, :group)]
        )
      end
    end

    describe 'update_vitals' do
      subject(:themed_window) { build_window(Grimoire::Theme::DEFAULT.with(show_indicators: true)) }

      it 'shows the icon IndicatorGroups.slots computes for each slot' do
        vitals_state = Grimoire::VitalsState.new
        vitals_state.set_indicator('IconKNEELING', true)
        vitals_state.set_indicator('IconJOINED', true)
        vitals_state.set_indicator('IconHIDDEN', true)
        vitals_state.set_indicator('IconSTUNNED', true)

        themed_window.update_vitals(vitals_state)

        expect(indicator_image(themed_window, :posture).pixbuf).to eq(themed_window.send(:indicator_pixbuf, 'kneeling.png'))
        expect(indicator_image(themed_window, :group).pixbuf).to eq(themed_window.send(:indicator_pixbuf, 'joined.png'))
        expect(indicator_image(themed_window, :stealth).pixbuf).to eq(themed_window.send(:indicator_pixbuf, 'hidden.png'))
        expect(indicator_image(themed_window, :status).pixbuf).to eq(themed_window.send(:indicator_pixbuf, 'stunned.png'))
      end

      it 'reverts a slot to blank once its indicator is no longer visible' do
        vitals_state = Grimoire::VitalsState.new
        vitals_state.set_indicator('IconKNEELING', true)
        themed_window.update_vitals(vitals_state)
        expect(blank?(themed_window, :posture)).to be(false)

        vitals_state.set_indicator('IconKNEELING', false)
        themed_window.update_vitals(vitals_state)

        expect(blank?(themed_window, :posture)).to be(true)
      end

      it 'shows standing once posture has been seen, establishing the always-populated baseline' do
        vitals_state = Grimoire::VitalsState.new
        vitals_state.set_indicator('IconSTANDING', true)

        themed_window.update_vitals(vitals_state)

        expect(indicator_image(themed_window, :posture).pixbuf).to eq(themed_window.send(:indicator_pixbuf, 'standing.png'))
        expect(blank?(themed_window, :group)).to be(true)
        expect(blank?(themed_window, :stealth)).to be(true)
        expect(blank?(themed_window, :status)).to be(true)
      end
    end

    describe 'theming' do
      it 'paints every icon box background a fixed black, independent of any theme' do
        theme = Grimoire::Theme::DEFAULT.with(
          show_indicators: true, padding_bg: Grimoire::Color.new(red: 200, green: 200, blue: 200)
        )
        themed_window = build_window(theme)

        expect(themed_window.send(:indicator_icon_box_css)).to include('background-color: rgb(0, 0, 0)')
      end
    end
  end

  describe 'status_indicators_location' do
    def build_window(theme)
      described_class.new(on_command: ->(_command) {}, clock: clock, theme: theme)
    end

    def indicator_block_for(window)
      window.instance_variable_get(:@indicator_images)
    end

    # No longer the default (status_indicators_location defaults :left as
    # of 2026-09-15, revised the same day from an initial :right), but the
    # shape/placement logic itself is unchanged from before this setting
    # existed.
    describe ':right' do
      it 'docks the block to the right of command_stack -- 4x1 when command_vitals is off' do
        themed_window = build_window(
          Grimoire::Theme::DEFAULT.with(
            show_indicators: true, show_command_vitals: false, status_indicators_location: :right
          )
        )
        roundtime_widget, stack, indicator_block = command_row(themed_window).children

        expect(roundtime_widget.child).to equal(themed_window.instance_variable_get(:@roundtime_bar))
        expect(stack).to equal(command_stack(themed_window))
        expect(indicator_block.orientation).to eq(:horizontal)
        expect(indicator_block_for(themed_window).keys).to eq([:posture, :group, :stealth, :status])
      end

      it 'grows to a 2x2 grid, still docked to the right, when command_vitals is on' do
        themed_window = build_window(
          Grimoire::Theme::DEFAULT.with(show_indicators: true, show_command_vitals: true, status_indicators_location: :right)
        )
        block = command_row(themed_window).children.last

        expect(block.orientation).to eq(:vertical)
        expect(block.children.length).to eq(2)
      end
    end

    describe ':left' do
      it 'docks to the left of command_stack when the roundtime bar is off, nothing to be "left of" instead' do
        themed_window = build_window(
          Grimoire::Theme::DEFAULT.with(
            show_indicators: true, show_roundtime_bar: false, show_command_vitals: false,
            status_indicators_location: :left
          )
        )
        indicator_block, stack = command_row(themed_window).children

        expect(stack).to equal(command_stack(themed_window))
        expect(indicator_block.orientation).to eq(:horizontal)
        expect(indicator_block.children.length).to eq(4)
      end

      # Regression coverage for the user's own correction (2026-09-15):
      # the original spec forced 4x1 "in all circumstances" for :left,
      # including this one -- but with the roundtime bar off, :left has
      # nothing to line up 4x1 against, so it should follow the same
      # show_command_vitals-driven 2x2 shape :right always has.
      it 'is a 2x2 grid, not 4x1, when the roundtime bar is off but command_vitals is on' do
        themed_window = build_window(
          Grimoire::Theme::DEFAULT.with(
            show_indicators: true, show_roundtime_bar: false, show_command_vitals: true,
            status_indicators_location: :left
          )
        )
        indicator_block, stack = command_row(themed_window).children

        expect(stack).to equal(command_stack(themed_window))
        expect(indicator_block.orientation).to eq(:vertical)
        expect(indicator_block.children.length).to eq(2)
      end

      it 'docks to the left of the roundtime bar when it is on and command_vitals is off' do
        themed_window = build_window(
          Grimoire::Theme::DEFAULT.with(
            show_indicators: true, show_command_vitals: false, status_indicators_location: :left
          )
        )
        indicator_block, roundtime_widget, stack = command_row(themed_window).children

        expect(indicator_block.orientation).to eq(:horizontal)
        expect(roundtime_widget.child).to equal(themed_window.instance_variable_get(:@roundtime_bar))
        expect(stack).to equal(command_stack(themed_window))
      end

      # The height reconciliation this needs: the roundtime bar's own CSS
      # height shrinks to plain #command_bar_height, and its own fixed
      # ROUNDTIME_BAR_WIDTH stays pinned (not stretched to the wider
      # indicator row's own width) via an explicit halign: :start -- see
      # #pack_command_row's own comment.
      it 'stacks beneath the roundtime bar in a shared column when both it and command_vitals are on' do
        themed_window = build_window(
          Grimoire::Theme::DEFAULT.with(
            show_indicators: true, show_command_vitals: true, status_indicators_location: :left
          )
        )
        themed_window.show
        Gtk.main_iteration while Gtk.events_pending?

        column, stack = command_row(themed_window).children
        roundtime_widget, indicator_block = column.children

        expect(column.orientation).to eq(:vertical)
        expect(roundtime_widget.child).to equal(themed_window.instance_variable_get(:@roundtime_bar))
        expect(roundtime_widget.halign).to eq(:start)
        expect(stack).to equal(command_stack(themed_window))
        expect(column.allocation.height).to eq(stack.allocation.height)
        # #roundtime_bar_target_width (2026-09-15) matches the indicator
        # row's own real width (including its 3 inter-icon padding gaps),
        # not just ROUNDTIME_BAR_WIDTH's zero-padding baseline -- the two
        # now span exactly the same width, leaving no empty space in the
        # shared column. halign: :start still matters if they were ever
        # to mismatch (a non-default padding elsewhere, say), just not
        # visibly here.
        expect(roundtime_widget.allocation.width).to eq(indicator_block.allocation.width)
        expect(roundtime_widget.allocation.width).to eq(themed_window.send(:roundtime_bar_target_width))
      ensure
        themed_window.to_gtk.destroy
      end

      # Still 4x1 here specifically because the roundtime bar is also on
      # (the default) -- see the 2x2 correction above for the case where
      # it is off instead.
      it 'stays 4x1 even when command_vitals is on, unlike :right, while the roundtime bar is also on' do
        themed_window = build_window(
          Grimoire::Theme::DEFAULT.with(
            show_indicators: true, show_command_vitals: true, show_roundtime_bar: true,
            status_indicators_location: :left
          )
        )
        column = command_row(themed_window).children.first
        indicator_block = column.children.last

        expect(indicator_block.orientation).to eq(:horizontal)
        expect(indicator_block.children.length).to eq(4)
        expect(indicator_block_for(themed_window).keys).to eq([:posture, :group, :stealth, :status])
      end
    end

    describe '#roundtime_bar_target_height' do
      it 'matches plain #command_bar_height when the indicator block is not stacked beneath it' do
        [
          Grimoire::Theme::DEFAULT.with(show_indicators: false, show_command_vitals: false),
          Grimoire::Theme::DEFAULT.with(show_indicators: true, show_command_vitals: false, status_indicators_location: :right),
          Grimoire::Theme::DEFAULT.with(show_indicators: true, show_command_vitals: false, status_indicators_location: :left),
        ].each do |theme|
          themed_window = build_window(theme)

          expect(themed_window.send(:roundtime_bar_target_height)).to eq(themed_window.send(:command_bar_height))
        end
      end

      it 'matches plain #command_bar_height, not #command_area_height, once the indicator block stacks beneath it' do
        themed_window = build_window(
          Grimoire::Theme::DEFAULT.with(
            show_indicators: true, show_command_vitals: true, status_indicators_location: :left
          )
        )

        expect(themed_window.send(:roundtime_bar_target_height)).to eq(themed_window.send(:command_bar_height))
        expect(themed_window.send(:roundtime_bar_target_height)).not_to eq(themed_window.send(:command_area_height))
      end

      it 'still matches #command_area_height when command_vitals is on but location is :right' do
        themed_window = build_window(
          Grimoire::Theme::DEFAULT.with(
            show_indicators: true, show_command_vitals: true, status_indicators_location: :right
          )
        )

        expect(themed_window.send(:roundtime_bar_target_height)).to eq(themed_window.send(:command_area_height))
      end
    end
  end
end
