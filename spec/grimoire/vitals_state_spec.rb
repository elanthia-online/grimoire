require 'spec_helper'

RSpec.describe Grimoire::VitalsState do
  subject(:state) { described_class.new }

  it 'starts with every vital nil, stance nil, no indicators, and no roundtime' do
    expect(state.health).to be_nil
    expect(state.mana).to be_nil
    expect(state.stamina).to be_nil
    expect(state.spirit).to be_nil
    expect(state.mind).to be_nil
    expect(state.encumbrance).to be_nil
    expect(state.stance).to be_nil
    expect(state.indicators).to eq({})
    expect(state.roundtime_end).to be_nil
    expect(state.cast_roundtime_end).to be_nil
  end

  it 'holds roundtime_end as a bare epoch' do
    state.roundtime_end = 1_788_826_158

    expect(state.roundtime_end).to eq(1_788_826_158)
  end

  it 'holds cast_roundtime_end independently of roundtime_end' do
    state.roundtime_end = 1_788_826_158
    state.cast_roundtime_end = 1_788_826_200

    expect(state.roundtime_end).to eq(1_788_826_158)
    expect(state.cast_roundtime_end).to eq(1_788_826_200)
  end

  it 'holds a percent/text pair set directly on a vital field' do
    state.health = described_class::Vital.new(percent: 98, text: 'health 351/355')

    expect(state.health.percent).to eq(98)
    expect(state.health.text).to eq('health 351/355')
  end

  it 'holds stance as a bare percent, independent of the other vitals' do
    state.stance = 80

    expect(state.stance).to eq(80)
  end

  it 'tracks indicators by id, defaulting to whatever was last set' do
    state.set_indicator('IconBLEEDING', false)
    state.set_indicator('IconSTANDING', true)

    expect(state.indicators).to eq('IconBLEEDING' => false, 'IconSTANDING' => true)

    state.set_indicator('IconBLEEDING', true)

    expect(state.indicators['IconBLEEDING']).to be(true)
  end
end
