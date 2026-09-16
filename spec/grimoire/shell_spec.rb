require 'spec_helper'

RSpec.describe Grimoire::Shell do
  subject(:shell) { described_class.new }

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
    shell.to_gtk.destroy
    pump_gtk_events
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

    it 'offers a Session menu with attach, launch and quit' do
      labels = menu_items(shell).map { |item| item.respond_to?(:label) ? item.label : nil }

      expect(labels).to include('Attach to session...', 'Launch headless...', 'Quit')
    end

    # The user's own call (2026-09-15): the entry exists from the start so it
    # is not bolted on later, but stays inert until BACKLOG.md's "Lich
    # headless launch" section is picked up.
    it 'leaves the headless launch entry disabled until that work lands' do
      launch = menu_items(shell).find { |item| item.respond_to?(:label) && item.label == 'Launch headless...' }

      expect(launch.sensitive?).to be(false)
    end

    it 'keeps attach and quit enabled' do
      items = menu_items(shell).select { |item| item.respond_to?(:label) }
      enabled = items.select(&:sensitive?).map(&:label)

      expect(enabled).to include('Attach to session...', 'Quit')
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

  def view_text(session)
    session.instance_variable_get(:@view).instance_variable_get(:@buffer).text
  end
end
