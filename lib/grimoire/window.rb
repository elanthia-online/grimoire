require 'gtk3'
require_relative 'vitals_colors'

module Grimoire
  # Main window: a vitals/indicator strip, a scrollback text view, and a
  # single-line command entry (MVP shape, matching rift-client's minimal
  # starting point per CLAUDE.md). Owns no socket or protocol state --
  # callers feed narrative text in via #append_text, structured vitals via
  # #update_vitals, and receive submitted commands through the on_command
  # callback. #append_text and #update_vitals must be called on the GTK
  # main thread; a caller feeding either from a socket thread should
  # marshal through GLib::Idle.add.
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

    private_constant :BAR_HEIGHT

    def initialize(on_command:)
      @on_command     = on_command
      @history        = []
      @history_index  = nil

      load_vitals_css
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
    # or guessing a value.
    def update_vitals(vitals_state)
      VITAL_LABELS.each_key do |field|
        vital = vitals_state.public_send(field)
        next unless vital

        set_bar(@vital_bars[field], vital.percent, vital.text)
      end

      set_bar(@stance_bar, vitals_state.stance, "Stance #{vitals_state.stance}%") if vitals_state.stance

      @indicator_label.text = active_indicators(vitals_state.indicators).join(' ')
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

    def recall_history
      @entry.text = @history[@history_index]
      @entry.position = -1
    end

    def build_window
      @buffer = Gtk::TextBuffer.new
      @view   = Gtk::TextView.new(@buffer)
      @view.editable   = false
      @view.wrap_mode  = :word_char
      @end_mark        = @buffer.create_mark(nil, @buffer.end_iter, false)

      scroller = Gtk::ScrolledWindow.new
      scroller.set_policy(:automatic, :automatic)
      scroller.add(@view)

      @entry = Gtk::Entry.new
      @entry.signal_connect('activate') { submit_command }
      @entry.signal_connect('key-press-event') { |_widget, event| handle_key_press(event) }

      box = Gtk::Box.new(:vertical)
      box.pack_start(build_vitals_strip, expand: false, fill: false, padding: 0)
      box.pack_start(scroller, expand: true, fill: true, padding: 0)
      box.pack_start(@entry, expand: false, fill: false, padding: 0)

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

    # A GTK theme's own stylesheet typically paints "progressbar progress"
    # with a gradient background-image, which otherwise wins over a plain
    # background-color -- resetting it to none per bar is what actually
    # lets VitalsColors::FIELDS's flat color show. One CSS class per field
    # (rather than one shared class with an inline per-widget color) is
    # what lets each bar keep its own fill color from one stylesheet.
    def load_vitals_css
      provider = Gtk::CssProvider.new
      provider.load(data: VitalsColors::FIELDS.map { |field, color| vital_css(field, color) }.join)
      Gtk::StyleContext.add_provider_for_screen(
        Gdk::Screen.default, provider, Gtk::StyleProvider::PRIORITY_APPLICATION
      )
    end

    def vital_css(field, color)
      <<~CSS
        progressbar.#{vital_css_class(field)} trough {
          background-color: #{VitalsColors::BACKGROUND.to_css};
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

    def vital_css_class(field)
      "vital-#{field}"
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
