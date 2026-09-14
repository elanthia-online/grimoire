require 'spec_helper'

RSpec.describe Grimoire::RoomState do
  subject(:state) { described_class.new }

  it 'starts with every field nil' do
    expect(state.number).to be_nil
    expect(state.title).to be_nil
    expect(state.description).to be_nil
    expect(state.objects).to be_nil
    expect(state.players).to be_nil
    expect(state.exits).to be_nil
  end

  it 'enter sets every given field' do
    state.enter(number: '7355', title: 'Town Square, Small Park', description: 'A small park.',
                objects: 'Some benches.', players: 'Nobody.', exits: 'north, south')

    expect(state.number).to eq('7355')
    expect(state.title).to eq('Town Square, Small Park')
    expect(state.description).to eq('A small park.')
    expect(state.objects).to eq('Some benches.')
    expect(state.players).to eq('Nobody.')
    expect(state.exits).to eq('north, south')
  end

  it 'enter resets fields left unspecified (a real room transition replaces everything)' do
    state.enter(number: '7355', title: 'Small Park', description: 'A small park.',
                objects: 'Some benches.', players: 'Nobody.', exits: 'north')

    state.enter(number: '3201029', title: 'Gardenia Commons', description: '[Room window disabled.]')

    expect(state.number).to eq('3201029')
    expect(state.objects).to be_nil
    expect(state.players).to be_nil
    expect(state.exits).to be_nil
  end

  it 'update merges only the given fields, leaving the rest untouched' do
    state.enter(number: '7355', title: 'Small Park', description: 'A small park.',
                objects: 'Some benches.', players: 'Nobody.', exits: 'north')

    state.update(objects: 'A dreadsteed appears.')

    expect(state.objects).to eq('A dreadsteed appears.')
    expect(state.players).to eq('Nobody.')
    expect(state.number).to eq('7355')
    expect(state.title).to eq('Small Park')
    expect(state.description).to eq('A small park.')
    expect(state.exits).to eq('north')
  end
end
