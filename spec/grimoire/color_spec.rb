require 'spec_helper'

RSpec.describe Grimoire::Color do
  it 'holds a plain red/green/blue triple' do
    color = described_class.new(red: 200, green: 0, blue: 0)

    expect(color.red).to eq(200)
    expect(color.green).to eq(0)
    expect(color.blue).to eq(0)
  end

  it 'renders as a CSS rgb() function' do
    color = described_class.new(red: 128, green: 0, blue: 200)

    expect(color.to_css).to eq('rgb(128, 0, 200)')
  end

  describe '#to_hex' do
    it 'renders as a lowercase, zero-padded "#rrggbb" string' do
      color = described_class.new(red: 200, green: 0, blue: 8)

      expect(color.to_hex).to eq('#c80008')
    end

    it 'round-trips through .from_hex' do
      color = described_class.new(red: 18, green: 52, blue: 86)

      expect(described_class.from_hex(color.to_hex)).to eq(color)
    end
  end

  describe '.from_hex' do
    it 'parses a leading-# hex string' do
      expect(described_class.from_hex('#c80000')).to eq(described_class.new(red: 200, green: 0, blue: 0))
    end

    it 'parses a bare hex string with no leading #' do
      expect(described_class.from_hex('0000c8')).to eq(described_class.new(red: 0, green: 0, blue: 200))
    end

    it 'is case-insensitive' do
      expect(described_class.from_hex('#FFFFFF')).to eq(described_class.new(red: 255, green: 255, blue: 255))
    end

    it 'raises on a malformed value' do
      expect { described_class.from_hex('not-a-color') }.to raise_error(ArgumentError, /invalid color/)
    end

    it 'raises on the wrong number of digits' do
      expect { described_class.from_hex('#fff') }.to raise_error(ArgumentError, /invalid color/)
    end
  end
end
