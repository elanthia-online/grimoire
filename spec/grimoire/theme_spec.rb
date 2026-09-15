require 'spec_helper'

RSpec.describe Grimoire::Theme do
  describe 'DEFAULT' do
    it 'sets the game window (scrollback/entry) to black bg, white fg' do
      expect(described_class::DEFAULT.game_window_bg).to eq(Grimoire::Color.new(red: 0, green: 0, blue: 0))
      expect(described_class::DEFAULT.game_window_fg).to eq(Grimoire::Color.new(red: 255, green: 255, blue: 255))
    end

    it 'defaults the output font to Overpass Mono (falling back to generic monospace) at 11pt' do
      expect(described_class::DEFAULT.font_family).to eq('Overpass Mono, monospace')
      expect(described_class::DEFAULT.font_size).to eq(11)
    end

    it 'defines a fill color for every vitals field not shown by command_vitals' do
      expect(described_class::DEFAULT.vitals_colors.keys).to contain_exactly(:mind, :encumbrance, :stance)
    end

    it 'defines a fill color for every command_vitals field' do
      expect(described_class::DEFAULT.command_vitals_colors.keys).to contain_exactly(
        :health, :mana, :stamina, :spirit
      )
    end

    it 'gives every vitals/command_vitals field a Color instance' do
      described_class::DEFAULT.vitals_colors.each_value { |color| expect(color).to be_a(Grimoire::Color) }
      described_class::DEFAULT.command_vitals_colors.each_value { |color| expect(color).to be_a(Grimoire::Color) }
    end

    it 'has no vitals_background field -- every progress bar trough is a fixed #000000, not themeable' do
      expect(described_class::DEFAULT).not_to respond_to(:vitals_background)
    end

    it 'defaults roundtime colors to health-red (hard) and mana-blue (cast)' do
      expect(described_class::DEFAULT.roundtime_hard).to eq(described_class::DEFAULT.command_vitals_colors[:health])
      expect(described_class::DEFAULT.roundtime_cast).to eq(described_class::DEFAULT.command_vitals_colors[:mana])
    end

    it 'defaults the title bar fg to match the game window, bg to its own dark charcoal' do
      expect(described_class::DEFAULT.title_bar_fg).to eq(described_class::DEFAULT.game_window_fg)
      expect(described_class::DEFAULT.title_bar_bg).to eq(Grimoire::Color.new(red: 26, green: 26, blue: 26))
    end

    it 'defaults padding to 2px and every border width to 0 (invisible)' do
      expect(described_class::DEFAULT.padding).to eq(2)
      expect(described_class::DEFAULT.border_width).to eq(0)
      expect(described_class::DEFAULT.vitals_border_width).to eq(0)
    end

    it 'defaults padding_bg to its own dark charcoal, distinct from the game window' do
      expect(described_class::DEFAULT.padding_bg).to eq(Grimoire::Color.new(red: 34, green: 34, blue: 34))
    end

    it 'defaults the command bar to the same colors/font as the game window' do
      expect(described_class::DEFAULT.command_bar_bg).to eq(described_class::DEFAULT.game_window_bg)
      expect(described_class::DEFAULT.command_bar_fg).to eq(described_class::DEFAULT.game_window_fg)
      expect(described_class::DEFAULT.command_bar_font_family).to eq(described_class::DEFAULT.font_family)
      expect(described_class::DEFAULT.command_bar_font_size).to eq(described_class::DEFAULT.font_size)
    end

    it 'defaults the command_vitals overlaid number text color to white' do
      expect(described_class::DEFAULT.vitals_fg).to eq(Grimoire::Color.new(red: 255, green: 255, blue: 255))
    end

    it 'has no vitals font-family field -- the label font is fixed, not themeable' do
      expect(described_class::DEFAULT).not_to respond_to(:vitals_font_family)
    end

    it 'has no indicator_fg field -- the old text-based status bar was removed 2026-09-15' do
      expect(described_class::DEFAULT).not_to respond_to(:indicator_fg)
    end

    it 'has no show_vitals_bar/show_status_bar fields -- the old top-of-window vitals strip was removed 2026-09-15' do
      expect(described_class::DEFAULT).not_to respond_to(:show_vitals_bar)
      expect(described_class::DEFAULT).not_to respond_to(:show_status_bar)
    end

    it 'defaults show_roundtime_bar to true' do
      expect(described_class::DEFAULT.show_roundtime_bar).to be(true)
    end

    it 'defaults the debug menu to hidden, unlike the other widget toggles' do
      expect(described_class::DEFAULT.show_debug_menu).to be(false)
    end

    # Revised from an initial *false* default (the same "brand new, not
    # existing UI" reasoning show_debug_menu still uses) -- the user's own
    # later spec (2026-09-15): command_vitals should default enabled, the
    # same revision status_indicators already got.
    it 'defaults command_vitals to shown, unlike the debug menu' do
      expect(described_class::DEFAULT.show_command_vitals).to be(true)
    end

    it 'defaults command_vitals numbers to shown' do
      expect(described_class::DEFAULT.command_vitals_show_numbers).to be(true)
    end

    it 'has no command_vitals_number_justify field -- always centered, not configurable' do
      expect(described_class::DEFAULT).not_to respond_to(:command_vitals_number_justify)
    end

    # Revised from an initial *false* default (the same "brand new, not
    # existing UI" reasoning show_debug_menu/show_command_vitals still
    # use) -- the user's own later spec (2026-09-15): status_indicators
    # should default enabled.
    it 'defaults the indicator block to shown, unlike the debug menu' do
      expect(described_class::DEFAULT.show_indicators).to be(true)
    end

    # Revised (2026-09-15) from an initial :right the same day.
    it 'defaults status_indicators_location to :left' do
      expect(described_class::DEFAULT.status_indicators_location).to eq(:left)
    end

    it 'defaults roundtime_min_rt to 5 (down from the old fixed 10)' do
      expect(described_class::DEFAULT.roundtime_min_rt).to eq(5)
    end
  end
end
