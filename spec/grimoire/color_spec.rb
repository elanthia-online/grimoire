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
end
