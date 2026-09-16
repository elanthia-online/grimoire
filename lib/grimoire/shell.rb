require 'gtk3'
require_relative 'narrative_stream'
require_relative 'session'
require_relative 'session_locator'
require_relative 'session_view'
require_relative 'theme'

module Grimoire
  # The application itself: one top-level window, its chrome (title bar, menu
  # bar) and a Gtk::Notebook holding one tab per connected character. Replaces
  # the former App, which paired exactly one SessionView with one Session --
  # the shell holds N of them, and exists with none.
  #
  # Owning the window here rather than in SessionView is what makes a
  # blank-start launch possible at all: the window has to exist before (and
  # after) any character is connected, so it cannot belong to a per-character
  # class. SessionView is now purely the content of a notebook page.
  class Shell
    # How often every open session's roundtime countdown is refreshed between
    # wire lines, in milliseconds -- see Session#tick for why this is driven
    # from out here rather than from a socket thread. One timer drives every
    # tab, including background ones, so a countdown stays correct while its
    # tab is not the visible one.
    ROUNDTIME_TICK_INTERVAL = 1000

    DEFAULT_WIDTH  = 640
    DEFAULT_HEIGHT = 480

    # Applied to the top-level Gtk::Window so #window_css can paint what shows
    # through the layout's padding gaps.
    WINDOW_CSS_CLASS = 'grimoire-window'

    # Gtk::Window's native title bar is drawn by the window manager, not a
    # widget, so it cannot be themed from CSS -- a Gtk::HeaderBar supplied via
    # #set_titlebar is a real widget and can be.
    TITLE_BAR_CSS_CLASS = 'grimoire-titlebar'

    # The blank-state backdrop: plain black. Artwork was layered over this
    # briefly (2026-09-15) and then dropped at the user's request -- the
    # drawn-and-scaled approach is recorded in docs/decisions.md if it comes
    # back, but nothing here depends on an asset now.
    EMPTY_BACKGROUND_COLOR = [0.0, 0.0, 0.0].freeze

    # Gap between a tab's label and its own close button.
    TAB_LABEL_SPACING = 4

    # Padding around the attach dialog's own content.
    DIALOG_PADDING = 10

    attr_reader :sessions

    def initialize(theme: Theme::DEFAULT, autolog: false, log_dir: 'logs',
                   prompt_char: NarrativeStream::DEFAULT_PROMPT_CHAR)
      @theme       = theme
      @autolog     = autolog
      @log_dir     = log_dir
      @prompt_char = prompt_char
      @sessions    = []
      # Kept alongside the sessions so #close_session can tear a view's
      # signal handlers down before its page is removed. Session itself is
      # deliberately view-agnostic (see lib/grimoire/session.rb), so the
      # shell tracks the pairing rather than asking the session for it.
      @views       = {}

      load_chrome_css
      build_window
    end

    # Opens one character in a new tab and starts it. Returns the Session.
    #
    # Connection failures are deliberately left to the caller rather than
    # swallowed here: what should happen depends on who asked. A launch-time
    # --character wants to report and retry, a menu action wants a dialog.
    def attach(host:, port:, character: nil)
      # Duplicate-attach guard: a second Connection to the same frontend port
      # would have both sockets racing the same Lich session. Focusing the
      # tab that already exists is friendlier than refusing outright, and
      # costs nothing -- host/port is the identity here rather than the
      # character name, which is nil for a raw --host/--port attach.
      existing = find_session(host, port)
      return focus(existing) if existing

      # The callback closes over `session`, which is still nil when the view
      # is built (the view has to exist first, since the session draws into
      # it) but is always set before the user can submit anything -- the same
      # ordering the single-session App used.
      session = nil
      view    = SessionView.new(on_command: ->(command) { session.send_command(command) }, theme: @theme)
      session = Session.new(
        host: host, port: port, character: character, view: view,
        autolog: @autolog, log_dir: @log_dir, prompt_char: @prompt_char
      )
      session.start

      add_tab(session, view, label: character || "#{host}:#{port}")
      session
    end

    def run
      GLib::Timeout.add(ROUNDTIME_TICK_INTERVAL) do
        @sessions.each(&:tick)
        true
      end

      @gtk_window.show_all
      show_relevant_page
      focus_current_input
      Gtk.main
    end

    def to_gtk
      @gtk_window
    end

    # True when this shell already holds a session on that host/port.
    def attached?(host, port)
      !find_session(host, port).nil?
    end

    # Disconnects one session and removes its tab. Grimoire only ever
    # attached to this Lich session, it did not start it, so closing the tab
    # deliberately leaves Lich itself running and reattachable -- the same
    # boundary BACKLOG.md draws for sessions grimoire did not spawn.
    def close_session(session)
      index = @sessions.index(session)
      return unless index

      session.stop
      # Order matters: disconnect the view's handlers *before* removing the
      # page. Removing it unrealizes the widgets, and a handler still live at
      # that moment fires against a GdkWindow that no longer exists -- which
      # is what produced a stream of Gtk/Gdk CRITICAL assertions on tab close.
      @views.delete(session)&.teardown
      @sessions.delete_at(index)
      @notebook.remove_page(index)
      show_relevant_page
    end

    private

    def find_session(host, port)
      @sessions.find { |session| session.host == host && session.port == port }
    end

    def focus(session)
      index = @sessions.index(session)
      @notebook.page = index if index
      focus_current_input
      session
    end

    # Focus follows the current tab into its command entry, so the user can
    # start typing a command without clicking first.
    def focus_current_input
      focus_input_on(@notebook.get_nth_page(@notebook.current_page))
    end

    # Looked up by page widget rather than index: while a tab is being
    # removed, the notebook switches pages before its indices and @sessions
    # agree again.
    def focus_input_on(page)
      @views.each_value.find { |view| view.content == page }&.focus_input
    end

    # Tab labels use the character name when one is known, falling back to
    # host:port for a raw --host/--port attach with no name to use.
    def add_tab(session, view, label:)
      @sessions << session
      @views[session] = view
      @notebook.append_page(view.content, build_tab_label(session, label))
      @notebook.show_all
      @notebook.page = @notebook.n_pages - 1
      show_relevant_page
      focus_current_input
    end

    # A label plus its own close button, the shape a notebook tab is expected
    # to have. The button carries no confirmation itself -- #confirm_close
    # does that, so closing is never one stray click away from dropping a
    # live connection.
    def build_tab_label(session, label)
      box   = Gtk::Box.new(:horizontal, TAB_LABEL_SPACING)
      text  = Gtk::Label.new(label)
      close = Gtk::Button.new
      close.image = Gtk::Image.new(icon_name: 'window-close-symbolic', size: :menu)
      close.relief = :none
      close.focus_on_click = false
      close.tooltip_text = 'Close session'
      close.signal_connect('clicked') { close_session(session) if confirm_close(session) }

      box.pack_start(text, expand: false, fill: false, padding: 0)
      box.pack_start(close, expand: false, fill: false, padding: 0)
      box.show_all
      box
    end

    # Closing drops a live connection to the game, so it asks first -- the
    # user's own call (2026-09-15) after finding a session could only be
    # ended by quitting grimoire entirely.
    def confirm_close(session)
      name = session.character || "#{session.host}:#{session.port}"
      dialog = Gtk::MessageDialog.new(
        parent: @gtk_window, flags: :modal, type: :question,
        buttons: Gtk::ButtonsType::OK_CANCEL,
        message: "Close the session for #{name}?"
      )
      dialog.secondary_text =
        'Grimoire will disconnect from this session. Lich itself keeps running, ' \
        'so the character stays logged in and can be attached again.'
      response = dialog.run
      dialog.destroy
      response == Gtk::ResponseType::OK
    end

    # The notebook and the blank-state backdrop are two pages of a Gtk::Stack
    # rather than one widget swapped in and out, so neither has to be rebuilt
    # as tabs come and go -- #show_relevant_page just picks which is visible.
    def show_relevant_page
      @stack.visible_child_name = @notebook.n_pages.zero? ? 'empty' : 'sessions'
    end

    def build_window
      @notebook = Gtk::Notebook.new
      @notebook.scrollable = true
      # Deferred to idle rather than done inside the handler: on a mouse click
      # GTK 3.24 emits switch-page from inside its tab button-press handler,
      # and that handler then grabs focus onto the notebook and moves it into
      # the page's first focusable child (the scrollback) -- regardless of
      # focus-on-click. Focusing the entry any earlier gets overridden. The
      # page is re-checked since a tab can be closed before the idle runs.
      @notebook.signal_connect_after('switch-page') do |_notebook, page, _index|
        GLib::Idle.add do
          focus_input_on(page) if !@notebook.destroyed? && @notebook.page_num(page) == @notebook.current_page
          false
        end
      end

      @stack = Gtk::Stack.new
      @stack.add_named(build_empty_state, 'empty')
      @stack.add_named(@notebook, 'sessions')

      layout = Gtk::Box.new(:vertical, 0)
      layout.pack_start(build_menu_bar, expand: false, fill: false, padding: 0)
      layout.pack_start(@stack, expand: true, fill: true, padding: 0)

      @gtk_window = Gtk::Window.new
      @gtk_window.title = 'grimoire'
      @gtk_window.style_context.add_class(WINDOW_CSS_CLASS)
      @gtk_window.set_titlebar(build_titlebar)
      @gtk_window.set_default_size(DEFAULT_WIDTH, DEFAULT_HEIGHT)
      @gtk_window.add(layout)
      # Guarded rather than a bare Gtk.main_quit: the window can also be
      # destroyed with no main loop running (during teardown, or in a spec
      # that never called #run), and quitting a loop that does not exist
      # raises a Gtk-CRITICAL "main_loops != NULL" assertion -- which is a
      # real crash risk, not just noise, and made the suite dump core
      # intermittently once specs began building several shells.
      @gtk_window.signal_connect('destroy') { Gtk.main_quit if Gtk.main_level.positive? }
    end

    def build_titlebar
      header = Gtk::HeaderBar.new
      header.title = 'grimoire'
      header.show_close_button = true
      header.style_context.add_class(TITLE_BAR_CSS_CLASS)
      header
    end

    # A drawn area rather than a themed widget so the backdrop fills whatever
    # space the notebook would have taken, at any window size, with no CSS
    # node of its own to fight over. Currently a flat black fill; it stays a
    # DrawingArea because that is also what any future artwork would need.
    def build_empty_state
      area = Gtk::DrawingArea.new
      area.signal_connect('draw') do |_widget, cairo|
        cairo.set_source_rgb(*EMPTY_BACKGROUND_COLOR)
        cairo.paint
        true
      end
      area
    end

    def build_menu_bar
      menu_bar = Gtk::MenuBar.new
      session_menu = Gtk::Menu.new

      attach_item = Gtk::MenuItem.new(label: 'Attach to session...')
      attach_item.signal_connect('activate') { prompt_for_session }
      session_menu.append(attach_item)

      # Present from the start, per the user's own call (2026-09-15), but
      # inert until BACKLOG.md's "Lich headless launch" section is picked up.
      launch_item = Gtk::MenuItem.new(label: 'Launch headless...')
      launch_item.sensitive = false
      session_menu.append(launch_item)

      session_menu.append(Gtk::SeparatorMenuItem.new)

      quit_item = Gtk::MenuItem.new(label: 'Quit')
      quit_item.signal_connect('activate') { Gtk.main_quit }
      session_menu.append(quit_item)

      root = Gtk::MenuItem.new(label: 'Session')
      root.submenu = session_menu
      menu_bar.append(root)
      menu_bar
    end

    # Lists whatever lich-5 has left in its session directory right now and
    # attaches to the chosen one. Deliberately the plain SessionLocator list
    # rather than the favorites-aware dialog BACKLOG.md's "Shell & connection
    # menu" section describes -- that one needs Lich's entry.yaml, which is
    # not picked up yet, and this uses only what already works today.
    def prompt_for_session
      found = SessionLocator.list.select(&:valid?)
      return report('No Lich sessions found', SessionLocator::SESSION_DIR) if found.empty?

      # Already-attached sessions are left out rather than listed and
      # rejected -- the user's own call (2026-09-15) on finding the dialog
      # offered sessions that were already open in a tab. The two empty
      # cases are reported differently, since "nothing is running" and
      # "everything running is already open" call for different next steps.
      sessions = found.reject { |session| attached?(session.host, session.port) }
      if sessions.empty?
        return report(
          'Every available session is already attached',
          'Each Lich session found is already open in a tab.'
        )
      end

      chosen = ask_which_session(sessions)
      return unless chosen

      begin
        attach(host: chosen.host, port: chosen.port, character: chosen.character)
      rescue Connection::ConnectError => e
        report("Could not attach to #{chosen.character}", e.message)
      end
    end

    def ask_which_session(sessions)
      dialog = Gtk::Dialog.new(title: 'Attach to session', parent: @gtk_window, flags: :modal)
      dialog.add_button(Gtk::Stock::CANCEL, Gtk::ResponseType::CANCEL)
      dialog.add_button(Gtk::Stock::OK, Gtk::ResponseType::OK)

      combo = Gtk::ComboBoxText.new
      sessions.each { |session| combo.append_text("#{session.character} (#{session.host}:#{session.port})") }
      combo.active = 0
      dialog.child.pack_start(combo, expand: false, fill: false, padding: DIALOG_PADDING)
      dialog.show_all

      response = dialog.run
      index    = combo.active
      dialog.destroy
      response == Gtk::ResponseType::OK ? sessions[index] : nil
    end

    def report(heading, detail)
      dialog = Gtk::MessageDialog.new(
        parent: @gtk_window, flags: :modal, type: :info,
        buttons: Gtk::ButtonsType::OK, message: heading
      )
      dialog.secondary_text = detail.to_s
      dialog.run
      dialog.destroy
    end

    def load_chrome_css
      provider = Gtk::CssProvider.new
      provider.load(data: window_css + title_bar_css)
      Gtk::StyleContext.add_provider_for_screen(
        Gdk::Screen.default, provider, Gtk::StyleProvider::PRIORITY_APPLICATION
      )
    end

    def window_css
      <<~CSS
        window.#{WINDOW_CSS_CLASS} {
          background-color: #{@theme.padding_bg.to_css};
          background-image: none;
        }
      CSS
    end

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
  end
end
