require 'spec_helper'

require 'json'
require 'tmpdir'

RSpec.describe Grimoire::Shell do
  # An empty session directory of its own, so no example ever reads the
  # real lich-5 session files on the machine running the suite. The clock
  # is a plain number an example can move forward.
  let(:session_dir) { Dir.mktmpdir }
  let(:now) { [1000.0] }

  let(:lich_dir) { nil }

  subject(:shell) { described_class.new(session_dir: session_dir, clock: -> { now.first }, lich_dir: lich_dir) }

  def pump_gtk_events
    Gtk.main_iteration while Gtk.events_pending?
  end

  # Every #attach starts a Connection read thread and a CommandQueue thread.
  # Left running past the example they keep a socket open and keep scheduling
  # GTK work through GLib::Idle.add, which made the suite segfault
  # intermittently once several sessions could exist at once.
  after do
    shell.sessions.each(&:stop)
    pump_gtk_events
    shell.to_gtk.destroy unless shell.to_gtk.destroyed?
    pump_gtk_events
    FileUtils.remove_entry(session_dir)
  end

  def notebook(shell)
    shell.instance_variable_get(:@notebook)
  end

  def stack(shell)
    shell.instance_variable_get(:@stack)
  end

  # A tab label is a Gtk::Box holding the name plus its own close button, so
  # the text lives one level in.
  def tab_text(shell, index)
    page = notebook(shell).get_nth_page(index)
    notebook(shell).get_tab_label(page).children.first.text
  end

  def tab_close_button(shell, index)
    page = notebook(shell).get_nth_page(index)
    notebook(shell).get_tab_label(page).children.last
  end

  # Gtk::Stack does not report a visible child until it has been realized,
  # and #run's real sequence is show_all first, then pick the page -- so a
  # spec asserting on which page shows has to realize the shell the same way.
  def visible_page(shell)
    shell.to_gtk.show_all
    pump_gtk_events
    shell.send(:show_relevant_page)
    stack(shell).visible_child_name
  end

  # Shell#attach opens a real socket, so every attach-based example needs
  # something listening. A fake Lich that accepts, reads the identify line and
  # then stays quiet is enough -- nothing here asserts on wire traffic.
  def with_fake_lich
    server = TCPServer.new('127.0.0.1', 0)
    accepted = Thread.new do
      client = server.accept
      client.gets
      sleep 5
    rescue StandardError
      nil
    end
    yield server.addr[1]
  ensure
    accepted&.kill
    server&.close
  end

  # Like #with_fake_lich, but hands the example a way to end the connection
  # from the Lich side, the way a crashed or restarted Lich would.
  def with_droppable_lich
    server = TCPServer.new('127.0.0.1', 0)
    client = Queue.new
    accepted = Thread.new do
      client << server.accept
      sleep 5
    rescue StandardError
      nil
    end
    yield server.addr[1], -> { client.pop.close }
  ensure
    accepted&.kill
    server&.close
  end

  def closed_port
    server = TCPServer.new('127.0.0.1', 0)
    server.addr[1].tap { server.close }
  end

  def write_session_file(character, port)
    File.write(File.join(session_dir, "#{character}.session"),
               { 'name' => character, 'host' => '127.0.0.1', 'port' => port }.to_json)
  end

  def dropped(shell)
    shell.instance_variable_get(:@dropped)
  end

  def entry_sensitive?(shell, session)
    shell.instance_variable_get(:@views)[session].instance_variable_get(:@entry).sensitive?
  end

  describe 'blank start' do
    # The whole point of the shell: the window exists before, and without,
    # any character being connected. A per-character class could not own this.
    it 'builds a top-level window with no sessions attached' do
      expect(shell.to_gtk).to be_a(Gtk::Window)
      expect(shell.sessions).to be_empty
    end

    it 'opens no notebook pages until something is attached' do
      expect(notebook(shell).n_pages).to eq(0)
    end

    it 'shows the empty-state page rather than the notebook while blank' do
      expect(visible_page(shell)).to eq('empty')
    end
  end

  describe 'window chrome' do
    # Moved here from the view's spec when the chrome moved to Shell -- the
    # view builds no window of its own any more.
    it 'installs a themed Gtk::HeaderBar as the window titlebar' do
      titlebar = shell.to_gtk.titlebar

      expect(titlebar).to be_a(Gtk::HeaderBar)
      expect(titlebar.style_context.has_class?('grimoire-titlebar')).to be(true)
    end

    it 'tags the top-level window with its own CSS class' do
      expect(shell.to_gtk.style_context.has_class?('grimoire-window')).to be(true)
    end

    it 'defaults the title bar CSS to a dark charcoal bg, white fg' do
      css = shell.send(:title_bar_css)

      expect(css).to include('background-color: rgb(26, 26, 26)')
      expect(css).to include('color: rgb(255, 255, 255)')
    end

    # Adwaita's own headerbar stylesheet carries a subtle inset highlight
    # (box-shadow) plus a bottom border-color for the separator against the
    # rest of the window -- left unreset, both rendered as a stray 1px light
    # line above and below the bar regardless of the theme's own colors,
    # reported live (2026-09-13).
    it 'resets the headerbar box-shadow/border so no stray line shows above/below it' do
      css = shell.send(:title_bar_css)

      expect(css).to include('box-shadow: none')
      expect(css).to include('border-style: none')
    end

    it 'renders a custom title bar theme into the title-bar CSS' do
      theme = Grimoire::Theme::DEFAULT.with(
        title_bar_bg: Grimoire::Color.new(red: 30, green: 30, blue: 30),
        title_bar_fg: Grimoire::Color.new(red: 220, green: 220, blue: 220)
      )

      css = described_class.new(theme: theme).send(:title_bar_css)

      expect(css).to include('background-color: rgb(30, 30, 30)')
      expect(css).to include('color: rgb(220, 220, 220)')
    end

    it 'defaults the window (padding_bg) CSS to its own dark charcoal background' do
      expect(shell.send(:window_css)).to include('background-color: rgb(34, 34, 34)')
    end

    it 'renders a custom padding_bg into the window CSS' do
      theme = Grimoire::Theme::DEFAULT.with(padding_bg: Grimoire::Color.new(red: 40, green: 50, blue: 60))

      expect(described_class.new(theme: theme).send(:window_css)).to include('background-color: rgb(40, 50, 60)')
    end
  end

  describe 'menu bar' do
    def menu_items(shell)
      root = shell.send(:build_menu_bar).children.first
      root.submenu.children
    end

    # One Connect item for attaching and launching alike (the user's own
    # call, 2026-09-15), replacing the separate attach item and the inert
    # launch stub.
    it 'offers Connect and Quit, both enabled' do
      items  = menu_items(shell).reject { |item| item.is_a?(Gtk::SeparatorMenuItem) }
      labels = items.map(&:label)

      expect(labels).to eq(['Connect...', 'Quit'])
      expect(items).to all(be_sensitive)
    end
  end

  describe 'the blank-state backdrop' do
    # Artwork was layered over this briefly (2026-09-15) and then removed at
    # the user's request -- plain black for now.
    it 'paints black behind everything' do
      expect(described_class::EMPTY_BACKGROUND_COLOR).to eq([0.0, 0.0, 0.0])
    end

    it 'draws through a Gtk::DrawingArea so it fills the window at any size' do
      expect(shell.send(:build_empty_state)).to be_a(Gtk::DrawingArea)
    end

    # Nothing about the blank state depends on a file on disk any more.
    it 'needs no image asset at all' do
      expect(described_class.constants).not_to include(:EMPTY_BACKGROUND_IMAGE)
      expect(shell.private_methods).not_to include(:load_empty_background)
    end
  end

  describe '#attach' do
    it 'opens a tab per attached character and tracks the session' do
      with_fake_lich do |port|
        session = shell.attach(host: '127.0.0.1', port: port, character: 'Sparrow')

        expect(session.character).to eq('Sparrow')
        expect(shell.sessions).to eq([session])
        expect(notebook(shell).n_pages).to eq(1)
      end
    end

    it 'labels the tab with the character name' do
      with_fake_lich do |port|
        shell.attach(host: '127.0.0.1', port: port, character: 'Sparrow')

        expect(tab_text(shell, 0)).to eq('Sparrow')
      end
    end

    # A raw --host/--port attach has no name to use, so the tab falls back to
    # something that still identifies which connection it is.
    it 'falls back to host:port for a tab with no character name' do
      with_fake_lich do |port|
        shell.attach(host: '127.0.0.1', port: port)

        expect(tab_text(shell, 0)).to eq("127.0.0.1:#{port}")
      end
    end

    it 'swaps from the blank backdrop to the notebook once a session exists' do
      with_fake_lich do |port|
        shell.attach(host: '127.0.0.1', port: port, character: 'Sparrow')

        expect(visible_page(shell)).to eq('sessions')
      end
    end

    it 'holds several characters at once, each in its own tab' do
      with_fake_lich do |first_port|
        with_fake_lich do |second_port|
          shell.attach(host: '127.0.0.1', port: first_port, character: 'Sparrow')
          shell.attach(host: '127.0.0.1', port: second_port, character: 'Wren')

          expect(shell.sessions.map(&:character)).to eq(%w[Sparrow Wren])
          expect(notebook(shell).n_pages).to eq(2)
        end
      end
    end

    # Each session draws into its own view, so a line arriving for one
    # character must never land in another's scrollback.
    it 'keeps each tab\'s scrollback separate' do
      with_fake_lich do |first_port|
        with_fake_lich do |second_port|
          first  = shell.attach(host: '127.0.0.1', port: first_port, character: 'Sparrow')
          second = shell.attach(host: '127.0.0.1', port: second_port, character: 'Wren')

          first.send(:handle_line, "Sparrow sees a sparrow.\r\n")
          second.send(:handle_line, "Wren sees a wren.\r\n")
          pump_gtk_events

          expect(view_text(first)).to include('Sparrow sees a sparrow.')
          expect(view_text(first)).not_to include('wren')
          expect(view_text(second)).to include('Wren sees a wren.')
          expect(view_text(second)).not_to include('sparrow')
        end
      end
    end

    # TASKS.md's "Multi-session shell" item 5: a session keeps running while
    # its tab is not the visible one -- its view still takes writes even
    # though GTK has unmapped that notebook page.
    it 'keeps delivering lines to a tab that is not the visible one' do
      with_fake_lich do |first_port|
        with_fake_lich do |second_port|
          shell.attach(host: '127.0.0.1', port: first_port, character: 'Sparrow')
          background = shell.attach(host: '127.0.0.1', port: second_port, character: 'Wren')
          notebook(shell).page = 0

          background.send(:handle_line, "A wren sings out of sight.\r\n")
          pump_gtk_events

          expect(notebook(shell).current_page).to eq(0)
          expect(view_text(background)).to include('A wren sings out of sight.')
        end
      end
    end

    it 'ticks every session\'s countdown, not only the visible tab\'s' do
      with_fake_lich do |first_port|
        with_fake_lich do |second_port|
          visible    = shell.attach(host: '127.0.0.1', port: first_port, character: 'Sparrow')
          background = shell.attach(host: '127.0.0.1', port: second_port, character: 'Wren')
          notebook(shell).page = 0
          allow(visible).to receive(:tick)
          allow(background).to receive(:tick)

          shell.send(:tick_sessions)

          expect(visible).to have_received(:tick)
          expect(background).to have_received(:tick)
        end
      end
    end

    # Reported live (2026-09-15): the attach dialog offered sessions that were
    # already open in a tab, and a second Connection to the same frontend port
    # would have both sockets racing one Lich session.
    it 'focuses the existing tab instead of opening a second one for the same session' do
      with_fake_lich do |port|
        first = shell.attach(host: '127.0.0.1', port: port, character: 'Sparrow')
        again = shell.attach(host: '127.0.0.1', port: port, character: 'Sparrow')

        expect(again).to be(first)
        expect(shell.sessions.length).to eq(1)
        expect(notebook(shell).n_pages).to eq(1)
      end
    end

    # Reported live (2026-09-16): a new session opened with focus in the
    # scrollback, so typing did nothing until the entry was clicked.
    describe 'command entry focus' do
      def entry_of(shell, session)
        shell.instance_variable_get(:@views)[session].instance_variable_get(:@entry)
      end

      it 'focuses the command entry of a newly attached session' do
        with_fake_lich do |port|
          session = shell.attach(host: '127.0.0.1', port: port, character: 'Sparrow')
          shell.to_gtk.show_all
          pump_gtk_events

          expect(shell.to_gtk.focus).to be(entry_of(shell, session))
        end
      end

      it 'moves focus to the new tab\'s entry when a second session is attached' do
        with_fake_lich do |first_port|
          with_fake_lich do |second_port|
            shell.attach(host: '127.0.0.1', port: first_port, character: 'Sparrow')
            second = shell.attach(host: '127.0.0.1', port: second_port, character: 'Wren')

            expect(shell.to_gtk.focus).to be(entry_of(shell, second))
          end
        end
      end

      it 'follows the user switching tabs into that tab\'s entry' do
        with_fake_lich do |first_port|
          with_fake_lich do |second_port|
            first = shell.attach(host: '127.0.0.1', port: first_port, character: 'Sparrow')
            shell.attach(host: '127.0.0.1', port: second_port, character: 'Wren')
            shell.to_gtk.show_all
            pump_gtk_events

            notebook(shell).page = 0
            pump_gtk_events

            expect(shell.to_gtk.focus).to be(entry_of(shell, first))
          end
        end
      end

      # Reported live (2026-09-16): a mouse click on a tab left focus on the
      # tab. GTK's tab button-press handler switches the page and *then*
      # grabs focus onto the notebook (and on into the scrollback), all in
      # the same turn -- reproduced here with a grab straight after the
      # switch, since a real click cannot be synthesized under the suite.
      it 'still lands in the entry when the notebook grabs focus right after a tab switch' do
        with_fake_lich do |first_port|
          with_fake_lich do |second_port|
            first = shell.attach(host: '127.0.0.1', port: first_port, character: 'Sparrow')
            shell.attach(host: '127.0.0.1', port: second_port, character: 'Wren')
            shell.to_gtk.show_all
            pump_gtk_events

            notebook(shell).page = 0
            notebook(shell).grab_focus
            pump_gtk_events

            expect(shell.to_gtk.focus).to be(entry_of(shell, first))
          end
        end
      end

      it 'refocuses the existing tab\'s entry on a duplicate attach' do
        with_fake_lich do |first_port|
          with_fake_lich do |second_port|
            first = shell.attach(host: '127.0.0.1', port: first_port, character: 'Sparrow')
            shell.attach(host: '127.0.0.1', port: second_port, character: 'Wren')

            shell.attach(host: '127.0.0.1', port: first_port, character: 'Sparrow')

            expect(shell.to_gtk.focus).to be(entry_of(shell, first))
          end
        end
      end

      it 'focuses the remaining tab\'s entry after another tab is closed' do
        with_fake_lich do |first_port|
          with_fake_lich do |second_port|
            first  = shell.attach(host: '127.0.0.1', port: first_port, character: 'Sparrow')
            second = shell.attach(host: '127.0.0.1', port: second_port, character: 'Wren')
            shell.to_gtk.show_all
            pump_gtk_events

            shell.close_session(second)

            expect(shell.to_gtk.focus).to be(entry_of(shell, first))
          end
        end
      end
    end

    it 'reports an already-attached session through #attached?' do
      with_fake_lich do |port|
        expect(shell.attached?('127.0.0.1', port)).to be(false)

        shell.attach(host: '127.0.0.1', port: port, character: 'Sparrow')

        expect(shell.attached?('127.0.0.1', port)).to be(true)
      end
    end

    # Identity is host/port, not the character name -- a raw --host/--port
    # attach has no name at all, so two nameless sessions on different ports
    # must not look like the same one.
    it 'treats different ports as different sessions even with no character name' do
      with_fake_lich do |first_port|
        with_fake_lich do |second_port|
          shell.attach(host: '127.0.0.1', port: first_port)
          shell.attach(host: '127.0.0.1', port: second_port)

          expect(notebook(shell).n_pages).to eq(2)
        end
      end
    end

    # Deliberately raises rather than reporting: what should happen depends on
    # who asked. Launch-time retries and exits, the menu shows a dialog.
    it 'lets a connection failure propagate to the caller' do
      expect { shell.attach(host: '127.0.0.1', port: 1, character: 'Nobody') }
        .to raise_error(Grimoire::Connection::ConnectError)
    end

    it 'opens no tab for a failed attach' do
      begin
        shell.attach(host: '127.0.0.1', port: 1, character: 'Nobody')
      rescue Grimoire::Connection::ConnectError
        nil
      end

      expect(notebook(shell).n_pages).to eq(0)
      expect(visible_page(shell)).to eq('empty')
    end
  end

  describe 'closing a session' do
    # Reported live (2026-09-15): a session could only be ended by quitting
    # grimoire entirely.
    it 'disconnects the session and removes its tab' do
      with_fake_lich do |port|
        session = shell.attach(host: '127.0.0.1', port: port, character: 'Sparrow')

        shell.close_session(session)

        expect(shell.sessions).to be_empty
        expect(notebook(shell).n_pages).to eq(0)
      end
    end

    it 'falls back to the blank backdrop once the last tab closes' do
      with_fake_lich do |port|
        session = shell.attach(host: '127.0.0.1', port: port, character: 'Sparrow')

        shell.close_session(session)

        expect(visible_page(shell)).to eq('empty')
      end
    end

    it 'closes only the session asked for, leaving the others attached' do
      with_fake_lich do |first_port|
        with_fake_lich do |second_port|
          first  = shell.attach(host: '127.0.0.1', port: first_port, character: 'Sparrow')
          second = shell.attach(host: '127.0.0.1', port: second_port, character: 'Wren')

          shell.close_session(first)

          expect(shell.sessions).to eq([second])
          expect(tab_text(shell, 0)).to eq('Wren')
        end
      end
    end

    it 'frees the host/port so the same session can be attached again afterwards' do
      with_fake_lich do |port|
        session = shell.attach(host: '127.0.0.1', port: port, character: 'Sparrow')
        shell.close_session(session)

        expect(shell.attached?('127.0.0.1', port)).to be(false)
      end
    end

    it 'ignores a session it does not hold' do
      with_fake_lich do |port|
        other = shell.attach(host: '127.0.0.1', port: port, character: 'Sparrow')
        shell.close_session(other)

        expect { shell.close_session(other) }.not_to raise_error
      end
    end

    # Reported live (2026-09-15) as a stream of Gtk/Gdk CRITICAL assertions
    # on tab close: removing the page unrealizes the widgets, and the view's
    # scroll handlers were still connected, so the adjustment went on firing
    # into a GdkWindow that no longer existed. Confirmed by reproduction:
    # 5 assertions without the teardown call, 0 with it.
    it 'disconnects the view\'s scroll handlers before removing its page' do
      with_fake_lich do |port|
        session = shell.attach(host: '127.0.0.1', port: port, character: 'Sparrow')
        view    = shell.instance_variable_get(:@views)[session]

        shell.close_session(session)

        expect(view.instance_variable_get(:@scroll_changed_handler)).to be_nil
        expect(view.instance_variable_get(:@scrollbar_change_handler)).to be_nil
      end
    end

    it 'stops tracking the view once its tab is closed' do
      with_fake_lich do |port|
        session = shell.attach(host: '127.0.0.1', port: port, character: 'Sparrow')

        shell.close_session(session)

        expect(shell.instance_variable_get(:@views)).to be_empty
      end
    end

    it 'gives every tab its own close button' do
      with_fake_lich do |port|
        shell.attach(host: '127.0.0.1', port: port, character: 'Sparrow')

        expect(tab_close_button(shell, 0)).to be_a(Gtk::Button)
        expect(tab_close_button(shell, 0).tooltip_text).to eq('Close session')
      end
    end
  end

  # TASKS.md's "Multi-session shell" item 7 (the user's own call,
  # 2026-09-16): what a tab does when its Lich connection drops depends on
  # who started that Lich.
  describe 'a dropped session' do
    it 'names a raw host/port attach from the lich-5 session file on that port' do
      with_fake_lich do |port|
        write_session_file('Sparrow', port)

        session = shell.attach(host: '127.0.0.1', port: port)

        expect(session.character).to eq('Sparrow')
        expect(tab_text(shell, 0)).to eq('Sparrow')
      end
    end

    it 'keeps the tab, marks it disconnected and disables its command entry' do
      with_droppable_lich do |port, drop|
        session = shell.attach(host: '127.0.0.1', port: port, character: 'Sparrow')

        drop.call
        deadline = Time.now + 2
        pump_gtk_events until dropped(shell).key?(session) || Time.now > deadline

        expect(notebook(shell).n_pages).to eq(1)
        expect(tab_text(shell, 0)).to eq('Sparrow (disconnected)')
        expect(entry_sensitive?(shell, session)).to be(false)
        expect(view_text(session)).to include('[disconnected:')
      end
    end

    it 'treats a session grimoire launched headless the same way' do
      with_fake_lich do |port|
        session = shell.attach(host: '127.0.0.1', port: port, character: 'Sparrow', origin: :launched_headless)

        shell.send(:handle_drop, session)

        expect(shell.sessions).to eq([session])
        expect(tab_text(shell, 0)).to eq('Sparrow (disconnected)')
      end
    end

    it 'closes the tab straight away for a Lich grimoire launched with its own frontend' do
      with_fake_lich do |port|
        session = shell.attach(host: '127.0.0.1', port: port, character: 'Sparrow', origin: :launched_with_frontend)

        shell.send(:handle_drop, session)

        expect(shell.sessions).to be_empty
        expect(notebook(shell).n_pages).to eq(0)
      end
    end

    it 'ignores a drop reported for a tab that was already closed' do
      with_fake_lich do |port|
        session = shell.attach(host: '127.0.0.1', port: port, character: 'Sparrow')
        shell.close_session(session)

        expect { shell.send(:handle_drop, session) }.not_to raise_error
        expect(dropped(shell)).to be_empty
      end
    end

    it 'no longer counts as attached, so the Connect dialog offers it again' do
      with_fake_lich do |port|
        session = shell.attach(host: '127.0.0.1', port: port, character: 'Sparrow')

        shell.send(:handle_drop, session)

        expect(shell.attached?('127.0.0.1', port)).to be(false)
      end
    end

    # lich-5 rewrites <Name>.session each time it starts, so a restarted Lich
    # is found by name even when it comes back on a different port.
    it 'reattaches in place when the character\'s session file reappears on a new port' do
      with_fake_lich do |old_port|
        with_fake_lich do |new_port|
          session = shell.attach(host: '127.0.0.1', port: old_port, character: 'Sparrow')
          shell.send(:handle_drop, session)
          write_session_file('Sparrow', new_port)

          shell.send(:scan_dropped_sessions)

          expect(session.port).to eq(new_port)
          expect(dropped(shell)).to be_empty
          expect(shell.sessions).to eq([session])
          expect(tab_text(shell, 0)).to eq('Sparrow')
          expect(entry_sensitive?(shell, session)).to be(true)
        end
      end
    end

    it 'matches the session file by name regardless of case' do
      with_fake_lich do |old_port|
        with_fake_lich do |new_port|
          session = shell.attach(host: '127.0.0.1', port: old_port, character: 'sparrow')
          shell.send(:handle_drop, session)
          write_session_file('Sparrow', new_port)

          shell.send(:scan_dropped_sessions)

          expect(session.port).to eq(new_port)
        end
      end
    end

    it 'keeps waiting while there is no session file for the character' do
      with_fake_lich do |port|
        session = shell.attach(host: '127.0.0.1', port: port, character: 'Sparrow')
        shell.send(:handle_drop, session)

        shell.send(:scan_dropped_sessions)

        expect(dropped(shell)).to have_key(session)
      end
    end

    # A crashed Lich can leave its session file behind.
    it 'keeps waiting when the session file points at nothing listening' do
      with_fake_lich do |port|
        session = shell.attach(host: '127.0.0.1', port: port, character: 'Sparrow')
        shell.send(:handle_drop, session)
        write_session_file('Sparrow', closed_port)

        expect { shell.send(:scan_dropped_sessions) }.not_to raise_error
        expect(dropped(shell)).to have_key(session)
        expect(session.port).to eq(port)
      end
    end

    it 'retries the same host/port for a session with no name to look up' do
      with_fake_lich do |port|
        session = shell.attach(host: '127.0.0.1', port: port)
        shell.send(:handle_drop, session)

        shell.send(:scan_dropped_sessions)

        expect(dropped(shell)).to be_empty
        expect(session.connected?).to be(true)
      end
    end

    it 'closes the tab once it has been down for the reattach timeout' do
      with_fake_lich do |port|
        session = shell.attach(host: '127.0.0.1', port: port, character: 'Sparrow')
        shell.send(:handle_drop, session)

        now[0] += described_class::REATTACH_TIMEOUT - 1
        shell.send(:scan_dropped_sessions)
        expect(shell.sessions).to eq([session])

        now[0] += 1
        shell.send(:scan_dropped_sessions)
        expect(shell.sessions).to be_empty
        expect(dropped(shell)).to be_empty
      end
    end

    it 'waits about five minutes, rescanning every five seconds' do
      expect(described_class::REATTACH_TIMEOUT).to eq(300)
      expect(described_class::REATTACH_SCAN_INTERVAL).to eq(5000)
    end

    it 'brings the dropped tab back when the same character is attached by hand' do
      with_fake_lich do |old_port|
        with_fake_lich do |new_port|
          session = shell.attach(host: '127.0.0.1', port: old_port, character: 'Sparrow')
          shell.send(:handle_drop, session)

          again = shell.attach(host: '127.0.0.1', port: new_port, character: 'Sparrow')

          expect(again).to be(session)
          expect(notebook(shell).n_pages).to eq(1)
          expect(session.port).to eq(new_port)
          expect(dropped(shell)).to be_empty
        end
      end
    end

    it 'runs one rescan timer while anything is dropped, and stops it with the window' do
      with_fake_lich do |port|
        session = shell.attach(host: '127.0.0.1', port: port, character: 'Sparrow')
        shell.send(:handle_drop, session)
        timer = shell.instance_variable_get(:@reattach_scan)
        shell.send(:handle_drop, session)

        expect(timer).not_to be_nil
        expect(shell.instance_variable_get(:@reattach_scan)).to eq(timer)

        shell.to_gtk.destroy
        expect(shell.instance_variable_get(:@reattach_scan)).to be_nil
      end
    end
  end

  describe 'awaiting a launched Lich' do
    def launched(character: 'Sparrow', exit_status: nil)
      instance_double(
        Grimoire::LaunchedLich,
        character: character, started_at: Time.now - 1, running?: exit_status.nil?, exit_status: exit_status,
        log_path: '/logs/lich.log', output_tail: "bad password\n"
      )
    end

    def watches(shell)
      shell.instance_variable_get(:@launch_watches)
    end

    it 'polls on a timer and does nothing while the session is not ready' do
      watcher = shell.await_launch(launched)

      expect(watches(shell)).to have_key(watcher)
      expect(shell.send(:poll_launch, watcher)).to be(true)
      expect(shell.sessions).to be_empty
    end

    it 'attaches as a headless launch once the session file appears, then stops polling' do
      with_fake_lich do |port|
        watcher = shell.await_launch(launched)
        write_session_file('Sparrow', port)

        expect(shell.send(:poll_launch, watcher)).to be(false)

        session = shell.sessions.first
        expect([session.character, session.port, session.origin]).to eq(['Sparrow', port, :launched_headless])
        expect(tab_text(shell, 0)).to eq('Sparrow')
        expect(watches(shell)).to be_empty
      end
    end

    it 'keeps polling when the session file names a port that refuses the connection' do
      watcher = shell.await_launch(launched)
      write_session_file('Sparrow', closed_port)

      expect(shell.send(:poll_launch, watcher)).to be(true)
      expect(shell.sessions).to be_empty
      expect(watches(shell)).to have_key(watcher)
    end

    it 'reports a Lich that exited before its session was ready, with its output' do
      allow(shell).to receive(:report)
      watcher = shell.await_launch(launched(exit_status: instance_double(Process::Status, exitstatus: 1, termsig: nil)))

      expect(shell.send(:poll_launch, watcher)).to be(false)
      expect(shell).to have_received(:report).with('Sparrow could not be launched', /status 1.*bad password/m)
      expect(watches(shell)).to be_empty
    end

    it 'reports a launch that times out' do
      allow(shell).to receive(:report)
      watcher = shell.await_launch(launched, timeout: 60)
      now[0] += 60

      expect(shell.send(:poll_launch, watcher)).to be(false)
      expect(shell).to have_received(:report).with('Sparrow is taking too long to start', /still running/)
    end

    it 'removes every poll timer with the window' do
      shell.await_launch(launched)
      shell.await_launch(launched(character: 'Wren'))

      shell.to_gtk.destroy

      expect(watches(shell)).to be_empty
    end

    # End to end on the real timer: a real LichLauncher starts a fake
    # lich.rbw that does what lich-5 does on --headless auto -- bind an
    # OS-assigned port, write <Name>.session, accept a frontend.
    it 'launches, waits for the session file and attaches without blocking the main loop' do
      Dir.mktmpdir do |lich_dir|
        FileUtils.mkdir_p(File.join(lich_dir, 'data'))
        File.write(File.join(lich_dir, 'data', 'entry.yaml'), "accounts: {}\n")
        File.write(File.join(lich_dir, 'lich.rbw'), <<~RUBY)
          require 'json'
          require 'socket'
          sleep 1
          server = TCPServer.new('127.0.0.1', 0)
          name = ARGV[ARGV.index('--login') + 1].capitalize
          File.write(File.join(#{session_dir.inspect}, "\#{name}.session"),
                     { name: name, host: '127.0.0.1', port: server.addr[1] }.to_json)
          client = server.accept
          client.gets
          sleep 30
        RUBY

        install  = Grimoire::LichInstall.new(lich_dir)
        launcher = Grimoire::LichLauncher.new(install: install, log_dir: File.join(lich_dir, 'logs'))
        entry    = Grimoire::LichInstall::Entry.new(user_id: 'ALPHA', char_name: 'Sparrow', game_code: 'GS3',
                                                    game_name: nil, favorite: true, favorite_order: nil)
        process  = launcher.launch(entry)

        begin
          shell.await_launch(process)
          deadline = Time.now + 15
          until shell.sessions.any? || Time.now > deadline
            pump_gtk_events
            sleep 0.02
          end

          expect(shell.sessions.map(&:character)).to eq(['Sparrow'])
          expect(shell.sessions.first.origin).to eq(:launched_headless)
          expect(watches(shell)).to be_empty
        ensure
          process.stop
          process.wait(5)
        end
      end
    end
  end

  describe 'the Connect dialog' do
    def favorite(char_name, user_id: 'ALPHA')
      Grimoire::LichInstall::Entry.new(user_id: user_id, char_name: char_name, game_code: 'GS3',
                                       game_name: 'GemStone IV', favorite: true, favorite_order: nil)
    end

    def row(status, character: 'Sparrow', port: nil, entry: favorite(character))
      session = port && Grimoire::SessionLocator::Session.new(character: character, host: '127.0.0.1', port: port, error: nil)
      Grimoire::ConnectList::Row.new(character: character, game: 'GemStone IV', status: status, entry: entry, session: session)
    end

    def write_install(dir, entry_yaml)
      FileUtils.mkdir_p(File.join(dir, 'data'))
      File.write(File.join(dir, 'lich.rbw'), "# stand-in\n")
      File.write(File.join(dir, 'data', 'entry.yaml'), entry_yaml)
    end

    def launcher(shell)
      shell.instance_variable_get(:@launcher)
    end

    describe 'launch availability' do
      it 'explains that lich.dir is needed when it is not set' do
        favorites, notice = shell.send(:launchable_favorites)

        expect(favorites).to eq([])
        expect(notice).to include('set lich.dir')
      end

      context 'with a lich.dir that is not a lich-5 install' do
        let(:lich_dir) { Dir.mktmpdir }

        after { FileUtils.remove_entry(lich_dir) }

        it 'passes on what is missing' do
          expect(shell.send(:launchable_favorites).last).to match(/Launching is unavailable: .*lich\.rbw: not found/)
        end
      end

      context 'with a usable lich-5 install' do
        let(:lich_dir) do
          Dir.mktmpdir.tap { |dir| write_install(dir, File.read(File.join(FixtureHelpers::FIXTURE_DIR, 'entry.yaml'))) }
        end

        after { FileUtils.remove_entry(lich_dir) }

        it 'offers its favorites with no notice' do
          favorites, notice = shell.send(:launchable_favorites)

          expect(favorites.map(&:char_name)).to eq(%w[Morrow Zephyr Zephyr Aldous])
          expect(notice).to be_nil
        end

        it 'lists favorites and marks the running ones' do
          write_session_file('Morrow', 4100)

          rows = shell.send(:connect_rows, shell.send(:launchable_favorites).first)

          expect(rows.map { |r| [r.character, r.status] }.first(2)).to eq([['Morrow', :running], ['Zephyr', :not_running]])
        end
      end
    end

    describe '#prompt_for_connect' do
      it 'reports why there is nothing to connect to, instead of an empty dialog' do
        allow(shell).to receive(:report)

        shell.send(:prompt_for_connect)

        expect(shell).to have_received(:report).with('Nothing to connect to', /set lich\.dir/)
      end

      it 'acts on the row chosen in the dialog' do
        with_fake_lich do |port|
          write_session_file('Sparrow', port)
          allow(shell).to receive(:ask_connect_choice) { |rows, _notice| rows.first }

          shell.send(:prompt_for_connect)

          expect(shell.sessions.map(&:character)).to eq(['Sparrow'])
        end
      end

      it 'does nothing when the dialog is cancelled' do
        write_session_file('Sparrow', 4100)
        allow(shell).to receive(:ask_connect_choice).and_return(nil)

        expect { shell.send(:prompt_for_connect) }.not_to(change { shell.sessions.size })
      end
    end

    describe 'acting on a row' do
      it 'attaches to a running session' do
        with_fake_lich do |port|
          shell.send(:connect_row, row(:running, port: port))

          expect(shell.sessions.map { |session| [session.character, session.origin] }).to eq([['Sparrow', :attached]])
        end
      end

      it 'reports a running session that refuses the connection' do
        allow(shell).to receive(:report)

        shell.send(:connect_row, row(:running, port: closed_port))

        expect(shell).to have_received(:report).with('Could not attach to Sparrow', anything)
        expect(shell.sessions).to be_empty
      end

      it 'focuses the tab of a session already attached' do
        with_fake_lich do |port|
          first = shell.attach(host: '127.0.0.1', port: port, character: 'Sparrow')
          with_fake_lich do |other_port|
            shell.attach(host: '127.0.0.1', port: other_port, character: 'Wren')

            shell.send(:connect_row, row(:attached, port: port))

            expect(notebook(shell).page).to eq(shell.sessions.index(first))
            expect(shell.sessions.size).to eq(2)
          end
        end
      end

      it 'does nothing for a launch already in progress' do
        expect { shell.send(:connect_row, row(:launching)) }.not_to(change { shell.sessions.size })
      end

      context 'with a usable lich-5 install' do
        let(:lich_dir) do
          Dir.mktmpdir.tap do |dir|
            write_install(dir, <<~YAML)
              accounts:
                ALPHA:
                  characters:
                  - { char_name: Sparrow, game_code: GS3, is_favorite: true }
                  - { char_name: Wren, game_code: GS3, is_favorite: false }
                BETA:
                  characters:
                  - { char_name: Morrow, game_code: DR, is_favorite: true }
            YAML
          end
        end
        let(:launched) do
          instance_double(Grimoire::LaunchedLich, character: 'Sparrow', started_at: Time.now, running?: true)
        end

        after { FileUtils.remove_entry(lich_dir) }

        it 'launches a favorite that is not running and waits for it' do
          allow(launcher(shell)).to receive(:launch).and_return(launched)

          shell.send(:connect_row, row(:not_running))

          expect(launcher(shell)).to have_received(:launch).with(having_attributes(char_name: 'Sparrow'))
          expect(shell.send(:launching_characters)).to eq(['Sparrow'])
        end

        it 'launches without asking when only other accounts are running' do
          write_session_file('Morrow', 4100)
          allow(launcher(shell)).to receive(:launch).and_return(launched)
          allow(shell).to receive(:confirm_launch_anyway)

          shell.send(:connect_row, row(:not_running))

          expect(shell).not_to have_received(:confirm_launch_anyway)
          expect(launcher(shell)).to have_received(:launch)
        end

        it 'asks before launching over another character on the same account, naming it' do
          write_session_file('Wren', 4100)
          allow(launcher(shell)).to receive(:launch).and_return(launched)
          allow(shell).to receive(:confirm_launch_anyway).and_return(false)

          shell.send(:connect_row, row(:not_running))

          expect(shell).to have_received(:confirm_launch_anyway)
            .with(having_attributes(char_name: 'Sparrow'), [having_attributes(char_name: 'Wren')])
          expect(launcher(shell)).not_to have_received(:launch)
        end

        it 'launches anyway when the user confirms' do
          write_session_file('Wren', 4100)
          allow(launcher(shell)).to receive(:launch).and_return(launched)
          allow(shell).to receive(:confirm_launch_anyway).and_return(true)

          shell.send(:connect_row, row(:not_running))

          expect(launcher(shell)).to have_received(:launch)
        end

        it 'reports a launch the launcher refuses' do
          allow(launcher(shell)).to receive(:launch).and_raise(Grimoire::LichLauncher::Error, 'GemStone IV Platinum (GSX) has closed')
          allow(shell).to receive(:report)

          shell.send(:connect_row, row(:not_running))

          expect(shell).to have_received(:report).with('Could not launch Sparrow', /has closed/)
          expect(shell.send(:launching_characters)).to be_empty
        end
      end

      it 'cannot launch without a lich.dir' do
        expect { shell.send(:connect_row, row(:not_running)) }.not_to(change { shell.send(:launching_characters) })
      end
    end

    describe 'the dialog itself' do
      def tree_rows(tree)
        [].tap { |rows| tree.model.each { |_model, _path, iter| rows << [iter[0], iter[1], iter[2]] } }
      end

      def connect_button(dialog)
        dialog.get_widget_for_response(Gtk::ResponseType::OK)
      end

      it 'lists each row with its game and status' do
        dialog, tree = shell.send(:build_connect_dialog, [row(:running, port: 4100), row(:attached, character: 'Wren', port: 4101)], nil)

        expect(tree_rows(tree)).to eq([['Sparrow', 'GemStone IV', 'Running'], ['Wren', 'GemStone IV', 'Open in a tab']])
      ensure
        dialog&.destroy
      end

      it 'shows why launching is unavailable above the list' do
        dialog, = shell.send(:build_connect_dialog, [row(:running, port: 4100)], 'Launching is unavailable: because')
        labels = dialog.child.children.grep(Gtk::Label).map(&:text)

        expect(labels).to include('Launching is unavailable: because')
      ensure
        dialog&.destroy
      end

      it 'selects the first row it can act on and enables Connect' do
        dialog, tree = shell.send(:build_connect_dialog, [row(:launching), row(:running, character: 'Wren', port: 4100)], nil)

        expect(shell.send(:selected_index, tree)).to eq(1)
        expect(connect_button(dialog)).to be_sensitive
      ensure
        dialog&.destroy
      end

      it 'disables Connect on a row it cannot act on' do
        dialog, tree = shell.send(:build_connect_dialog, [row(:running, port: 4100), row(:launching, character: 'Wren')], nil)

        tree.selection.select_path(Gtk::TreePath.new('1'))

        expect(connect_button(dialog)).not_to be_sensitive
      ensure
        dialog&.destroy
      end

      it 'cannot launch a favorite without a launcher, so Connect stays disabled' do
        dialog, = shell.send(:build_connect_dialog, [row(:not_running)], nil)

        expect(connect_button(dialog)).not_to be_sensitive
      ensure
        dialog&.destroy
      end
    end

    describe 'launch progress in the title bar' do
      def subtitle(shell)
        shell.instance_variable_get(:@header).subtitle
      end

      def launched(character)
        instance_double(Grimoire::LaunchedLich, character: character, started_at: Time.now, running?: true)
      end

      it 'names every launch being waited on, and clears once they finish' do
        expect(subtitle(shell)).to be_nil

        sparrow = shell.await_launch(launched('Sparrow'))
        shell.await_launch(launched('Wren'))
        expect(subtitle(shell)).to eq('Launching Sparrow, Wren...')

        shell.send(:finish_launch_watch, sparrow)
        expect(subtitle(shell)).to eq('Launching Wren...')
      end
    end
  end

  def view_text(session)
    session.instance_variable_get(:@view).instance_variable_get(:@buffer).text
  end
end
