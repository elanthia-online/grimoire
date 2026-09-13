require 'spec_helper'

RSpec.describe Grimoire::VitalsColors do
  it 'defaults the shared empty/background color to black' do
    expect(described_class::BACKGROUND).to eq(Grimoire::Color.new(red: 0, green: 0, blue: 0))
  end

  it 'defines a fill color for every vitals-strip field, including stance' do
    expect(described_class::FIELDS.keys).to contain_exactly(
      :health, :mana, :stamina, :spirit, :mind, :encumbrance, :stance
    )
  end

  it 'gives every field a Color instance' do
    described_class::FIELDS.each_value do |color|
      expect(color).to be_a(Grimoire::Color)
    end
  end
end
