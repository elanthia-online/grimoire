require 'spec_helper'

RSpec.describe Grimoire::RoomTracker do
  def text(value)
    Grimoire::Tokenizer::Tokens::Text.new(value: value)
  end

  def tag(name, attrs: {}, closing: false, self_closing: false)
    Grimoire::Tokenizer::Tokens::Tag.new(name: name, attrs: attrs, closing: closing, self_closing: self_closing)
  end

  subject(:tracker) { described_class.new }

  def feed_enter(tracker, id: 'room', number: '7355', title: ' - Town Square, Small Park')
    tracker.route(tag('nav', attrs: { 'rm' => number }, self_closing: true))
    tracker.route(tag('streamWindow', attrs: { 'id' => id, 'subtitle' => title }, self_closing: true))
    tracker.route(tag('pushStream', attrs: { 'id' => id }, self_closing: true))
    tracker.route(tag('compDef', attrs: { 'id' => 'room desc' }))
    tracker.route(text('A small, shaded park.'))
    tracker.route(tag('compDef', closing: true))
    tracker.route(tag('compDef', attrs: { 'id' => 'room objs' }))
    tracker.route(text('You also see some benches.'))
    tracker.route(tag('compDef', closing: true))
    tracker.route(tag('compDef', attrs: { 'id' => 'room players' }))
    tracker.route(tag('compDef', closing: true))
    tracker.route(tag('compDef', attrs: { 'id' => 'room exits' }))
    tracker.route(text('Obvious paths: north, south.'))
    tracker.route(tag('compDef', closing: true))
    tracker.route(tag('popStream', attrs: { 'id' => id }, self_closing: true))
  end

  it 'reports plain narrative text as narrative when nothing is being captured' do
    routed = tracker.route(text('You are standing in a field.'))

    expect(routed).to be_narrative
  end

  it 'captures a full move-triggered room entry into room_state' do
    feed_enter(tracker)

    expect(tracker.room_state.number).to eq('7355')
    expect(tracker.room_state.title).to eq('Town Square, Small Park')
    expect(tracker.room_state.description).to eq('A small, shaded park.')
    expect(tracker.room_state.objects).to eq('You also see some benches.')
    expect(tracker.room_state.players).to eq('')
    expect(tracker.room_state.exits).to eq('Obvious paths: north, south.')
  end

  it 'reports text inside a compDef bracket as not narrative' do
    tracker.route(tag('pushStream', attrs: { 'id' => 'room' }, self_closing: true))
    tracker.route(tag('compDef', attrs: { 'id' => 'room desc' }))
    routed = tracker.route(text('A small, shaded park.'))

    expect(routed).not_to be_narrative
  end

  it 'resets every field on a second room entry, even ones the new entry omits' do
    feed_enter(tracker)
    tracker.route(tag('nav', attrs: { 'rm' => '3201029' }, self_closing: true))
    tracker.route(tag('streamWindow', attrs: { 'id' => 'room', 'subtitle' => ' - Gardenia Commons' },
                                      self_closing: true))
    tracker.route(tag('pushStream', attrs: { 'id' => 'room' }, self_closing: true))
    tracker.route(tag('compDef', attrs: { 'id' => 'room desc' }))
    tracker.route(text('[Room window disabled at this location.]'))
    tracker.route(tag('compDef', closing: true))
    tracker.route(tag('popStream', attrs: { 'id' => 'room' }, self_closing: true))

    expect(tracker.room_state.number).to eq('3201029')
    expect(tracker.room_state.description).to eq('[Room window disabled at this location.]')
    expect(tracker.room_state.objects).to be_nil
    expect(tracker.room_state.players).to be_nil
    expect(tracker.room_state.exits).to be_nil
  end

  it 'merges a bare periodic component update without touching other fields' do
    feed_enter(tracker)

    tracker.route(tag('component', attrs: { 'id' => 'room objs' }))
    routed = tracker.route(text('A dreadsteed appears, frozen in place.'))
    tracker.route(tag('component', closing: true))

    expect(routed).not_to be_narrative
    expect(tracker.room_state.objects).to eq('A dreadsteed appears, frozen in place.')
    expect(tracker.room_state.description).to eq('A small, shaded park.')
    expect(tracker.room_state.players).to eq('')
    expect(tracker.room_state.exits).to eq('Obvious paths: north, south.')
  end

  it 'ignores a bare component tag with an unrelated id' do
    feed_enter(tracker)

    tracker.route(tag('component', attrs: { 'id' => 'inv' }))
    routed = tracker.route(text('some ignored text'))
    tracker.route(tag('component', closing: true))

    expect(routed).to be_narrative
    expect(tracker.room_state.objects).to eq('You also see some benches.')
  end
end
