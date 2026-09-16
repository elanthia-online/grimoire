require 'gtk3'
require_relative 'theme'
require_relative 'indicator_groups'

module Grimoire
  # Main window: a scrollback text view, a roundtime bar, a compact
  # command_vitals row, an icon-based indicator block, and a single-line
  # command entry (MVP shape, matching rift-client's minimal starting
  # point per CLAUDE.md). Owns no socket or
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
  # (full at @theme.roundtime_min_rt seconds or more -- 5 by default, was a
  # fixed 10 before that became configurable, 2026-09-15), but the *color*
  # tracks hard roundtime specifically
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
    # #build_command_vitals's row order -- left to right, the user's own
    # spec (2026-09-15): a second, compact bar row docked beneath the
    # command entry, showing only these four (not mind/encumbrance/stance).
    COMMAND_VITAL_FIELDS = [:health, :mana, :stamina, :spirit].freeze

    # Originally set to 124 (50% of the 248px each command_vitals bar
    # measured at under default conditions, expand: true, fill: true,
    # confirmed live 2026-09-15), then tightened further to 96, the user's
    # own later spec (2026-09-15) -- still comfortably fits the overlaid
    # number: "255/355"/"999/999" measure 69px, and even an unrealistically
    # generous "9999/9999" measures 87px, both under 96px, and no real game
    # circumstance produces a longer one. Reusing
    # #build_command_vital_bar's own expand: true, fill: false packing (see
    # #build_command_vitals) keeps the four bars evenly spaced across the
    # row's full width while capping each bar's own rendered width at this
    # value, the same min-width-as-a-floor-under-fill:-false shape
    # #build_roundtime_bar already uses for ROUNDTIME_BAR_WIDTH.
    COMMAND_VITAL_MIN_WIDTH = 96

    # #build_debug_panel's row order/labels -- every VitalsState field
    # currently populated by VitalsTracker (see docs/decisions.md), shown
    # under its own full name (e.g. "Encumbrance"). :indicators is plural
    # (a whole hash, not a single field) so it is kept
    # separate from the singular Vital/bare-percent/epoch fields above it
    # rather than folded into the same shape.
    DEBUG_ROWS = [
      [:health, 'Health'],
      [:mana, 'Mana'],
      [:stamina, 'Stamina'],
      [:spirit, 'Spirit'],
      [:mind, 'Mind'],
      [:encumbrance, 'Encumbrance'],
      [:stance, 'Stance'],
      [:roundtime_end, 'Roundtime End'],
      [:cast_roundtime_end, 'Cast Roundtime End'],
      [:indicators, 'Indicators'],
    ].freeze

    # 32px -- a common icon size, the user's own spec (2026-09-15). Plays
    # three roles, all meant to read as one consistent height in the live
    # command area: command_vitals bars (#command_vital_css), each
    # indicator icon in #build_indicator_block, and the command entry's own
    # min-height floor (#command_bar_css) -- see MAX_COMMAND_BAR_FONT_SIZE's
    # own comment in Config for the other half of pinning the entry to
    # exactly this height (GTK3's CSS has no max-height property at all,
    # confirmed live, so capping the font size that could grow the entry
    # past this floor is the only lever available).
    ICON_SIZE = 32

    # Every progress bar's trough background -- command_vitals and
    # roundtime bar alike -- the user's own spec (2026-09-13): fixed
    # #000000 regardless of any other color setting, not themeable. There
    # is deliberately no corresponding Theme field (see Theme's own comment
    # on this); #command_vital_css/#roundtime_css interpolate this constant
    # directly rather than reading anything off @theme.
    PROGRESS_BAR_BACKGROUND = 'rgb(0, 0, 0)'

    # command_vitals's own overlaid number label text (e.g. "351/355", see
    # #command_vitals_text_css) font family -- the user's own spec
    # (2026-09-13): switch it from the monospace family used elsewhere
    # (game_window/command_bar) to plain Overpass, but deliberately fixed
    # rather than themeable, unlike that label's own color
    # (Theme#vitals_fg). A generic sans-serif fallback, not monospace,
    # matches Overpass itself (a proportional family) -- see
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
    # ROUNDTIME_BAR_WIDTH was originally "roughly 60% the width of the
    # minimum health bar size" (91px), revised (2026-09-15) to 4 * ICON_SIZE
    # (128px) -- the user's own spec: matches a 4x1 indicator row's own
    # width with zero padding between icons, so the roundtime bar reads as
    # the same width baseline as #build_indicator_block's row, most
    # visibly when status_indicators_location: :left stacks or sits it
    # beside one. This is the zero-padding baseline only -- #roundtime_css
    # actually targets #roundtime_bar_target_width, not this constant
    # directly, since a real 4x1 row is never actually zero-padding (see
    # that method's own comment for why the real target has to grow with
    # @theme.padding too, to leave no gap between the roundtime bar's own
    # width and the indicator row's).
    #
    # The bar's *height* is not a constant here at all -- see #command_bar_height
    # for why, and #roundtime_css for how it is used.
    ROUNDTIME_BAR_WIDTH = 4 * ICON_SIZE

    # Toggled on/off #build_roundtime_bar's style_context in
    # #update_roundtime_bar rather than baked in at construction, since the
    # bar's fill color changes live as hard roundtime ends but cast
    # roundtime continues (see the class comment's red-then-blue example).
    ROUNDTIME_BAR_CSS_CLASS  = 'roundtime-bar'
    ROUNDTIME_HARD_CSS_CLASS = 'roundtime-hard'
    ROUNDTIME_CAST_CSS_CLASS = 'roundtime-cast'

    # The overlaid "RT: <n>" label's own class -- always bold and
    # @theme.roundtime_fg (white by default) regardless of the bar's fill
    # color underneath it, so unlike the bar's own color classes above this
    # one is set once at construction and never toggled.
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

    # Applied to each command_vitals bar's overlaid number label (see
    # #build_command_vital_bar/#command_vitals_text_css) -- reads
    # @theme.vitals_fg/VITALS_FONT_FAMILY via a separate Gtk::Overlay label
    # instead of GtkProgressBar's own show_text (see the class comment on
    # why the roundtime label already needs the same technique: show_text
    # cannot be aligned left/center/right, only centered).
    COMMAND_VITALS_TEXT_CSS_CLASS = 'grimoire-command-vitals-text'

    # Applied to each #build_indicator_block icon slot -- the same
    # fixed-black-background technique IndicatorWindow already uses for
    # the same reason (every icon in assets/indicators/ is designed for a
    # black backdrop regardless of theme, the user's own spec, 2026-09-15).
    INDICATOR_ICON_BOX_CSS_CLASS = 'grimoire-indicator-icon-box'

    # Same assets/indicators/*.png directory IndicatorWindow reads from --
    # not shared as a literal constant reference across the two classes
    # (each computes its own via __dir__), since they are independent
    # widgets that happen to read the same files, not one owning the other.
    INDICATOR_ASSETS_DIR = File.expand_path('../../assets/indicators', __dir__)

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

    private_constant :PROGRESS_BAR_BACKGROUND, :VITALS_FONT_FAMILY, :ROUNDTIME_BAR_WIDTH,
                     :COMMAND_VITAL_MIN_WIDTH,
                     :INDICATOR_ICON_BOX_CSS_CLASS, :INDICATOR_ASSETS_DIR,
                     :ROUNDTIME_BAR_CSS_CLASS, :ROUNDTIME_HARD_CSS_CLASS,
                     :ROUNDTIME_CAST_CSS_CLASS, :ROUNDTIME_TEXT_CSS_CLASS, :OUTPUT_CSS_CLASS, :INPUT_CSS_CLASS,
                     :TITLE_BAR_CSS_CLASS, :WINDOW_CSS_CLASS, :AT_BOTTOM_EPSILON,
                     :COMMAND_VITALS_TEXT_CSS_CLASS

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
    # left at the relevant widget's initial 0%/unlabeled state rather than
    # raising or guessing a value. roundtime_end/cast_roundtime_end are each
    # a wire epoch, not a duration, so the remaining seconds shown are only
    # ever as fresh as the last call -- a caller wanting a live-ticking
    # countdown (rather than one that only moves when a new line arrives)
    # needs to call this again on a timer of its own even when no new
    # vitals have come in; see Session#tick.
    def update_vitals(vitals_state)
      update_roundtime_bar(vitals_state)
      update_command_vitals(vitals_state)
      update_indicator_block(vitals_state)
      update_debug_panel(vitals_state)
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

    def update_debug_panel(vitals_state)
      return unless @debug_rows

      DEBUG_ROWS.each do |field, _label|
        @debug_rows[field][1] = debug_value(vitals_state, field)
      end
    end

    # Every DEBUG_ROWS field read back in its own wire-native shape rather
    # than reused through any other widget's own display logic (percent
    # clamped to a bar fraction, "Icon" prefix stripped) -- the whole point
    # of this panel is to show VitalsState's raw values for troubleshooting,
    # not a second copy of the already-themed widgets.
    def debug_value(vitals_state, field)
      case field
      when :stance
        vitals_state.stance.nil? ? '' : "#{vitals_state.stance}%"
      when :roundtime_end, :cast_roundtime_end
        vitals_state.public_send(field).to_s
      when :indicators
        vitals_state.indicators.select { |_id, visible| visible }.keys.join(', ')
      else
        vital = vitals_state.public_send(field)
        vital ? "#{vital.percent}% (#{vital.text})" : ''
      end
    end

    # Per the user's spec: the displayed/filled number is whichever of hard
    # roundtime and cast roundtime has more time left, but the color
    # follows hard roundtime specifically (red while it is still running,
    # blue once it has ended but cast roundtime has not) -- see the class
    # comment's red-then-blue example. Neither running is the ordinary idle
    # state between actions, not an edge case, and renders as "RT: 0" with
    # an empty bar and no color class, same as any other 0-fraction bar.
    def update_roundtime_bar(vitals_state)
      return unless @roundtime_bar

      hard_remaining = remaining_seconds(vitals_state.roundtime_end)
      cast_remaining = remaining_seconds(vitals_state.cast_roundtime_end)
      seconds = [hard_remaining, cast_remaining].max

      @roundtime_bar.fraction = (seconds / @theme.roundtime_min_rt.to_f).clamp(0.0, 1.0)
      @roundtime_label.text   = "RT: #{seconds}"
      set_roundtime_color(hard: hard_remaining.positive?, cast: cast_remaining.positive?)
    end

    def update_command_vitals(vitals_state)
      return unless @command_vital_bars

      COMMAND_VITAL_FIELDS.each do |field|
        vital = vitals_state.public_send(field)
        next unless vital

        @command_vital_bars[field].fraction = (vital.percent / 100.0).clamp(0.0, 1.0)
        @command_vital_labels[field]&.text = numeric_text(vital)
      end
    end

    # Vital#text carries a leading label word on the wire (e.g. "health
    # 351/355") -- command_vitals bars carry no label of their own, per the
    # user's own spec (2026-09-15: "no description or text"), so only the
    # fraction after that first word is shown.
    def numeric_text(vital)
      vital.text.split(' ', 2).last
    end

    # Swaps each slot's Gtk::Image#pixbuf directly rather than
    # adding/removing widgets -- simpler, and avoids re-decoding/repacking
    # on every call (#update_vitals runs on every wire line and once a
    # second from Session#tick, whether or not indicators actually
    # changed). #blank_indicator_pixbuf keeps every box at a fixed
    # ICON_SIZE regardless of whether its slot currently has an icon,
    # rather than emptying the Gtk::Image out -- consistent with every
    # other slot in this file staying built-and-present once shown (see
    # #build_indicator_block), just blank.
    def update_indicator_block(vitals_state)
      return unless @indicator_images

      slots = IndicatorGroups.slots(vitals_state.indicators)
      @indicator_images.each do |slot_name, image|
        filename = slots.public_send(slot_name)
        image.pixbuf = filename ? indicator_pixbuf(filename) : blank_indicator_pixbuf
      end
    end

    def indicator_pixbuf(filename)
      @indicator_pixbufs ||= {}
      @indicator_pixbufs[filename] ||=
        GdkPixbuf::Pixbuf.new(file: File.join(INDICATOR_ASSETS_DIR, filename)).scale_simple(ICON_SIZE, ICON_SIZE, :bilinear)
    end

    # A fully transparent ICON_SIZE x ICON_SIZE pixbuf -- GdkPixbuf has no
    # "empty" sentinel, and this keeps every indicator slot's Gtk::Image at
    # a fixed size whether or not it currently has an icon, rather than
    # needing to size the surrounding box (INDICATOR_ICON_BOX_CSS_CLASS's
    # own black background) by any other means.
    def blank_indicator_pixbuf
      @blank_indicator_pixbuf ||= GdkPixbuf::Pixbuf.new(
        colorspace: :rgb, has_alpha: true, bits_per_sample: 8, width: ICON_SIZE, height: ICON_SIZE
      ).tap { |pixbuf| pixbuf.fill!(0x00000000) }
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

      # command_stack holds the entry and, optionally, command_vitals
      # beneath it -- the roundtime bar (built below, see
      # #roundtime_bar_target_height) sits beside this whole stack rather
      # than just the entry alone, so it can span both rows once
      # command_vitals adds a second one -- see #pack_command_row for
      # where command_stack actually lands in command_row, which varies
      # by Theme#status_indicators_location. Not given explicit
      # expand/fill here since a vertical box's own cross axis (horizontal,
      # for @entry/command_vitals) already defaults to halign: :fill, which
      # is exactly the "stretch to the stack's full width" behavior the
      # entry already had packed directly into command_row before this
      # split existed.
      command_stack = Gtk::Box.new(:vertical, @theme.padding)
      command_stack.pack_start(@entry, expand: false, fill: false, padding: 0)

      command_vitals_widget = build_command_vitals if @theme.show_command_vitals
      command_stack.pack_start(command_vitals_widget, expand: false, fill: false, padding: 0) if command_vitals_widget

      roundtime_widget = build_roundtime_bar if @theme.show_roundtime_bar
      indicator_block  = build_indicator_block if @theme.show_indicators

      command_row = Gtk::Box.new(:horizontal, @theme.padding)
      pack_command_row(command_row, roundtime_widget: roundtime_widget, indicator_block: indicator_block,
                                     command_stack: command_stack)

      box = Gtk::Box.new(:vertical, @theme.padding)
      box.border_width = @theme.padding
      box.pack_start(scroller, expand: true, fill: true, padding: 0)
      box.pack_start(command_row, expand: false, fill: false, padding: 0)

      content = box
      if @theme.show_debug_menu
        content = Gtk::Paned.new(:horizontal)
        content.pack1(box, resize: true, shrink: false)
        content.pack2(build_debug_panel, resize: false, shrink: true)
      end

      window = Gtk::Window.new
      window.title = 'grimoire'
      window.style_context.add_class(WINDOW_CSS_CLASS)
      window.set_titlebar(build_titlebar)
      window.set_default_size(640, 480)
      window.add(content)
      window.signal_connect('destroy') { Gtk.main_quit }
      window
    end

    # Assembles command_row from its (up to) three pieces, per
    # Theme#status_indicators_location's own spec (2026-09-15):
    #
    # :right (unchanged from before this setting existed) --
    # [roundtime_widget?, command_stack, indicator_block?], indicator_block
    # docked to the right of everything else.
    #
    # :left, indicator_block present -- three shapes depending on what else
    # is on:
    # - roundtime_widget nil: [indicator_block, command_stack] (nothing to
    #   be "left of" or "beneath" instead).
    # - roundtime_widget present, show_command_vitals off:
    #   [indicator_block, roundtime_widget, command_stack] -- indicator
    #   block to the left of the roundtime bar.
    # - roundtime_widget present, show_command_vitals on: indicator_block
    #   is stacked directly beneath roundtime_widget in their own vertical
    #   column (roundtime_widget.halign = :start keeps it pinned to its own
    #   fixed ROUNDTIME_BAR_WIDTH rather than stretching to the column's
    #   width, which the wider indicator row now determines), that column
    #   then playing the role roundtime_widget alone used to:
    #   [[roundtime_widget, indicator_block] column, command_stack]. See
    #   #roundtime_bar_target_height for how the roundtime bar's own CSS
    #   height shrinks to make room for the indicator row beneath it,
    #   keeping the whole column matched to command_stack's height.
    def pack_command_row(command_row, roundtime_widget:, indicator_block:, command_stack:)
      if indicator_block && status_indicators_left?
        if roundtime_widget && @theme.show_command_vitals
          column = Gtk::Box.new(:vertical, @theme.padding)
          roundtime_widget.halign = :start
          column.pack_start(roundtime_widget, expand: false, fill: false, padding: 0)
          column.pack_start(indicator_block, expand: false, fill: false, padding: 0)
          command_row.pack_start(column, expand: false, fill: false, padding: 0)
        else
          command_row.pack_start(indicator_block, expand: false, fill: false, padding: 0)
          command_row.pack_start(roundtime_widget, expand: false, fill: false, padding: 0) if roundtime_widget
        end
        command_row.pack_start(command_stack, expand: true, fill: true, padding: 0)
      else
        command_row.pack_start(roundtime_widget, expand: false, fill: false, padding: 0) if roundtime_widget
        command_row.pack_start(command_stack, expand: true, fill: true, padding: 0)
        command_row.pack_start(indicator_block, expand: false, fill: false, padding: 0) if indicator_block
      end
    end

    def status_indicators_left?
      @theme.status_indicators_location == :left
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

    # A live dump of VitalsState's own fields (see DEBUG_ROWS), not a themed
    # gameplay widget -- a Gtk::TreeView/Gtk::ListStore pair reads as a
    # plain two-column spreadsheet out of the box, which is the whole
    # ask, so no custom CSS class/styling is added here the way every other
    # widget in this file gets. @debug_rows keeps each row's own
    # Gtk::TreeIter so #update_debug_panel can update column 1 in place by
    # field rather than rebuilding the store on every vitals update.
    def build_debug_panel
      store = Gtk::ListStore.new(String, String)

      @debug_rows = {}
      DEBUG_ROWS.each do |field, label|
        iter = store.append
        iter[0] = label
        iter[1] = ''
        @debug_rows[field] = iter
      end

      view = Gtk::TreeView.new(store)
      variable_column = Gtk::TreeViewColumn.new('Variable', Gtk::CellRendererText.new, text: 0)
      value_column    = Gtk::TreeViewColumn.new('Value', Gtk::CellRendererText.new, text: 1)
      # resizable defaults to false in GTK3 -- without it the header divider
      # cannot be dragged at all, which is what left long values (e.g. a
      # "98% (health 351/355)" cell) clipped with no way to widen the column.
      variable_column.resizable = true
      value_column.resizable = true
      view.append_column(variable_column)
      view.append_column(value_column)

      scroller = Gtk::ScrolledWindow.new
      scroller.set_policy(:automatic, :automatic)
      scroller.set_size_request(220, -1)
      scroller.add(view)
      scroller
    end

    # Live, icon-based 4-slot indicator display (IndicatorGroups.slots).
    # Grid shape is derived, not a Theme field of its own: a 2x2 grid whenever
    # show_command_vitals is on, *unless* the block is actually being
    # positioned relative to the roundtime bar (status_indicators_location
    # :left with show_roundtime_bar also on -- #pack_command_row's "left
    # of"/"beneath" cases), which forces 4x1 regardless -- see
    # #force_four_by_one?. Revised (2026-09-15) from an initial blanket
    # "4x1 in all circumstances for :left": with the roundtime bar off,
    # :left has nothing to line up 4x1 against, so it follows the same
    # show_command_vitals-driven 2x2 shape :right always has -- the user's
    # own correction, reported live after the original spec shipped. 4x1
    # keeps the original left-to-right slot order (posture, group,
    # stealth, status); the 2x2 row order is a separate, later spec (top:
    # stealth/status, bottom: posture/group) -- not a flattening of the
    # 4x1 order.
    def build_indicator_block
      @indicator_images = {}

      if @theme.show_command_vitals && !force_four_by_one?
        grid = Gtk::Box.new(:vertical, @theme.padding)
        grid.pack_start(build_indicator_row(%i[stealth status]), expand: false, fill: false, padding: 0)
        grid.pack_start(build_indicator_row(%i[posture group]), expand: false, fill: false, padding: 0)
        grid
      else
        build_indicator_row(%i[posture group stealth status])
      end
    end

    # Only :left, with the roundtime bar also on, forces 4x1 regardless of
    # show_command_vitals -- that is the "left of"/"beneath the roundtime
    # bar" placement (#pack_command_row), which needs a fixed 4x1 shape
    # either way. Without the roundtime bar on, :left has nothing to line
    # up against, so it does not force anything -- see #build_indicator_block's
    # own comment.
    def force_four_by_one?
      status_indicators_left? && @theme.show_roundtime_bar
    end

    # Each slot always gets its own box (see INDICATOR_ICON_BOX_CSS_CLASS's
    # own comment on the fixed black background) even while blank -- the
    # static-width design already established for IndicatorWindow, not a
    # variable-width list of only the currently-true indicators.
    def build_indicator_row(slot_names)
      row = Gtk::Box.new(:horizontal, @theme.padding)

      slot_names.each do |slot_name|
        box = Gtk::Box.new(:horizontal, 0)
        box.style_context.add_class(INDICATOR_ICON_BOX_CSS_CLASS)

        image = Gtk::Image.new(pixbuf: blank_indicator_pixbuf)
        box.pack_start(image, expand: false, fill: false, padding: 0)
        @indicator_images[slot_name] = image

        row.pack_start(box, expand: false, fill: false, padding: 0)
      end

      row
    end

    # A second, compact health/mana/stamina/spirit row docked beneath the
    # command entry -- left to right, in COMMAND_VITAL_FIELDS order, the
    # user's own spec (2026-09-15). expand: true, fill: true (reverted
    # from a brief fill: false + COMMAND_VITAL_MIN_WIDTH-capped-width
    # design the same day -- the user's own later correction, 2026-09-15:
    # the four bars should together fill the row's whole width, matching
    # the command entry above them, not stop at a capped natural width).
    # COMMAND_VITAL_MIN_WIDTH's own CSS min-width now only matters as a
    # floor for a window narrow enough that an equal share would otherwise
    # shrink a bar below it. The row's own @theme.padding spacing (set on
    # the Gtk::Box itself, not any one child's pack_start padding) is what
    # already puts exactly 3 gaps between the 4 bars, independent of
    # fill: -- unaffected by this change.
    def build_command_vitals
      row = Gtk::Box.new(:horizontal, @theme.padding)

      @command_vital_bars = {}
      @command_vital_labels = {}
      COMMAND_VITAL_FIELDS.each do |field|
        row.pack_start(build_command_vital_bar(field), expand: true, fill: true, padding: 0)
      end

      row
    end

    # No label text of its own (the user's own spec: "no description or
    # text") -- just the bar, plus an optional overlaid number
    # (Theme#command_vitals_show_numbers), always centered -- a
    # left/center/right justify option existed briefly (2026-09-15) but
    # was removed the same day, the user's own spec: centered only. The
    # label is only built at all when numbers are enabled, rather than
    # built-and-hidden -- the same convention every other show_*-gated
    # widget in this file already follows (see
    # #build_roundtime_bar/#build_debug_panel), and the only way to avoid
    # Gtk::Widget#show_all (called from #show) forcing a #visible = false
    # widget back on.
    def build_command_vital_bar(field)
      bar = Gtk::ProgressBar.new
      bar.show_text = false
      bar.fraction  = 0.0
      bar.style_context.add_class(command_vital_css_class(field))
      @command_vital_bars[field] = bar

      overlay = Gtk::Overlay.new
      overlay.add(bar)

      if @theme.command_vitals_show_numbers
        label = Gtk::Label.new('')
        label.halign = :center
        label.valign = :center
        label.margin_start = 4
        label.margin_end   = 4
        label.style_context.add_class(COMMAND_VITALS_TEXT_CSS_CLASS)
        @command_vital_labels[field] = label
        overlay.add_overlay(label)
      end

      overlay
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
      base_css = COMMAND_VITAL_FIELDS.map { |field| command_vital_css(field, @theme.command_vitals_colors[field]) }.join +
                 game_window_css + command_bar_css + title_bar_css + window_css +
                 command_vitals_text_css + indicator_icon_box_css
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

    # command_vitals bars are unlabeled progress bars only (see
    # #build_command_vital_bar) -- no "text" subnode rule here, since any
    # number rendered over one is a separate Gtk::Overlay label styled by
    # #command_vitals_text_css instead of GtkProgressBar's own show_text.
    # trough carries PROGRESS_BAR_BACKGROUND's fixed fill (not @theme --
    # see that constant's own comment) and an optional
    # @theme.vitals_border_color/width frame around it -- border-width
    # defaults to 0 (invisible) so a config file only needs to mention a
    # width to opt in; border-style must be set explicitly since CSS borders
    # do not render at all with a width and color but no style. padding
    # insets the fill from trough/border (the user's spec, 2026-09-13:
    # padding is a global setting applied as content padding on every
    # bordered widget, not just spacing between widgets) -- min-height/
    # min-width come from #inset (ICON_SIZE/COMMAND_VITAL_MIN_WIDTH minus
    # the padding being added back around them), so the bar's whole
    # rendered size stays at the target regardless of @theme.padding's
    # value, not just at the default. ICON_SIZE, not a separate constant,
    # per the user's own spec (2026-09-15: command_vitals should match the
    # same 32px height as the indicator icons). min-width floors each bar
    # at COMMAND_VITAL_MIN_WIDTH the same way --
    # with #build_command_vitals back to packing fill: true (2026-09-15),
    # a bar always stretches to its full allocated share regardless of
    # this value in the ordinary case; it only actually binds if that
    # share would otherwise shrink narrower than COMMAND_VITAL_MIN_WIDTH
    # (a window narrow enough, or with many other widgets crowding this
    # row).
    def command_vital_css(field, color)
      <<~CSS
        progressbar.#{command_vital_css_class(field)} trough {
          background-color: #{PROGRESS_BAR_BACKGROUND};
          background-image: none;
          border-color: #{@theme.vitals_border_color.to_css};
          border-width: #{@theme.vitals_border_width}px;
          border-style: solid;
          padding: #{@theme.padding}px;
          min-height: #{inset(ICON_SIZE)}px;
          min-width: #{inset(COMMAND_VITAL_MIN_WIDTH)}px;
        }
        progressbar.#{command_vital_css_class(field)} progress {
          background-color: #{color.to_css};
          background-image: none;
          min-height: #{inset(ICON_SIZE)}px;
          min-width: #{inset(COMMAND_VITAL_MIN_WIDTH)}px;
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
    #
    # min-height: #{inset(ICON_SIZE)}px pins the entry's own rendered
    # height at exactly ICON_SIZE (32px) by default, the same #inset
    # pattern every other sized widget in this file already uses --
    # replacing whatever undocumented floor
    # the ambient GTK theme happened to impose (confirmed live, 2026-09-15:
    # this varied by platform/GTK version before this rule existed, e.g.
    # 36px here vs. 34px reported live elsewhere, for the identical default
    # 11pt font). GTK3's CSS engine has no max-height property at all
    # (confirmed live: Gtk::CssProviderError, "'max-height' is not a valid
    # property name"), so this is only ever a floor -- Config's own
    # MAX_COMMAND_BAR_FONT_SIZE is the other half, capping the font size
    # that could otherwise grow the entry past it, per the user's own spec
    # (2026-09-15: "we will restrict font size").
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
          min-height: #{inset(ICON_SIZE)}px;
        }
      CSS
    end

    # Colors the custom Gtk::HeaderBar #build_titlebar installs as the
    # window's titlebar -- background-image is reset to none the same way
    # #command_vital_css/#roundtime_css already do for progress bars, since
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
    # why those gaps (the outer border and the spacing between
    # scrollback/command row, and between the individual command_vitals
    # bars) have no widget of their own to inherit @theme.game_window_bg
    # from otherwise.
    def window_css
      <<~CSS
        window.#{WINDOW_CSS_CLASS} {
          background-color: #{@theme.padding_bg.to_css};
          background-image: none;
        }
      CSS
    end

    # Colors each command_vitals bar's overlaid number label
    # (@theme.vitals_fg/VITALS_FONT_FAMILY) as a standalone label rule --
    # these bars have no "text" subnode of their own (show_text is false --
    # see #build_command_vital_bar).
    def command_vitals_text_css
      <<~CSS
        label.#{COMMAND_VITALS_TEXT_CSS_CLASS} {
          color: #{@theme.vitals_fg.to_css};
          font-family: #{VITALS_FONT_FAMILY};
        }
      CSS
    end

    # Fixed black regardless of @theme -- unrelated to any theme setting,
    # the user's own spec from the IndicatorWindow work (every icon in
    # assets/indicators/ is designed for a black backdrop).
    def indicator_icon_box_css
      <<~CSS
        box.#{INDICATOR_ICON_BOX_CSS_CLASS} {
          background-color: rgb(0, 0, 0);
        }
      CSS
    end

    def command_vital_css_class(field)
      "command-vital-#{field}"
    end

    # CSS padding is content-box padding: GTK adds it on top of min-height/
    # min-width rather than eating into them, so a bar whose trough must
    # still add up to an exact total (ICON_SIZE; ROUNDTIME_BAR_WIDTH;
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

    # The full height the roundtime bar's trough must now match: the
    # command entry's own real height (#command_bar_height) alone when
    # command_vitals is off (unchanged from before this existed), or that
    # plus the padding gap and ICON_SIZE-tall command_vitals row stacked
    # beneath it when it is on -- the user's own spec (2026-09-15): the
    # roundtime bar grows taller to span the whole command area, not just
    # the entry, once command_vitals adds a second row underneath it.
    # ICON_SIZE per command_vital_css's own comment (command_vitals bars
    # are ICON_SIZE tall). Computed from ICON_SIZE (a constant) rather
    # than measuring a real built command_vitals widget,
    # since #load_theme_css (and this method, via #roundtime_css) runs
    # before #build_window ever constructs one -- see #initialize's own
    # ordering.
    def command_area_height
      height = command_bar_height
      height += @theme.padding + ICON_SIZE if @theme.show_command_vitals
      height
    end

    # The height #roundtime_css actually targets -- #command_area_height,
    # except when the indicator block is stacked directly beneath the
    # roundtime bar in their own shared column (status_indicators_location
    # :left, show_command_vitals on -- see #pack_command_row). There, the
    # roundtime bar's own height needs to shrink back to plain
    # #command_bar_height, leaving @theme.padding + ICON_SIZE of the
    # column's total height for the indicator row stacked beneath it --
    # together the column still matches command_stack's own height exactly
    # (the same #command_area_height sum, just split across two widgets
    # instead of held by the roundtime bar alone).
    def roundtime_bar_target_height
      return command_bar_height if indicator_block_below_roundtime?

      command_area_height
    end

    def indicator_block_below_roundtime?
      @theme.show_indicators && status_indicators_left? && @theme.show_roundtime_bar && @theme.show_command_vitals
    end

    # The width #roundtime_css actually targets -- ROUNDTIME_BAR_WIDTH
    # (4 * ICON_SIZE) is only the zero-padding baseline; a real 4x1
    # indicator row (#build_indicator_row) is 4 boxes wide with 3 gaps of
    # @theme.padding between them (the row's own Gtk::Box spacing), so
    # its real total width is ROUNDTIME_BAR_WIDTH + 3 * @theme.padding,
    # not ROUNDTIME_BAR_WIDTH alone. Without adding those 3 gaps back
    # in, the roundtime bar would render narrower than the indicator
    # row beside/beneath it (status_indicators_location: :left) by
    # exactly that much, leaving empty space in their shared column
    # instead of the roundtime bar spanning it fully -- the user's own
    # report, 2026-09-15.
    def roundtime_bar_target_width
      ROUNDTIME_BAR_WIDTH + (3 * @theme.padding)
    end

    # The outer progressbar node's own padding/border (a couple of stray
    # pixels beyond the trough's own min-height, confirmed by measuring a
    # bare bar with it left unzeroed) is reset to zero here so
    # #command_bar_height is the bar's whole natural height with nothing
    # left over -- unlike the command_vitals bars, which never needed this
    # since they were never required to match another widget's height
    # exactly.
    # trough carries the bar's fixed size (width from #inset of
    # #roundtime_bar_target_width, height from #inset of #command_bar_height
    # -- not either directly, so the padding it also now carries as content
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
          min-width: #{inset(roundtime_bar_target_width)}px;
          min-height: #{inset(roundtime_bar_target_height)}px;
          margin: 0px;
        }
        progressbar.#{ROUNDTIME_BAR_CSS_CLASS}.#{ROUNDTIME_HARD_CSS_CLASS} progress {
          background-color: #{@theme.roundtime_hard.to_css};
          background-image: none;
          min-height: #{inset(roundtime_bar_target_height)}px;
        }
        progressbar.#{ROUNDTIME_BAR_CSS_CLASS}.#{ROUNDTIME_CAST_CSS_CLASS} progress {
          background-color: #{@theme.roundtime_cast.to_css};
          background-image: none;
          min-height: #{inset(roundtime_bar_target_height)}px;
        }
        label.#{ROUNDTIME_TEXT_CSS_CLASS} {
          color: #{@theme.roundtime_fg.to_css};
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
