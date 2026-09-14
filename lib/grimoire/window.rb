require 'gtk3'
require_relative 'theme'

module Grimoire
  # Main window: a vitals/indicator strip, a scrollback text view, a
  # roundtime bar, and a single-line command entry (MVP shape, matching
  # rift-client's minimal starting point per CLAUDE.md). Owns no socket or
  # protocol state -- callers feed narrative text in via #append_text,
  # structured vitals via #update_vitals, and receive submitted commands
  # through the on_command callback. #append_text and #update_vitals must
  # be called on the GTK main thread; a caller feeding either from a socket
  # thread should marshal through GLib::Idle.add.
  #
  # The roundtime bar (left of the command entry, see #build_roundtime_bar)
  # renders a single number derived from two independently-ticking locks --
  # hard roundtime (most actions, restricts most commands) and cast
  # roundtime (spell preparation, restricts spells/some commands), each a
  # wall-clock diff against VitalsState#roundtime_end/#cast_roundtime_end
  # (an absolute epoch, not a duration) via the injectable `clock:`
  # (defaults to Time, matching SessionLogger's own convention so specs can
  # pin a fixed "now" instead of racing the real clock). Per the user's own
  # spec (2026-09-13, see docs/decisions.md): the greater of the two
  # remaining-seconds values is what is displayed and what fills the bar
  # (full at 10s or more), but the *color* tracks hard roundtime specifically
  # -- health-red whenever hard roundtime is still running, mana-blue once
  # hard roundtime has ended but cast roundtime is still going. A hard
  # roundtime shorter than a concurrent cast roundtime therefore shows as a
  # single descending number that changes color partway through (e.g. 3s
  # hard / 5s cast displays 5,4,3 in red, then 2,1 in blue) rather than as
  # two separate counters.
  #
  # The "RT: <n>" text renders embedded on the bar itself (left-justified,
  # bold, white), not above/below it as a separate label -- GtkProgressBar's
  # own show_text overlay cannot do this (it centers, with no public
  # alignment/weight/color control, and in this GTK/theme combination it
  # does not even overlay the trough at all: it is laid out as a genuinely
  # separate CSS node stacked below it, confirmed by measuring natural
  # height at several candidate sizes and finding it additive). Instead
  # #build_roundtime_bar wraps a plain Gtk::ProgressBar (show_text: false)
  # and a separately-styled Gtk::Label in a Gtk::Overlay, giving full
  # control over the label's position/weight/color independent of the
  # bar's own fill.
  class Window
    # VitalsState field => strip label. Stance has no VitalsState field of
    # its own (a bare percent, not a Vital) so it is wired up separately in
    # #build_vitals_strip/#update_vitals rather than living in this table.
    VITAL_LABELS = {
      :health      => 'Health',
      :mana        => 'Mana',
      :stamina     => 'Stamina',
      :spirit      => 'Spirit',
      :mind        => 'Mind',
      :encumbrance => 'Enc',
    }.freeze

    # The default GTK theme's progressbar trough renders at roughly 5px
    # tall -- easy to miss at a glance. 4x that as a flat default. This is
    # the bar's whole rendered (total) height, not the trough's own CSS
    # min-height directly -- #vital_css derives that from #inset, which
    # subtracts 2x @theme.padding (CSS padding is added on top of
    # min-height, per the box model GTK follows here) so that giving every
    # bar's trough its own inner padding (the user's spec, 2026-09-13:
    # padding applies as content padding on every bordered widget, not just
    # spacing between widgets) insets the fill without growing the bar
    # taller than this.
    BAR_HEIGHT = 20

    # Every progress bar's trough background -- vitals strip and roundtime
    # bar alike -- the user's own spec (2026-09-13): fixed #000000
    # regardless of any other color setting, not themeable. There is
    # deliberately no corresponding Theme field (see Theme's own comment on
    # this); #vital_css/#roundtime_css interpolate this constant directly
    # rather than reading anything off @theme.
    PROGRESS_BAR_BACKGROUND = 'rgb(0, 0, 0)'

    # The vitals-strip label text's (e.g. "Health 253/355") font family --
    # the user's own spec (2026-09-13): switch it from the monospace family
    # used elsewhere (game_window/command_bar) to plain Overpass, but
    # deliberately fixed rather than themeable, unlike that label's own
    # color (Theme#vitals_fg). A generic sans-serif fallback, not
    # monospace, matches Overpass itself (a proportional family) -- see
    # assets/fonts/README.md for how it is bundled the same way Overpass
    # Mono already is.
    VITALS_FONT_FAMILY = 'Overpass, sans-serif'

    # A prior plain-label roundtime indicator (blank whenever idle) was
    # reported live as showing "no visible indicator" at all -- an empty
    # Gtk::Label renders as literally nothing, not even a reserved slot,
    # and there was nothing else in the strip anchoring its location. The
    # user's replacement spec (2026-09-13, see docs/decisions.md) moves it
    # to a progress bar, always showing "RT: <n>" and always occupying its
    # own fixed slot next to the command entry, regardless of value -- this
    # alone already fixes the visibility complaint, independent of the
    # color/fraction behavior below.
    #
    # ROUNDTIME_BAR_WIDTH is "roughly 60% the width of the minimum health
    # bar size" per that spec. The vital bars have no fixed width of their
    # own (pure Gtk::Box expand: true, sized by whatever the window gives
    # them), so there is no stored constant to read -- 152 is GTK's own
    # measured natural width, in this environment's theme, for a bare
    # Gtk::ProgressBar showing static text "Health" (build_bar's own idle
    # state before any vital has been set) with no min-width CSS applied.
    # 60% of that, rounded, is ROUNDTIME_BAR_WIDTH. Revisit if a theme
    # change ever makes 152 stop matching what #build_bar actually renders.
    # Still the bar's whole rendered (total) width, not the trough's own
    # CSS min-width directly -- see #inset.
    #
    # The bar's *height* is not a constant here at all -- see #command_bar_height
    # for why, and #roundtime_css for how it is used.
    ROUNDTIME_BAR_WIDTH = 91

    # The bar reads "full" (fraction 1.0) at this many seconds of
    # (whichever is greater of hard/cast) roundtime remaining, and stays
    # full for anything higher -- an arbitrary but explicit cap per the
    # user's spec, not derived from any real maximum roundtime length.
    ROUNDTIME_FULL_SECONDS = 10

    # Toggled on/off #build_roundtime_bar's style_context in
    # #update_roundtime_bar rather than baked in at construction, since the
    # bar's fill color changes live as hard roundtime ends but cast
    # roundtime continues (see the class comment's red-then-blue example).
    ROUNDTIME_BAR_CSS_CLASS  = 'roundtime-bar'
    ROUNDTIME_HARD_CSS_CLASS = 'roundtime-hard'
    ROUNDTIME_CAST_CSS_CLASS = 'roundtime-cast'

    # The overlaid "RT: <n>" label's own class -- always bold and white
    # regardless of the bar's fill color underneath it, so unlike the bar's
    # own color classes above this one is set once at construction and
    # never toggled.
    ROUNDTIME_TEXT_CSS_CLASS = 'roundtime-text'

    # OUTPUT_CSS_CLASS is themed by #game_window_css, INPUT_CSS_CLASS by
    # #command_bar_css -- independently themed (own bg/fg/font each) per the
    # user's own spec (2026-09-13), though they still share border/padding
    # (see those methods' own comments for why).
    OUTPUT_CSS_CLASS = 'grimoire-output'
    INPUT_CSS_CLASS  = 'grimoire-input'

    # Applied to the custom Gtk::HeaderBar set as the window's titlebar (see
    # #build_titlebar) so #title_bar_css can theme it -- a plain
    # Gtk::Window's native title bar is drawn by the window manager, not a
    # themeable GTK widget, so a themeable title bar means supplying our own.
    TITLE_BAR_CSS_CLASS = 'grimoire-titlebar'

    # Applied to the top-level Gtk::Window so #window_css can paint what
    # shows through padding's own gaps -- see Theme's padding_bg doc
    # comment for why those gaps need their own themeable color at all.
    WINDOW_CSS_CLASS = 'grimoire-window'

    # The scrollback auto-follows new text only while pinned to the bottom
    # (see @pinned_to_bottom) -- the user's own spec (2026-09-14): scrolling
    # up to read backlog should not have new text yank the view back down,
    # and scrolling back down to the bottom by hand should silently resume
    # auto-scroll, with no separate toggle control.
    #
    # Two earlier approaches were tried and rejected live:
    #
    # 1. Re-scrolling unconditionally on every #append_text via
    #    Gtk::TextView#scroll_to_mark. This alone does not use
    #    @pinned_to_bottom at all, so it cannot be what regressed once pinning
    #    was added -- but it is worth recording that scroll_to_mark, called
    #    synchronously right after a single-line insert, computes its target
    #    against line-height estimates GtkTextView has not finished
    #    validating yet for content beyond the already-validated region. It
    #    can land short of the true bottom (confirmed live: a value of 0.9
    #    where the full scroll range was only 9) and does not get
    #    automatically corrected once validation catches up.
    #
    # 2. Deriving @pinned_to_bottom reactively from the scroller's vadjustment
    #    'value-changed' signal, comparing the current value against
    #    upper/page_size on every fire. This is the bug the user actually hit:
    #    'value-changed' also fires for the scroll_to_mark glitch above, so
    #    the very first line to overflow the visible page could read as "the
    #    user scrolled away" purely from that glitch, latching
    #    @pinned_to_bottom false with no user action involved -- and since
    #    #append_text then never scrolls again, the adjustment's value never
    #    changes again either, so nothing ever re-fires to correct it. This
    #    is also exactly the "does not scroll if the initial content does not
    #    fill the window" report: that is the first-overflow transition where
    #    the glitch occurs.
    #
    # The fix separates the two concerns that approach conflated:
    #
    # - Auto-follow is driven by the scroller's vadjustment 'changed' signal
    #   (#follow_to_bottom_if_pinned), not 'value-changed' and not
    #   scroll_to_mark. 'changed' fires only once GTK has actually finished
    #   recomputing upper/page_size for the newly inserted text -- confirmed
    #   live that upper already reflects each line's real height by the time
    #   this fires, unlike scroll_to_mark's premature estimate -- so setting
    #   the adjustment's value directly from the now-accurate upper/page_size
    #   has nothing left to guess.
    # - @pinned_to_bottom is updated only in response to genuine user input:
    #   a mouse-wheel/touchpad scroll over the scrollback (@view's
    #   'scroll-event', checked via signal_connect_after so the default
    #   handler has already applied the resulting value) or a scrollbar
    #   click/drag (the vscrollbar's own 'change-value', which GtkRange
    #   emits only for user-driven changes and hands the intended value
    #   directly, before it is applied). Content arriving no longer touches
    #   this flag at all, so it cannot be misread as a user action.
    #
    # AT_BOTTOM_EPSILON: how close counts as "at the bottom" when judging
    # whether a user scroll landed back at the end -- not exact equality,
    # since GTK's own reported value/upper can be off by a fractional pixel.
    AT_BOTTOM_EPSILON = 1.0

    private_constant :BAR_HEIGHT, :PROGRESS_BAR_BACKGROUND, :VITALS_FONT_FAMILY, :ROUNDTIME_BAR_WIDTH,
                     :ROUNDTIME_FULL_SECONDS, :ROUNDTIME_BAR_CSS_CLASS, :ROUNDTIME_HARD_CSS_CLASS,
                     :ROUNDTIME_CAST_CSS_CLASS, :ROUNDTIME_TEXT_CSS_CLASS, :OUTPUT_CSS_CLASS, :INPUT_CSS_CLASS,
                     :TITLE_BAR_CSS_CLASS, :WINDOW_CSS_CLASS, :AT_BOTTOM_EPSILON

    def initialize(on_command:, clock: Time, theme: Theme::DEFAULT)
      @on_command     = on_command
      @history        = []
      @history_index  = nil
      @clock          = clock
      @theme          = theme
      @pinned_to_bottom = true

      @entry = build_entry
      load_theme_css
      @gtk_window = build_window
    end

    def show
      @gtk_window.show_all
    end

    def to_gtk
      @gtk_window
    end

    def append_text(text)
      return if text.empty?

      @buffer.insert(@buffer.end_iter, text)
    end

    # vitals_state is a live Grimoire::VitalsState -- fields are nil until
    # VitalsTracker has actually seen the corresponding tag, so each is
    # left at the strip's initial 0%/unlabeled state rather than raising
    # or guessing a value. roundtime_end/cast_roundtime_end are each a wire
    # epoch, not a duration, so the remaining seconds shown are only ever as
    # fresh as the last call -- a caller wanting a live-ticking countdown
    # (rather than one that only moves when a new line arrives) needs to
    # call this again on a timer of its own even when no new vitals have
    # come in; see App#tick_roundtime.
    def update_vitals(vitals_state)
      VITAL_LABELS.each_key do |field|
        vital = vitals_state.public_send(field)
        next unless vital

        set_bar(@vital_bars[field], vital.percent, vital.text)
      end

      set_bar(@stance_bar, vitals_state.stance, "Stance #{vitals_state.stance}%") if vitals_state.stance

      @indicator_label.text = active_indicators(vitals_state.indicators).join(' ')
      update_roundtime_bar(vitals_state)
    end

    def submit_command
      command = @entry.text
      return if command.empty?

      @history << command
      @history_index = nil
      @entry.text = ''
      @on_command.call(command)
    end

    def history_up
      return if @history.empty?

      @history_index = @history_index.nil? ? @history.length - 1 : [@history_index - 1, 0].max
      recall_history
    end

    def history_down
      return if @history_index.nil?

      if @history_index >= @history.length - 1
        @history_index = nil
        @entry.text = ''
      else
        @history_index += 1
        recall_history
      end
    end

    private

    def set_bar(bar, percent, text)
      bar.fraction = (percent / 100.0).clamp(0.0, 1.0)
      bar.text     = text
    end

    # Indicator ids are a flat id => visible hash with no fixed icon list
    # (see VitalsState); only the currently-visible ones are shown, with
    # the shared "Icon" prefix stripped since it carries no meaning here.
    def active_indicators(indicators)
      indicators.select { |_id, visible| visible }.keys.map { |id| id.sub(/\AIcon/, '') }
    end

    # Per the user's spec: the displayed/filled number is whichever of hard
    # roundtime and cast roundtime has more time left, but the color
    # follows hard roundtime specifically (red while it is still running,
    # blue once it has ended but cast roundtime has not) -- see the class
    # comment's red-then-blue example. Neither running is the ordinary idle
    # state between actions, not an edge case, and renders as "RT: 0" with
    # an empty bar and no color class, same as any other 0-fraction bar.
    def update_roundtime_bar(vitals_state)
      hard_remaining = remaining_seconds(vitals_state.roundtime_end)
      cast_remaining = remaining_seconds(vitals_state.cast_roundtime_end)
      seconds = [hard_remaining, cast_remaining].max

      @roundtime_bar.fraction = (seconds / ROUNDTIME_FULL_SECONDS.to_f).clamp(0.0, 1.0)
      @roundtime_label.text   = "RT: #{seconds}"
      set_roundtime_color(hard: hard_remaining.positive?, cast: cast_remaining.positive?)
    end

    def remaining_seconds(end_epoch)
      return 0 unless end_epoch

      [end_epoch - @clock.now.to_i, 0].max
    end

    def set_roundtime_color(hard:, cast:)
      style = @roundtime_bar.style_context

      if hard
        style.add_class(ROUNDTIME_HARD_CSS_CLASS)
        style.remove_class(ROUNDTIME_CAST_CSS_CLASS)
      elsif cast
        style.add_class(ROUNDTIME_CAST_CSS_CLASS)
        style.remove_class(ROUNDTIME_HARD_CSS_CLASS)
      else
        style.remove_class(ROUNDTIME_HARD_CSS_CLASS)
        style.remove_class(ROUNDTIME_CAST_CSS_CLASS)
      end
    end

    def recall_history
      @entry.text = @history[@history_index]
      @entry.position = -1
    end

    # Built ahead of #build_window/#load_theme_css (see #initialize) rather
    # than inline there, so #command_bar_height has a fully-classed @entry
    # to measure before the roundtime bar's own CSS (which depends on that
    # measurement) is generated -- see #command_bar_height's own comment.
    def build_entry
      entry = Gtk::Entry.new
      entry.style_context.add_class(INPUT_CSS_CLASS)
      entry.signal_connect('activate') { submit_command }
      entry.signal_connect('key-press-event') { |_widget, event| handle_key_press(event) }
      entry
    end

    def build_window
      @buffer = Gtk::TextBuffer.new
      @view   = Gtk::TextView.new(@buffer)
      @view.editable   = false
      @view.wrap_mode  = :word_char
      @view.style_context.add_class(OUTPUT_CSS_CLASS)
      @view.signal_connect_after('scroll-event') { update_pinned_from_current_position; false }

      scroller = Gtk::ScrolledWindow.new
      scroller.set_policy(:automatic, :automatic)
      scroller.add(@view)
      @scroll_adjustment = scroller.vadjustment
      @scroll_adjustment.signal_connect('changed') { follow_to_bottom_if_pinned }
      scroller.vscrollbar.signal_connect('change-value') { |_range, _scroll, value| update_pinned_from(value); false }

      roundtime_widget = build_roundtime_bar

      command_row = Gtk::Box.new(:horizontal, @theme.padding)
      command_row.pack_start(roundtime_widget, expand: false, fill: false, padding: 0)
      command_row.pack_start(@entry, expand: true, fill: true, padding: 0)

      box = Gtk::Box.new(:vertical, @theme.padding)
      box.border_width = @theme.padding
      box.pack_start(build_vitals_strip, expand: false, fill: false, padding: 0)
      box.pack_start(scroller, expand: true, fill: true, padding: 0)
      box.pack_start(command_row, expand: false, fill: false, padding: 0)

      window = Gtk::Window.new
      window.title = 'grimoire'
      window.style_context.add_class(WINDOW_CSS_CLASS)
      window.set_titlebar(build_titlebar)
      window.set_default_size(640, 480)
      window.add(box)
      window.signal_connect('destroy') { Gtk.main_quit }
      window
    end

    # A plain Gtk::Window's title bar is drawn by the window manager, not a
    # GTK widget -- there is nothing there for #title_bar_css to theme.
    # Supplying a Gtk::HeaderBar via Gtk::Window#set_titlebar (GTK3's own
    # client-side-decoration mechanism) replaces it with one grimoire owns
    # and can color. show_close_button keeps the usual window controls
    # (close, and minimize/maximize where the platform shows them) rather
    # than requiring the user to fall back on a window-manager shortcut.
    def build_titlebar
      header = Gtk::HeaderBar.new
      header.title = 'grimoire'
      header.show_close_button = true
      header.style_context.add_class(TITLE_BAR_CSS_CLASS)
      header
    end

    def build_vitals_strip
      bars = Gtk::Box.new(:horizontal, @theme.padding)

      @vital_bars = {}
      VITAL_LABELS.each do |field, label|
        @vital_bars[field] = build_bar(label, field)
        bars.pack_start(@vital_bars[field], expand: true, fill: true, padding: 0)
      end

      @stance_bar = build_bar('Stance', :stance)
      bars.pack_start(@stance_bar, expand: true, fill: true, padding: 0)

      @indicator_label = Gtk::Label.new('')
      @indicator_label.xalign = 0

      strip = Gtk::Box.new(:vertical, @theme.padding)
      strip.pack_start(bars, expand: false, fill: false, padding: 0)
      strip.pack_start(@indicator_label, expand: false, fill: false, padding: 0)
      strip
    end

    def build_bar(label, field)
      bar = Gtk::ProgressBar.new
      bar.show_text = true
      bar.text      = label
      bar.fraction  = 0.0
      bar.style_context.add_class(vital_css_class(field))
      bar
    end

    # Returns a Gtk::Overlay (bar + label stacked, not two row items) so the
    # label paints on top of the bar's own fill rather than beside it --
    # see the class comment for why the label is a separate widget instead
    # of the bar's own show_text.
    def build_roundtime_bar
      @roundtime_bar = Gtk::ProgressBar.new
      @roundtime_bar.show_text = false
      @roundtime_bar.fraction  = 0.0
      @roundtime_bar.style_context.add_class(ROUNDTIME_BAR_CSS_CLASS)

      @roundtime_label = Gtk::Label.new('RT: 0')
      @roundtime_label.halign = :start
      @roundtime_label.valign = :center
      @roundtime_label.margin_start = 4
      @roundtime_label.style_context.add_class(ROUNDTIME_TEXT_CSS_CLASS)

      overlay = Gtk::Overlay.new
      overlay.add(@roundtime_bar)
      overlay.add_overlay(@roundtime_label)
      overlay
    end

    # A GTK theme's own stylesheet typically paints "progressbar progress"
    # with a gradient background-image, which otherwise wins over a plain
    # background-color -- resetting it to none per bar is what actually
    # lets @theme's flat color show. One CSS class per field (rather than
    # one shared class with an inline per-widget color) is what lets each
    # bar keep its own fill color from one stylesheet.
    #
    # Loaded as two providers, in order, rather than one combined string --
    # #roundtime_css depends on #command_bar_height, which needs @entry's
    # own CSS (#command_bar_css, part of the first provider) already
    # registered on the screen before it can be measured accurately (see
    # #command_bar_height's own comment on why an un-styled widget measures
    # as 0). Registering a second provider afterward is no different from
    # any other live config.yml-driven CSS reload as far as GTK is
    # concerned -- providers stack, they do not replace one another.
    def load_theme_css
      base_provider = Gtk::CssProvider.new
      base_css = @theme.vitals_colors.map { |field, color| vital_css(field, color) }.join +
                 game_window_css + command_bar_css + title_bar_css + window_css
      base_provider.load(data: base_css)
      Gtk::StyleContext.add_provider_for_screen(
        Gdk::Screen.default, base_provider, Gtk::StyleProvider::PRIORITY_APPLICATION
      )

      roundtime_provider = Gtk::CssProvider.new
      roundtime_provider.load(data: roundtime_css)
      Gtk::StyleContext.add_provider_for_screen(
        Gdk::Screen.default, roundtime_provider, Gtk::StyleProvider::PRIORITY_APPLICATION
      )
    end

    # trough carries PROGRESS_BAR_BACKGROUND's fixed fill (not @theme --
    # see that constant's own comment) and an optional
    # @theme.vitals_border_color/width frame around it -- border-width
    # defaults to 0 (invisible) so a config file only needs to mention a
    # width to opt in; border-style must be set explicitly since CSS borders
    # do not render at all with a width and color but no style. padding
    # insets the fill from trough/border (the user's spec, 2026-09-13:
    # padding is a global setting applied as content padding on every
    # bordered widget, not just spacing between widgets) -- min-height on
    # both trough and progress comes from #inset (BAR_HEIGHT minus the
    # padding being added back around it) rather than BAR_HEIGHT directly,
    # so the bar's whole rendered height stays BAR_HEIGHT regardless of
    # @theme.padding's value, not just at the default.
    #
    # The label text (e.g. "Health 253/355", from Gtk::ProgressBar's own
    # show_text/text, not a separate widget) is GTK's "text" CSS subnode of
    # "progressbar" -- confirmed live (2026-09-13) that both color and
    # font-family apply correctly through it, the same way #command_bar_css
    # colors GtkEntry directly with no extra node quirk to work around.
    # color is @theme.vitals_fg (the user's own spec, 2026-09-13: previously
    # not configurable at all); font-family is the fixed VITALS_FONT_FAMILY
    # constant, not @theme -- deliberately not themeable, per that same spec.
    def vital_css(field, color)
      <<~CSS
        progressbar.#{vital_css_class(field)} trough {
          background-color: #{PROGRESS_BAR_BACKGROUND};
          background-image: none;
          border-color: #{@theme.vitals_border_color.to_css};
          border-width: #{@theme.vitals_border_width}px;
          border-style: solid;
          padding: #{@theme.padding}px;
          min-height: #{inset(BAR_HEIGHT)}px;
        }
        progressbar.#{vital_css_class(field)} progress {
          background-color: #{color.to_css};
          background-image: none;
          min-height: #{inset(BAR_HEIGHT)}px;
        }
        progressbar.#{vital_css_class(field)} text {
          color: #{@theme.vitals_fg.to_css};
          font-family: #{VITALS_FONT_FAMILY};
        }
      CSS
    end

    # The primary scrollback output widget -- "the game window" (config.yml's
    # `game_window:` section, renamed from `main:` per the user's own spec
    # 2026-09-13 to better name what it actually is, as distinct from
    # grimoire's own top-level window chrome). Takes @theme's
    # game_window_bg/game_window_fg/font_family/font_size -- see
    # #command_bar_css for the independently-themed command entry, split out
    # from this method per the user's own later spec (2026-09-13): the
    # command entry previously shared this method's colors outright and had
    # no font setting of its own at all. "text" is TextView's own inner CSS
    # node that actually paints the buffer's background/text color; styling
    # the outer "textview" node alone leaves the default theme's white page
    # showing through.
    #
    # font-family/font-size are set on BOTH the outer "textview" node and
    # its "text" child -- confirmed live (2026-09-13, against a real
    # Adwaita-themed GtkTextView, not just the generated CSS string) that
    # setting them on "text" alone has no effect on the actually-rendered
    # glyphs: GtkTextView's Pango layout comes from
    # gtk_widget_get_pango_context, which resolves font from the widget's
    # own ("textview") CSS node, not the "text" node -- "text" governs
    # colors correctly but is simply never consulted for font. The
    # PangoContext font_description matched "Adwaita Sans 11" (the theme
    # default) even with a config.yml font family/size override in place,
    # until the same rule was duplicated onto the outer node. GtkEntry (see
    # #command_bar_css) has no such quirk -- it is a single CSS node, so a
    # font rule directly on it is enough.
    #
    # font_family is interpolated raw, not wrapped in a quote pair here --
    # a single bare name (e.g. "Monospace", Pango's own generic alias) is
    # valid CSS either way, but wrapping it would break a real CSS
    # font-family fallback list such as `"Overpass Mono", monospace`
    # (quoting the whole thing turns it into one invalid family name
    # instead of a specific font plus a generic fallback). Theme.font_family
    # is expected to already be valid CSS font-family syntax; config.yml is
    # where any quoting it needs gets added.
    # border-color/border-width/border-style go on the outer "textview"
    # node, not its inner "text" node -- a border frames the whole widget.
    # border-width defaults to 0 (invisible) so a config file only needs to
    # mention a width to opt in. This border is shared with the command
    # entry (see #command_bar_css) -- nothing has asked for those to split.
    #
    # padding, by contrast, goes on "text" specifically (not the outer
    # node) -- the user's spec (2026-09-13): padding is a global setting
    # applied as content padding on every bordered widget, giving the
    # actual rendered text breathing room from its own border, not just
    # controlling the spacing between widgets the way it did before.
    def game_window_css
      <<~CSS
        textview.#{OUTPUT_CSS_CLASS} {
          font-family: #{@theme.font_family};
          font-size: #{@theme.font_size}pt;
          border-color: #{@theme.border_color.to_css};
          border-width: #{@theme.border_width}px;
          border-style: solid;
        }
        textview.#{OUTPUT_CSS_CLASS} text {
          background-color: #{@theme.game_window_bg.to_css};
          color: #{@theme.game_window_fg.to_css};
          font-family: #{@theme.font_family};
          font-size: #{@theme.font_size}pt;
          padding: #{@theme.padding}px;
        }
      CSS
    end

    # The command entry -- independently themed from #game_window_css per
    # the user's own spec (2026-09-13): its own bg/fg/font rather than
    # borrowing game_window's outright, and a font setting at all (it
    # previously had none, silently rendering in the system default font
    # regardless of any config.yml font override). border-color/width and
    # padding still come from @theme.border_*/@theme.padding -- shared with
    # the scrollback (`game_window.border`/`global.padding` in config.yml),
    # since nothing has asked for those to split too. Unlike GtkTextView
    # (see #game_window_css's own comment on why its font rule needs
    # duplicating onto an outer node), GtkEntry is a single CSS node, so one
    # font-family/font-size rule directly on it is enough.
    def command_bar_css
      <<~CSS
        entry.#{INPUT_CSS_CLASS} {
          background-color: #{@theme.command_bar_bg.to_css};
          color: #{@theme.command_bar_fg.to_css};
          font-family: #{@theme.command_bar_font_family};
          font-size: #{@theme.command_bar_font_size}pt;
          border-color: #{@theme.border_color.to_css};
          border-width: #{@theme.border_width}px;
          border-style: solid;
          padding: #{@theme.padding}px;
        }
      CSS
    end

    # Colors the custom Gtk::HeaderBar #build_titlebar installs as the
    # window's titlebar -- background-image is reset to none the same way
    # #vital_css/#roundtime_css already do for progress bars, since
    # Adwaita's own headerbar stylesheet paints a gradient background-image
    # that otherwise wins over a plain background-color. box-shadow/border
    # are reset the same way -- Adwaita's headerbar carries its own subtle
    # inset highlight (box-shadow) and a bottom border-color for the
    # separator against the rest of the window, and left unreset both still
    # rendered as a stray 1px light line above and below the bar regardless
    # of @theme's own colors, reported live (2026-09-13).
    def title_bar_css
      <<~CSS
        headerbar.#{TITLE_BAR_CSS_CLASS} {
          background-color: #{@theme.title_bar_bg.to_css};
          background-image: none;
          color: #{@theme.title_bar_fg.to_css};
          box-shadow: none;
          border-style: none;
        }
      CSS
    end

    # Paints the top-level Gtk::Window itself, which is what actually shows
    # through padding's own gaps -- see Theme's padding_bg doc comment for
    # why those gaps (the outer border and the spacing between the vitals
    # strip/scrollback/command row, and between the individual vital bars)
    # have no widget of their own to inherit @theme.game_window_bg from
    # otherwise.
    def window_css
      <<~CSS
        window.#{WINDOW_CSS_CLASS} {
          background-color: #{@theme.padding_bg.to_css};
          background-image: none;
        }
      CSS
    end

    def vital_css_class(field)
      "vital-#{field}"
    end

    # CSS padding is content-box padding: GTK adds it on top of min-height/
    # min-width rather than eating into them, so a bar whose trough must
    # still add up to an exact total (BAR_HEIGHT; ROUNDTIME_BAR_WIDTH;
    # #command_bar_height -- see their own comments) needs that total's
    # *content* min-height/min-width reduced by 2x @theme.padding first.
    # Clamped at 0 rather than
    # going negative (which the CSS parser would simply reject) for a
    # padding value large enough to consume the whole target on its own --
    # the bar just renders taller/wider than the target in that case, no
    # different in kind from any other CSS min-height/min-width conflict.
    def inset(total)
      [total - (2 * @theme.padding), 0].max
    end

    # @entry's own natural (unallocated) height, in the theme currently
    # loaded -- what a hard-coded ROUNDTIME_BAR_HEIGHT constant used to
    # stand in for (measured once, by hand, against whatever font GtkEntry
    # happened to render in at the time). Derived here at runtime instead,
    # per the user's own spec (2026-09-13, reported live once command_bar
    # became independently themeable and the two bars visibly stopped
    # matching): the roundtime bar should automatically track the command
    # bar's real height as command_bar's own font/padding/border settings
    # change, not silently drift out of sync the way a fixed pixel constant
    # inevitably would the moment those settings differ from whatever the
    # constant was originally measured against.
    #
    # An unparented widget's #preferred_size reports 0 (confirmed live) --
    # GTK has no layout context to measure it against. A widget added to
    # *any* shown top-level does get a real, CSS-accurate natural size, so
    # @entry is temporarily reparented into a throwaway Gtk::OffscreenWindow
    # (rendered entirely off-screen, invisible to the user) just long enough
    # to measure it, then immediately removed again -- #build_window packs
    # the same @entry into the real command row afterward. Memoized since
    # @entry's own theme never changes after construction.
    def command_bar_height
      @command_bar_height ||= begin
        offscreen = Gtk::OffscreenWindow.new
        offscreen.add(@entry)
        offscreen.show_all
        # #show_all only queues the resize/layout pass, it does not run it
        # synchronously -- draining pending events is what actually forces
        # GTK to recompute size negotiation (confirmed live, 2026-09-13: a
        # #preferred_size query right after #show_all with no pump reported
        # the same height regardless of font-size, only changing once this
        # loop ran first).
        Gtk.main_iteration while Gtk.events_pending?
        height = @entry.preferred_size.last.height
        offscreen.remove(@entry)
        offscreen.destroy
        height
      end
    end

    # The outer progressbar node's own padding/border (a couple of stray
    # pixels beyond the trough's own min-height, confirmed by measuring a
    # bare bar with it left unzeroed) is reset to zero here so
    # #command_bar_height is the bar's whole natural height with nothing
    # left over -- unlike the vital bars, which never needed this since
    # they were never required to match another widget's height exactly.
    # trough carries the bar's fixed size (width from #inset of
    # ROUNDTIME_BAR_WIDTH, height from #inset of #command_bar_height -- not
    # either directly, so the padding it also now carries as content
    # padding, per the user's spec 2026-09-13, insets the fill instead of
    # growing the bar past the command-bar-height match) and idle
    # background regardless of state; the two .roundtime-hard/.roundtime-cast
    # progress rules are mutually exclusive at runtime (see
    # #set_roundtime_color) so only one ever applies at a time -- with
    # neither present (idle, fraction 0) the progress portion is not
    # visible anyway, so it needs no rule of its own. The label rule is the
    # "bolded, and white" half of the spec -- always applied, independent
    # of which (if either) color class the bar itself currently carries.
    def roundtime_css
      <<~CSS
        progressbar.#{ROUNDTIME_BAR_CSS_CLASS} {
          padding: 0px;
          border: 0px;
          margin: 0px;
        }
        progressbar.#{ROUNDTIME_BAR_CSS_CLASS} trough {
          background-color: #{PROGRESS_BAR_BACKGROUND};
          background-image: none;
          border-color: #{@theme.vitals_border_color.to_css};
          border-width: #{@theme.vitals_border_width}px;
          border-style: solid;
          padding: #{@theme.padding}px;
          min-width: #{inset(ROUNDTIME_BAR_WIDTH)}px;
          min-height: #{inset(command_bar_height)}px;
          margin: 0px;
        }
        progressbar.#{ROUNDTIME_BAR_CSS_CLASS}.#{ROUNDTIME_HARD_CSS_CLASS} progress {
          background-color: #{@theme.roundtime_hard.to_css};
          background-image: none;
          min-height: #{inset(command_bar_height)}px;
        }
        progressbar.#{ROUNDTIME_BAR_CSS_CLASS}.#{ROUNDTIME_CAST_CSS_CLASS} progress {
          background-color: #{@theme.roundtime_cast.to_css};
          background-image: none;
          min-height: #{inset(command_bar_height)}px;
        }
        label.#{ROUNDTIME_TEXT_CSS_CLASS} {
          color: white;
          font-weight: bold;
        }
      CSS
    end

    def handle_key_press(event)
      case event.keyval
      when Gdk::Keyval::KEY_Up
        history_up
        true
      when Gdk::Keyval::KEY_Down
        history_down
        true
      else
        false
      end
    end

    # Fires once GTK has actually finished recomputing the scroller's own
    # extent for newly-inserted text -- see the class comment for why this,
    # not #append_text plus scroll_to_mark, is what drives auto-follow.
    # Setting value directly (rather than scroll_to_mark/scroll_to_iter) has
    # nothing left to estimate: upper/page_size are already correct by the
    # time 'changed' fires.
    def follow_to_bottom_if_pinned
      return unless @pinned_to_bottom

      adjustment = @scroll_adjustment
      adjustment.value = [adjustment.upper - adjustment.page_size, adjustment.lower].max
    end

    def update_pinned_from_current_position
      update_pinned_from(@scroll_adjustment.value)
    end

    # value is the (post- or about-to-be-applied) scroll position from a
    # genuine user gesture -- see the class comment for why only these two
    # call sites (mouse-wheel/touchpad and scrollbar click/drag) feed this,
    # never content arriving.
    def update_pinned_from(value)
      adjustment = @scroll_adjustment
      @pinned_to_bottom = value + adjustment.page_size >= adjustment.upper - AT_BOTTOM_EPSILON
    end
  end
end
