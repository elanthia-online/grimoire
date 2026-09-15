require 'spec_helper'

RSpec.describe Grimoire::IndicatorWindow do
  subject(:window) { described_class.new }

  def row(window)
    window.to_gtk.child
  end

  def icon_boxes(window)
    row(window).children
  end

  it 'is a standalone top-level window, separate from the main game Window' do
    expect(window.to_gtk).to be_a(Gtk::Window)
  end

  it 'builds one box per known indicator, regardless of any live vitals state, in a single left-to-right row' do
    expect(row(window)).to be_a(Gtk::Box)
    expect(row(window).orientation).to eq(:horizontal)
    expect(icon_boxes(window).length).to eq(described_class::ICONS.length)
  end

  it 'shows no text label -- the icon alone is the whole indicator, per the user\'s own spec' do
    icon_boxes(window).each do |box|
      expect(box.children.length).to eq(1)
      expect(box.children.first).to be_a(Gtk::Image)
    end
  end

  it 'spaces icon boxes 2px apart (the default theme padding), with no extra padding inside a box' do
    expect(row(window).spacing).to eq(Grimoire::Theme::DEFAULT.padding)
    expect(row(window).border_width).to eq(Grimoire::Theme::DEFAULT.padding)
  end

  # An unrealized widget's #preferred_size reports 0 (GTK has no layout
  # context to measure against yet -- the same reason Window#command_bar_height
  # has to reparent into a throwaway Gtk::OffscreenWindow), so this needs a
  # real #show pass first, unlike every other example here.
  it 'sizes each icon box to exactly the icon itself (ICON_SIZE x ICON_SIZE), with no internal padding added' do
    window.show
    Gtk.main_iteration while Gtk.events_pending?

    icon_boxes(window).each do |box|
      size = box.preferred_size.last

      expect(size.width).to eq(described_class::ICON_SIZE)
      expect(size.height).to eq(described_class::ICON_SIZE)
    end
  ensure
    window.to_gtk.destroy
  end

  # Regression coverage for the user's own report (2026-09-15): resizing
  # the (standalone, directly user-resizable) window taller stretched each
  # icon box's own black-background CSS along with it. Root cause: GTK box
  # packing's expand/fill flags only govern the row's primary (horizontal)
  # axis -- the cross axis (vertical, for a horizontal box) is governed by
  # each child's own valign, which defaults to :fill, so a box given more
  # height than its natural size grows to fill it. Confirmed live before
  # the fix: allocation grew to 24x196 after a resize to 500x200.
  it 'locks each icon box to its natural height rather than stretching to fill a taller resized window' do
    window.show
    Gtk.main_iteration while Gtk.events_pending?
    window.to_gtk.resize(500, 200)
    30.times { Gtk.main_iteration while Gtk.events_pending?; sleep 0.01 }

    icon_boxes(window).each do |box|
      expect(box.allocation.height).to eq(described_class::ICON_SIZE)
    end
  ensure
    window.to_gtk.destroy
  end

  it 'tags every box with the fixed-black-background CSS class' do
    icon_boxes(window).each do |box|
      expect(box.style_context.has_class?('grimoire-indicator-preview-box')).to be(true)
    end
  end

  it 'paints every box background a fixed black, independent of any theme' do
    css = window.send(:preview_css)

    expect(css).to include('background-color: rgb(0, 0, 0)')
  end

  it 'paints the window background from the default theme\'s padding_bg, which shows through the row\'s own gaps' do
    css = window.send(:preview_css)

    expect(css).to include("background-color: #{Grimoire::Theme::DEFAULT.padding_bg.to_css}")
  end

  it 'reads the padding/padding_bg gap color from a custom theme rather than always the default' do
    theme = Grimoire::Theme::DEFAULT.with(padding: 5, padding_bg: Grimoire::Color.new(red: 10, green: 20, blue: 30))
    themed_window = described_class.new(theme: theme)

    expect(row(themed_window).spacing).to eq(5)
    expect(row(themed_window).border_width).to eq(5)
    expect(themed_window.send(:preview_css)).to include('background-color: rgb(10, 20, 30)')
  end

  it 'scales every icon image to ICON_SIZE x ICON_SIZE' do
    icon_boxes(window).each do |box|
      pixbuf = box.children.first.pixbuf

      expect(pixbuf.width).to eq(described_class::ICON_SIZE)
      expect(pixbuf.height).to eq(described_class::ICON_SIZE)
    end
  end

  it 'defaults ICON_SIZE to 32, per the user\'s own spec' do
    expect(described_class::ICON_SIZE).to eq(32)
  end

  it 'references a real assets/indicators/*.png file for every ICONS entry' do
    described_class::ICONS.each do |_name, filename, _wire_id|
      path = File.join(described_class::ASSETS_DIR, filename)

      expect(File).to exist(path)
    end
  end

  it 'pairs every ICONS entry with a unique wire id, matching the confirmed IconXXXX set' do
    wire_ids = described_class::ICONS.map(&:last)

    expect(wire_ids.uniq).to eq(wire_ids)
    expect(wire_ids).to all(match(/\AIcon[A-Z]+\z/))
  end
end
