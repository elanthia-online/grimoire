require 'gtk3'

module Grimoire
  # Main window: a scrollback text view plus a single-line command entry
  # (MVP shape, matching rift-client's minimal starting point per
  # CLAUDE.md). Owns no socket or protocol state -- callers feed narrative
  # text in via #append_text and receive submitted commands through the
  # on_command callback. #append_text must be called on the GTK main
  # thread; a caller feeding it from a socket thread should marshal
  # through GLib::Idle.add.
  class Window
    def initialize(on_command:)
      @on_command     = on_command
      @history        = []
      @history_index  = nil

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
      box.pack_start(scroller, expand: true, fill: true, padding: 0)
      box.pack_start(@entry, expand: false, fill: false, padding: 0)

      window = Gtk::Window.new
      window.title = 'grimoire'
      window.set_default_size(640, 480)
      window.add(box)
      window.signal_connect('destroy') { Gtk.main_quit }
      window
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
