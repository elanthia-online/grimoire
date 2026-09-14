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
    # tall -- easy to miss at a glance. 4x that as a flat default, applied
    # via CSS min-height (see #vital_css) since GTK3 progress bars have no
    # plain height property of their own.
    BAR_HEIGHT = 20

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
    #
    # ROUNDTIME_BAR_HEIGHT "matches the height of the command input" the
    # same way -- GtkEntry's own measured natural height in this
    # environment's theme is 34px. With show_text left on, a
    # Gtk::ProgressBar's own outer node also carries a couple of pixels of
    # padding/border beyond the trough's CSS min-height (confirmed by
    # measuring a bare bar with everything but the trough zeroed out); with
    # show_text off and that outer node explicitly zeroed too (see
    # #roundtime_css), the trough's own min-height is the bar's whole
    # natural height with no residual, so ROUNDTIME_BAR_HEIGHT can be the
    # plain 34px measured value directly, no fudge factor needed. The
    # "small amount of padding" the spec also asked for is the row's own
    # box-packing padding around the bar, not a shorter bar.
    ROUNDTIME_BAR_WIDTH = 91
    ROUNDTIME_BAR_HEIGHT = 34

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

    # Applied to the scrollback Gtk::TextView and the command Gtk::Entry so
    # #main_css can theme both -- per the user's spec (2026-09-13), the
    # primary input and output widgets share one background/foreground
    # pair rather than each picking their own.
    OUTPUT_CSS_CLASS = 'grimoire-output'
    INPUT_CSS_CLASS  = 'grimoire-input'

    private_constant :BAR_HEIGHT, :ROUNDTIME_BAR_WIDTH, :ROUNDTIME_BAR_HEIGHT, :ROUNDTIME_FULL_SECONDS,
                     :ROUNDTIME_BAR_CSS_CLASS, :ROUNDTIME_HARD_CSS_CLASS, :ROUNDTIME_CAST_CSS_CLASS,
                     :ROUNDTIME_TEXT_CSS_CLASS, :OUTPUT_CSS_CLASS, :INPUT_CSS_CLASS

    def initialize(on_command:, clock: Time, theme: Theme::DEFAULT)
      @on_command     = on_command
      @history        = []
      @history_index  = nil
      @clock          = clock
      @theme          = theme

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
      scroll_to_end
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

    def build_window
      @buffer = Gtk::TextBuffer.new
      @view   = Gtk::TextView.new(@buffer)
      @view.editable   = false
      @view.wrap_mode  = :word_char
      @view.style_context.add_class(OUTPUT_CSS_CLASS)
      @end_mark = @buffer.create_mark(nil, @buffer.end_iter, false)

      scroller = Gtk::ScrolledWindow.new
      scroller.set_policy(:automatic, :automatic)
      scroller.add(@view)

      @entry = Gtk::Entry.new
      @entry.style_context.add_class(INPUT_CSS_CLASS)
      @entry.signal_connect('activate') { submit_command }
      @entry.signal_connect('key-press-event') { |_widget, event| handle_key_press(event) }

      roundtime_widget = build_roundtime_bar

      command_row = Gtk::Box.new(:horizontal, 4)
      command_row.pack_start(roundtime_widget, expand: false, fill: false, padding: 4)
      command_row.pack_start(@entry, expand: true, fill: true, padding: 0)

      box = Gtk::Box.new(:vertical)
      box.pack_start(build_vitals_strip, expand: false, fill: false, padding: 0)
      box.pack_start(scroller, expand: true, fill: true, padding: 0)
      box.pack_start(command_row, expand: false, fill: false, padding: 0)

      window = Gtk::Window.new
      window.title = 'grimoire'
      window.set_default_size(640, 480)
      window.add(box)
      window.signal_connect('destroy') { Gtk.main_quit }
      window
    end

    def build_vitals_strip
      bars = Gtk::Box.new(:horizontal, 4)

      @vital_bars = {}
      VITAL_LABELS.each do |field, label|
        @vital_bars[field] = build_bar(label, field)
        bars.pack_start(@vital_bars[field], expand: true, fill: true, padding: 0)
      end

      @stance_bar = build_bar('Stance', :stance)
      bars.pack_start(@stance_bar, expand: true, fill: true, padding: 0)

      @indicator_label = Gtk::Label.new('')
      @indicator_label.xalign = 0

      strip = Gtk::Box.new(:vertical, 2)
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
    def load_theme_css
      provider = Gtk::CssProvider.new
      css = @theme.vitals_colors.map { |field, color| vital_css(field, color) }.join +
            roundtime_css + main_css
      provider.load(data: css)
      Gtk::StyleContext.add_provider_for_screen(
        Gdk::Screen.default, provider, Gtk::StyleProvider::PRIORITY_APPLICATION
      )
    end

    def vital_css(field, color)
      <<~CSS
        progressbar.#{vital_css_class(field)} trough {
          background-color: #{@theme.vitals_background.to_css};
          background-image: none;
          min-height: #{BAR_HEIGHT}px;
        }
        progressbar.#{vital_css_class(field)} progress {
          background-color: #{color.to_css};
          background-image: none;
          min-height: #{BAR_HEIGHT}px;
        }
      CSS
    end

    # The primary output (scrollback) and input (command entry) widgets,
    # per the user's spec (2026-09-13): both share @theme's main
    # background/foreground (black-on-white by default), and the
    # scrollback additionally takes @theme's font family/size -- GtkEntry
    # has no separate font setting exposed yet since nothing has asked for
    # one. "text" is TextView's own inner CSS node that actually paints the
    # buffer's background/text color; styling the outer "textview" node
    # alone leaves the default theme's white page showing through.
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
    # until the same rule was duplicated onto the outer node.
    #
    # font_family is interpolated raw, not wrapped in a quote pair here --
    # a single bare name (e.g. "Monospace", Pango's own generic alias) is
    # valid CSS either way, but wrapping it would break a real CSS
    # font-family fallback list such as `"Overpass Mono", monospace`
    # (quoting the whole thing turns it into one invalid family name
    # instead of a specific font plus a generic fallback). Theme.font_family
    # is expected to already be valid CSS font-family syntax; config.yml is
    # where any quoting it needs gets added.
    def main_css
      <<~CSS
        textview.#{OUTPUT_CSS_CLASS} {
          font-family: #{@theme.font_family};
          font-size: #{@theme.font_size}pt;
        }
        textview.#{OUTPUT_CSS_CLASS} text {
          background-color: #{@theme.main_background.to_css};
          color: #{@theme.main_foreground.to_css};
          font-family: #{@theme.font_family};
          font-size: #{@theme.font_size}pt;
        }
        entry.#{INPUT_CSS_CLASS} {
          background-color: #{@theme.main_background.to_css};
          color: #{@theme.main_foreground.to_css};
        }
      CSS
    end

    def vital_css_class(field)
      "vital-#{field}"
    end

    # The outer progressbar node's own padding/border (a couple of stray
    # pixels beyond the trough's own min-height, confirmed by measuring a
    # bare bar with it left unzeroed) is reset to zero here so
    # ROUNDTIME_BAR_HEIGHT is the bar's whole natural height with nothing
    # left over -- unlike the vital bars, which never needed this since
    # they were never required to match another widget's height exactly.
    # trough carries the bar's fixed size (width/height, per
    # ROUNDTIME_BAR_WIDTH/HEIGHT above) and idle background regardless of
    # state; the two .roundtime-hard/.roundtime-cast progress rules are
    # mutually exclusive at runtime (see #set_roundtime_color) so only one
    # ever applies at a time -- with neither present (idle, fraction 0) the
    # progress portion is not visible anyway, so it needs no rule of its
    # own. The label rule is the "bolded, and white" half of the spec --
    # always applied, independent of which (if either) color class the bar
    # itself currently carries.
    def roundtime_css
      <<~CSS
        progressbar.#{ROUNDTIME_BAR_CSS_CLASS} {
          padding: 0px;
          border: 0px;
          margin: 0px;
        }
        progressbar.#{ROUNDTIME_BAR_CSS_CLASS} trough {
          background-color: #{@theme.vitals_background.to_css};
          background-image: none;
          min-width: #{ROUNDTIME_BAR_WIDTH}px;
          min-height: #{ROUNDTIME_BAR_HEIGHT}px;
          padding: 0px;
          border: 0px;
          margin: 0px;
        }
        progressbar.#{ROUNDTIME_BAR_CSS_CLASS}.#{ROUNDTIME_HARD_CSS_CLASS} progress {
          background-color: #{@theme.roundtime_hard.to_css};
          background-image: none;
          min-height: #{ROUNDTIME_BAR_HEIGHT}px;
        }
        progressbar.#{ROUNDTIME_BAR_CSS_CLASS}.#{ROUNDTIME_CAST_CSS_CLASS} progress {
          background-color: #{@theme.roundtime_cast.to_css};
          background-image: none;
          min-height: #{ROUNDTIME_BAR_HEIGHT}px;
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

    def scroll_to_end
      @buffer.move_mark(@end_mark, @buffer.end_iter)
      @view.scroll_to_mark(@end_mark, 0.0, true, 0.0, 1.0)
    end
  end
end
