require 'gtk3'
require_relative 'account_guard'
require_relative 'connect_list'
require_relative 'launch_watcher'
require_relative 'lich_install'
require_relative 'lich_launcher'
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

    # Padding around a dialog's own content.
    DIALOG_PADDING = 10

    CONNECT_DIALOG_WIDTH  = 420
    CONNECT_DIALOG_HEIGHT = 320

    # What each ConnectList status looks like in the Connect dialog.
    CONNECT_STATUS_TEXT = {
      attached: 'Open in a tab',
      running: 'Running',
      launching: 'Launching...',
      not_running: 'Not running',
    }.freeze

    # A dropped session is rescanned this often, in milliseconds, and gives
    # up (closing its tab) once it has been down this many seconds -- the
    # user's own call (2026-09-16), "roughly 5 minutes", for every origin
    # that waits to reattach. See #handle_drop.
    REATTACH_SCAN_INTERVAL = 5000
    REATTACH_TIMEOUT       = 300

    DISCONNECTED_LABEL_SUFFIX = ' (disconnected)'

    # How often a Lich grimoire launched is checked for a session to attach
    # to, in milliseconds -- the same half second SessionLocator's own
    # startup retries use. See #await_launch.
    LAUNCH_POLL_INTERVAL = 500

    attr_reader :sessions

    # session_dir is where lich-5's .session files are looked up, both for
    # the Connect dialog and for rescanning dropped sessions. clock returns
    # seconds, and is monotonic so a wall-clock change cannot stretch or cut
    # short the reattach timeout. lich_dir is config.yml's lich.dir; with
    # none, the Connect dialog can attach but not launch.
    def initialize(theme: Theme::DEFAULT, autolog: false, log_dir: 'logs',
                   prompt_char: NarrativeStream::DEFAULT_PROMPT_CHAR,
                   session_dir: SessionLocator::SESSION_DIR,
                   clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
                   lich_dir: nil)
      @theme       = theme
      @autolog     = autolog
      @log_dir     = log_dir
      @prompt_char = prompt_char
      @session_dir = session_dir
      @clock       = clock
      @sessions    = []
      # Dropped sessions awaiting reattach, each mapped to the clock reading
      # when it dropped. A session in here keeps its tab but is not live.
      @dropped     = {}
      # Each tab's name label, kept so a drop or reattach can relabel it.
      @tab_labels  = {}
      # Kept alongside the sessions so #close_session can tear a view's
      # signal handlers down before its page is removed. Session itself is
      # deliberately view-agnostic (see lib/grimoire/session.rb), so the
      # shell tracks the pairing rather than asking the session for it.
      @views       = {}
      # The GLib source id of the rescan timer while one is running.
      @reattach_scan = nil
      # Launches still waiting for a session, each LaunchWatcher mapped to
      # the GLib source id of its poll timer.
      @launch_watches = {}
      # Built once per run so the launcher keeps track of every Lich this
      # run started. Whether the install is usable is checked each time the
      # Connect dialog opens, not here.
      @install  = lich_dir && LichInstall.new(lich_dir)
      @launcher = @install && LichLauncher.new(install: @install, log_dir: log_dir)

      load_chrome_css
      build_window
    end

    # Opens one character in a new tab and starts it. Returns the Session.
    #
    # Connection failures are deliberately left to the caller rather than
    # swallowed here: what should happen depends on who asked. A launch-time
    # --character wants to report and retry, a menu action wants a dialog.
    #
    # origin is one of Session::ORIGINS and decides what happens if the
    # connection later drops -- see #handle_drop.
    def attach(host:, port:, character: nil, origin: :attached)
      # Duplicate-attach guard: a second Connection to the same frontend port
      # would have both sockets racing the same Lich session. Focusing the
      # tab that already exists is friendlier than refusing outright, and
      # costs nothing -- host/port is the identity here rather than the
      # character name, which is nil for a raw --host/--port attach.
      existing = find_session(host, port)
      return focus(existing) if existing

      # A raw --host/--port attach still has a name if lich-5 wrote a session
      # file for that host/port, and the name is what lets a dropped session
      # be found again after Lich comes back on a different port.
      character ||= character_at(host, port)

      # Attaching to a session whose tab is still open and waiting to
      # reattach brings that tab back rather than opening a second one for
      # the same character.
      dropped = find_dropped(host, port, character)
      if dropped
        reattach(dropped, host: host, port: port)
        return focus(dropped)
      end

      # The callback closes over `session`, which is still nil when the view
      # is built (the view has to exist first, since the session draws into
      # it) but is always set before the user can submit anything -- the same
      # ordering the single-session App used.
      session = nil
      view    = SessionView.new(on_command: ->(command) { session.send_command(command) }, theme: @theme)
      session = Session.new(
        host: host, port: port, character: character, view: view, origin: origin,
        on_drop: method(:handle_drop),
        autolog: @autolog, log_dir: @log_dir, prompt_char: @prompt_char
      )
      session.start

      add_tab(session, view, label: tab_name(session))
      session
    end

    # Attaches a Lich grimoire just launched (a LaunchedLich from
    # LichLauncher#launch) once its session is ready, without blocking: a
    # LaunchWatcher is checked every LAUNCH_POLL_INTERVAL on the GTK main
    # loop. The tab opens with origin :launched_headless, so a later drop
    # waits and reattaches (#handle_drop). If Lich exits first, or no
    # session appears within timeout seconds, the reason and Lich's last
    # output are shown in a dialog instead; a timed-out Lich is left
    # running, since it may still finish logging in and can be attached by
    # hand. Returns the LaunchWatcher.
    def await_launch(launched, timeout: LaunchWatcher::DEFAULT_TIMEOUT)
      watcher = LaunchWatcher.new(launched, session_dir: @session_dir, timeout: timeout, clock: @clock)
      @launch_watches[watcher] = GLib::Timeout.add(LAUNCH_POLL_INTERVAL) { poll_launch(watcher) }
      update_launch_status
      watcher
    end

    def run
      GLib::Timeout.add(ROUNDTIME_TICK_INTERVAL) do
        tick_sessions
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

    # True when this shell already holds a live session on that host/port. A
    # dropped session waiting to reattach does not count.
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
      @dropped.delete(session)
      @tab_labels.delete(session)
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

    # Every session, not just the visible tab's: a background tab's
    # countdown has to stay correct while hidden, and its view keeps
    # accepting widget writes while its notebook page is unmapped (verified
    # live for TASKS.md's "Multi-session shell" item 5).
    def tick_sessions
      @sessions.each(&:tick)
    end

    # One check of a launch being waited on. The return value is the timer's
    # own keep-running flag: false once the launch is attached or given up
    # on, which also removes the GLib source.
    def poll_launch(watcher)
      return false unless @launch_watches.key?(watcher)

      result = watcher.check
      case result.state
      when :waiting
        true
      when :ready
        attach_launched(watcher, result)
      else
        finish_launch_watch(watcher)
        heading = result.state == :exited ? 'could not be launched' : 'is taking too long to start'
        report("#{watcher.launched.character} #{heading}", result.detail)
        false
      end
    end

    # A fresh session file can still refuse a connection for a moment; the
    # next poll tries again, and the watcher's timeout still applies.
    def attach_launched(watcher, result)
      attach(host: result.host, port: result.port, character: watcher.launched.character, origin: :launched_headless)
      finish_launch_watch(watcher)
      false
    rescue Connection::ConnectError
      true
    end

    def finish_launch_watch(watcher)
      @launch_watches.delete(watcher)
      update_launch_status
    end

    def launching_characters
      @launch_watches.each_key.map { |watcher| watcher.launched.character }
    end

    # The title bar's subtitle is the one place a launch in progress shows
    # while no dialog is open -- its tab only appears once it is attached.
    def update_launch_status
      names = launching_characters
      @header.subtitle = names.empty? ? nil : "Launching #{names.join(', ')}..."
    end

    def stop_launch_watches
      @launch_watches.each_value { |source| GLib::Source.remove(source) }
      @launch_watches.clear
    end

    def find_session(host, port)
      @sessions.find { |session| !@dropped.key?(session) && session.host == host && session.port == port }
    end

    def find_dropped(host, port, character)
      @dropped.each_key.find do |session|
        character && session.character ? session.character.casecmp?(character) : session.host == host && session.port == port
      end
    end

    def character_at(host, port)
      SessionLocator.list(session_dir: @session_dir)
                    .find { |found| found.valid? && found.host == host && found.port == port }
                    &.character
    end

    # Called by a Session, on the GTK main thread, when its connection ends
    # without the user closing the tab. What happens next depends on who
    # started the Lich process behind it (Session::ORIGINS; the user's own
    # call, 2026-09-16):
    #
    # - Grimoire launched Lich with a frontend of its own: the tab closes.
    #   That Lich is not grimoire's to wait on.
    # - Otherwise (attached, or launched headless): the tab stays, with its
    #   scrollback, marked disconnected and with its command entry disabled,
    #   and is rescanned every REATTACH_SCAN_INTERVAL until it reattaches or
    #   REATTACH_TIMEOUT runs out, at which point the tab closes.
    #
    # Visible and background tabs are treated the same.
    def handle_drop(session)
      return unless @sessions.include?(session)
      return close_session(session) if session.origin == :launched_with_frontend

      @dropped[session] ||= @clock.call
      mark_connected(session, false)
      start_reattach_scan
    end

    def start_reattach_scan
      return if @reattach_scan

      @reattach_scan = GLib::Timeout.add(REATTACH_SCAN_INTERVAL) do
        scan_dropped_sessions unless @gtk_window.destroyed?
        @reattach_scan = nil if @dropped.empty? || @gtk_window.destroyed?
        !@reattach_scan.nil?
      end
    end

    def stop_reattach_scan
      GLib::Source.remove(@reattach_scan) if @reattach_scan
      @reattach_scan = nil
    end

    def scan_dropped_sessions
      now = @clock.call
      @dropped.keys.each do |session|
        next close_session(session) if now - @dropped[session] >= REATTACH_TIMEOUT

        target = reattach_target(session)
        next unless target
        # A live tab already holds it (attached by hand in the meantime).
        next if find_session(target.host, target.port)

        begin
          reattach(session, host: target.host, port: target.port)
        rescue Connection::ConnectError
          # Lich left a stale session file behind, or is not listening yet.
          # Try again on the next scan.
          nil
        end
      end
    end

    # Found by character name when there is one: lich-5 writes
    # <Name>.session afresh each time it binds and deletes it on a clean
    # exit, so a restarted Lich is found even on a different port -- which is
    # the normal case, not an edge case, for a Lich using an `auto` port
    # with --reconnect (lich-5 lib/main/detachable_client_target.rb: `auto`
    # is port 0, OS-assigned on every bind). With no name at all, the only
    # thing to try is the same host/port.
    #
    # A nameless session only happens when no session file matched its
    # host/port at attach time (see #attach), so this fallback is rare.
    def reattach_target(session)
      unless session.character
        return SessionLocator::Session.new(character: nil, host: session.host, port: session.port, error: nil)
      end

      SessionLocator.list(session_dir: @session_dir)
                    .find { |found| found.valid? && found.character.casecmp?(session.character) }
    end

    # Raises Connection::ConnectError, leaving the session still dropped.
    def reattach(session, host:, port:)
      session.reconnect(host: host, port: port)
      @dropped.delete(session)
      mark_connected(session, true)
    end

    def mark_connected(session, connected)
      @views[session].connected = connected
      @tab_labels[session].text = connected ? tab_name(session) : "#{tab_name(session)}#{DISCONNECTED_LABEL_SUFFIX}"
    end

    # The character name when one is known, falling back to host:port for a
    # raw --host/--port attach with no name to use.
    def tab_name(session)
      session.character || "#{session.host}:#{session.port}"
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

    # Tab labels come from #tab_name.
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
      @tab_labels[session] = text
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
      name = tab_name(session)
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
      @gtk_window.signal_connect('destroy') do
        # The rescan timer would otherwise outlive the window and keep
        # relabelling tabs that no longer exist.
        stop_reattach_scan
        stop_launch_watches
        Gtk.main_quit if Gtk.main_level.positive?
      end
    end

    def build_titlebar
      @header = Gtk::HeaderBar.new
      @header.title = 'grimoire'
      @header.show_close_button = true
      @header.style_context.add_class(TITLE_BAR_CSS_CLASS)
      @header
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

      connect_item = Gtk::MenuItem.new(label: 'Connect...')
      connect_item.signal_connect('activate') { prompt_for_connect }
      session_menu.append(connect_item)

      session_menu.append(Gtk::SeparatorMenuItem.new)

      quit_item = Gtk::MenuItem.new(label: 'Quit')
      quit_item.signal_connect('activate') { Gtk.main_quit }
      session_menu.append(quit_item)

      root = Gtk::MenuItem.new(label: 'Session')
      root.submenu = session_menu
      menu_bar.append(root)
      menu_bar
    end

    # Session > Connect: one dialog for both attaching and launching (the
    # user's own call, 2026-09-15). Lists every Lich favorite plus any other
    # running session (ConnectList), then acts on the chosen row. Launching
    # needs a usable lich.dir; without one the dialog says why and still
    # offers whatever is running to attach to.
    def prompt_for_connect
      favorites, notice = launchable_favorites
      rows = connect_rows(favorites)
      return report('Nothing to connect to', notice || "No Lich sessions found in #{@session_dir}") if rows.empty?

      row = ask_connect_choice(rows, notice)
      connect_row(row) if row
    end

    # [favorites, notice], where notice is nil when launching is available
    # and otherwise says why not. Checked each time the dialog opens, so
    # fixing the install does not need a restart.
    def launchable_favorites
      return [[], 'Launching is unavailable: set lich.dir in config.yml to your lich-5 directory.'] unless @install

      problem = @install.problem
      return [[], "Launching is unavailable: #{problem}"] if problem

      [@install.favorites, nil]
    rescue LichInstall::Error => e
      [[], "Launching is unavailable: #{e.message}"]
    end

    def connect_rows(favorites)
      ConnectList.build(
        favorites: favorites, sessions: SessionLocator.list(session_dir: @session_dir),
        attached: method(:attached?), launching: launching_characters
      )
    end

    def connect_row(row)
      case row.status
      when :attached then focus(find_session(row.session.host, row.session.port))
      when :running then attach_row(row)
      when :not_running then launch_row(row)
      end
    end

    def attach_row(row)
      attach(host: row.session.host, port: row.session.port, character: row.session.character)
    rescue Connection::ConnectError => e
      report("Could not attach to #{row.character}", e.message)
    end

    # Checks the account first: launching a second character on an account
    # logs the first one out (AccountGuard), which is sometimes exactly the
    # point, so it asks rather than refusing.
    def launch_row(row)
      return unless row.entry && @launcher

      sessions = SessionLocator.list(session_dir: @session_dir)
      siblings = AccountGuard.running_siblings(row.entry, entries: @install.entries, sessions: sessions)
      return if siblings.any? && !confirm_launch_anyway(row.entry, siblings)

      await_launch(@launcher.launch(row.entry))
    rescue LichLauncher::Error, LichInstall::Error => e
      report("Could not launch #{row.character}", e.message)
    end

    # Names the other characters but not the account: entry.yaml's account
    # names stay a grouping key only. The --reconnect caveat is there because
    # a session file does not say how Lich was started, and a Lich run with
    # --reconnect logs straight back in, logging the new character out
    # instead (observed live by the user, 2026-09-16).
    def confirm_launch_anyway(entry, siblings)
      names  = siblings.map(&:char_name).join(', ')
      dialog = Gtk::MessageDialog.new(
        parent: @gtk_window, flags: :modal, type: :warning, buttons: Gtk::ButtonsType::NONE,
        message: "Already logged in on the same account: #{names}"
      )
      dialog.secondary_text =
        "An account allows one character logged in per game at a time. Launching #{entry.char_name} will log #{names} out. " \
        "If that Lich was started with --reconnect, it will log back in and log #{entry.char_name} out instead."
      dialog.add_button(Gtk::Stock::CANCEL, Gtk::ResponseType::CANCEL)
      dialog.add_button('Launch anyway', Gtk::ResponseType::OK)
      response = dialog.run
      dialog.destroy
      response == Gtk::ResponseType::OK
    end

    # Shows the dialog and returns the chosen ConnectList::Row, or nil.
    def ask_connect_choice(rows, notice)
      dialog, tree = build_connect_dialog(rows, notice)
      response = dialog.run
      index    = selected_index(tree)
      dialog.destroy
      response == Gtk::ResponseType::OK && index ? rows[index] : nil
    end

    # Built separately from #ask_connect_choice so specs can inspect it
    # without running it. Connect is only enabled on a row it can act on,
    # and double-clicking such a row connects straight away.
    def build_connect_dialog(rows, notice)
      dialog = Gtk::Dialog.new(title: 'Connect', parent: @gtk_window, flags: :modal)
      dialog.set_default_size(CONNECT_DIALOG_WIDTH, CONNECT_DIALOG_HEIGHT)
      dialog.add_button(Gtk::Stock::CANCEL, Gtk::ResponseType::CANCEL)
      connect = dialog.add_button('Connect', Gtk::ResponseType::OK)

      store = Gtk::ListStore.new(String, String, String)
      rows.each do |row|
        iter = store.append
        iter[0] = row.character
        iter[1] = row.game.to_s
        iter[2] = CONNECT_STATUS_TEXT.fetch(row.status)
      end

      tree = Gtk::TreeView.new(store)
      %w[Character Game Status].each_with_index do |title, column|
        tree.append_column(Gtk::TreeViewColumn.new(title, Gtk::CellRendererText.new, text: column))
      end
      tree.selection.signal_connect('changed') do
        index = selected_index(tree)
        connect.sensitive = !index.nil? && connectable?(rows[index])
      end
      tree.signal_connect('row-activated') do |_tree, path|
        dialog.response(Gtk::ResponseType::OK) if connectable?(rows[path.indices.first])
      end

      scroller = Gtk::ScrolledWindow.new
      scroller.set_policy(:never, :automatic)
      scroller.add(tree)

      if notice
        label = Gtk::Label.new(notice)
        label.wrap = true
        label.xalign = 0
        dialog.child.pack_start(label, expand: false, fill: false, padding: DIALOG_PADDING)
      end
      dialog.child.pack_start(scroller, expand: true, fill: true, padding: DIALOG_PADDING)

      connect.sensitive = false
      first = rows.index { |row| connectable?(row) }
      tree.selection.select_path(Gtk::TreePath.new(first.to_s)) if first
      dialog.show_all
      [dialog, tree]
    end

    def selected_index(tree)
      tree.selection.selected&.path&.indices&.first
    end

    # A launch already in progress has nothing to do yet, and a row with no
    # session can only be launched by a favorite with a usable launcher.
    def connectable?(row)
      case row.status
      when :attached, :running then true
      when :not_running then !row.entry.nil? && !@launcher.nil?
      else false
      end
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
