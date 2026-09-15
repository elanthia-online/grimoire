require 'gtk3'
require_relative 'theme'

module Grimoire
  # Standalone preview window for assets/indicators/*.png -- separate from
  # the main Window entirely (the user's own spec, 2026-09-15): not a
  # toggleable widget inside the game window, its own top-level
  # Gtk::Window. Every known indicator is shown at once, in a single
  # left-to-right row, icon only -- no text label under each one, per the
  # user's own later spec (2026-09-15): "the icon itself is the entire
  # indicator" (status indicators, unlike the vitals bars, need no text to
  # be legible). Every icon is forced "on" regardless of any live
  # VitalsState; the point is reviewing the icon set itself against the
  # real default theme, not exercising the indicator wire.
  #
  # ICONS pairs each icon's display name with its assets/indicators/*.png
  # filename and the wire id it corresponds to (VitalsTracker#handle_indicator/
  # docs/decisions.md's confirmed IconXXXX list) -- grouped to read sensibly
  # (postures, then afflictions, then combat/social state) rather than
  # alphabetically. The wire id is not used for anything here (this window
  # never touches VitalsState) but is kept alongside each entry so the
  # mapping back to the protocol stays in one place rather than needing to
  # be cross-referenced by hand. The display name is currently unused too
  # (no label renders it) but is kept for the same reason.
  class IndicatorWindow
    ICONS = [
      ['Standing', 'standing.png', 'IconSTANDING'],
      ['Kneeling', 'kneeling.png', 'IconKNEELING'],
      ['Sitting', 'sitting.png', 'IconSITTING'],
      ['Prone', 'prone.png', 'IconPRONE'],
      ['Bleeding', 'bleeding.png', 'IconBLEEDING'],
      ['Poisoned', 'poisoned.png', 'IconPOISONED'],
      ['Diseased', 'diseased.png', 'IconDISEASED'],
      ['Stunned', 'stunned.png', 'IconSTUNNED'],
      ['Webbed', 'webbed.png', 'IconWEBBED'],
      ['Hidden', 'hidden.png', 'IconHIDDEN'],
      ['Invisible', 'invisible.png', 'IconINVISIBLE'],
      ['Dead', 'dead.png', 'IconDEAD'],
      ['Joined', 'joined.png', 'IconJOINED'],
    ].freeze

    # 32x32 -- a common icon size, the user's own later spec (2026-09-15,
    # revised up from an initial 24x24). Kept as its own constant rather
    # than inlined so it can move again in one place; it is also the same
    # value Window uses for command_vitals bars and the command entry's
    # own min-height floor, so all three read as one visually consistent
    # height in the live game window.
    ICON_SIZE = 32

    ASSETS_DIR = File.expand_path('../../assets/indicators', __dir__)

    BOX_CSS_CLASS = 'grimoire-indicator-preview-box'
    WINDOW_CSS_CLASS = 'grimoire-indicator-preview-window'

    private_constant :BOX_CSS_CLASS, :WINDOW_CSS_CLASS

    def initialize(theme: Theme::DEFAULT)
      @theme = theme
      load_css
      @gtk_window = build_window
    end

    def show
      @gtk_window.show_all
    end

    def to_gtk
      @gtk_window
    end

    private

    # A single row, left-to-right -- the user's own spec (2026-09-15) --
    # rather than the wrapping grid this window shipped with initially.
    # @theme.padding (2px by default) is both the row's own outer border
    # and the spacing between each icon box, the same dual role Theme's
    # own padding field already plays in the main game Window.
    def build_window
      row = Gtk::Box.new(:horizontal, @theme.padding)
      row.border_width = @theme.padding

      ICONS.each { |_name, filename, _wire_id| row.pack_start(build_icon_box(filename), expand: false, fill: false, padding: 0) }

      window = Gtk::Window.new
      window.title = 'grimoire -- indicator preview'
      window.style_context.add_class(WINDOW_CSS_CLASS)
      window.add(row)
      window.signal_connect('destroy') { window.destroy }
      window
    end

    # No internal padding around the icon within its own box, per the
    # user's own spec -- the box exists only to give each icon its own
    # solid black backdrop (a bare Gtk::Image paints no background of its
    # own), sized to exactly ICON_SIZE with nothing added, not to add any
    # spacing of its own (that is the row's own @theme.padding, between
    # boxes, not inside one).
    #
    # valign: :center locks the box (and its black CSS background) to its
    # natural 24x24 height regardless of how tall the window is resized --
    # the user's own report (2026-09-15). pack_start's own expand/fill
    # flags only govern the row's primary (horizontal) axis; the cross
    # axis (vertical, for a horizontal box) is governed by each child's own
    # valign, which GTK defaults to :fill -- confirmed live, the box's
    # allocation grew to 24x196 after a resize to 500x200 with no valign
    # set. Evaluated separately (2026-09-15) whether this also bites once
    # this row is wired into the main game Window: it does not, so long as
    # it keeps being packed expand: false, fill: false into that window's
    # vertical box the same way the vitals strip/command row already are
    # -- expand: false means the vertical box never hands this row a share
    # of extra vertical space to begin with (that all goes to the
    # expand: true scrollback), confirmed by reproducing that exact packing
    # shape and resizing it. Fixed here anyway since this window is a
    # standalone, directly user-resizable Gtk::Window with nothing else to
    # absorb the extra space, unlike the embedded case.
    def build_icon_box(filename)
      box = Gtk::Box.new(:horizontal, 0)
      box.valign = :center
      box.style_context.add_class(BOX_CSS_CLASS)
      box.pack_start(Gtk::Image.new(pixbuf: load_pixbuf(filename)), expand: false, fill: false, padding: 0)
      box
    end

    def load_pixbuf(filename)
      GdkPixbuf::Pixbuf.new(file: File.join(ASSETS_DIR, filename)).scale_simple(ICON_SIZE, ICON_SIZE, :bilinear)
    end

    def load_css
      provider = Gtk::CssProvider.new
      provider.load(data: preview_css)
      Gtk::StyleContext.add_provider_for_screen(
        Gdk::Screen.default, provider, Gtk::StyleProvider::PRIORITY_APPLICATION
      )
    end

    # Each icon box stays a fixed black regardless of @theme -- every icon
    # is designed for a black backdrop, the user's own spec from the
    # previous round, unrelated to whatever theme is passed in. The window
    # itself, which is what shows through the row's own border/spacing
    # gaps between boxes, uses @theme.padding_bg -- the same role
    # Window's own padding_bg already plays for the main game window's own
    # gaps (see Theme's own comment on that field).
    def preview_css
      <<~CSS
        box.#{BOX_CSS_CLASS} {
          background-color: rgb(0, 0, 0);
        }
        window.#{WINDOW_CSS_CLASS} {
          background-color: #{@theme.padding_bg.to_css};
          background-image: none;
        }
      CSS
    end
  end
end
