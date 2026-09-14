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

    it 'defines a fill color for every vitals-strip field, including stance' do
      expect(described_class::DEFAULT.vitals_colors.keys).to contain_exactly(
        :health, :mana, :stamina, :spirit, :mind, :encumbrance, :stance
      )
    end

    it 'gives every vitals field a Color instance' do
      described_class::DEFAULT.vitals_colors.each_value do |color|
        expect(color).to be_a(Grimoire::Color)
      end
    end

    it 'has no vitals_background field -- every progress bar trough is a fixed #000000, not themeable' do
      expect(described_class::DEFAULT).not_to respond_to(:vitals_background)
    end

    it 'defaults roundtime colors to health-red (hard) and mana-blue (cast)' do
      expect(described_class::DEFAULT.roundtime_hard).to eq(described_class::DEFAULT.vitals_colors[:health])
      expect(described_class::DEFAULT.roundtime_cast).to eq(described_class::DEFAULT.vitals_colors[:mana])
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

    it 'defaults the vitals label text color to white' do
      expect(described_class::DEFAULT.vitals_fg).to eq(Grimoire::Color.new(red: 255, green: 255, blue: 255))
    end

    it 'has no vitals font-family field -- the label font is fixed, not themeable' do
      expect(described_class::DEFAULT).not_to respond_to(:vitals_font_family)
    end
  end
end
