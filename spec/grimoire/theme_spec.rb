require 'spec_helper'

RSpec.describe Grimoire::Theme do
  describe 'DEFAULT' do
    it 'sets the main input/output windows to black background, white text' do
      expect(described_class::DEFAULT.main_background).to eq(Grimoire::Color.new(red: 0, green: 0, blue: 0))
      expect(described_class::DEFAULT.main_foreground).to eq(Grimoire::Color.new(red: 255, green: 255, blue: 255))
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

    it 'defaults the shared vitals empty/background color to black' do
      expect(described_class::DEFAULT.vitals_background).to eq(Grimoire::Color.new(red: 0, green: 0, blue: 0))
    end

    it 'defaults roundtime colors to health-red (hard) and mana-blue (cast)' do
      expect(described_class::DEFAULT.roundtime_hard).to eq(described_class::DEFAULT.vitals_colors[:health])
      expect(described_class::DEFAULT.roundtime_cast).to eq(described_class::DEFAULT.vitals_colors[:mana])
    end
  end
end
