require 'spec_helper'

RSpec.describe Grimoire::StreamTracker do
  def text(value)
    Grimoire::Tokenizer::Tokens::Text.new(value: value)
  end

  def tag(name, attrs: {}, closing: false, self_closing: false)
    Grimoire::Tokenizer::Tokens::Tag.new(name: name, attrs: attrs, closing: closing, self_closing: self_closing)
  end

  subject(:tracker) { described_class.new }

  it 'tags plain text with a nil (narrative) stream id' do
    routed = tracker.route(text('You are standing in a field.'))

    expect(routed.stream_id).to be_nil
    expect(routed).to be_narrative
  end

  it 'tags text between pushStream and popStream with the pushed id' do
    tracker.route(tag('pushStream', attrs: { 'id' => 'inv' }, self_closing: true))
    routed = tracker.route(text('a rusty dagger'))

    expect(routed.stream_id).to eq('inv')
    expect(routed).not_to be_narrative
  end

  it 'returns text after popStream to a nil stream id' do
    tracker.route(tag('pushStream', attrs: { 'id' => 'inv' }, self_closing: true))
    tracker.route(text('a rusty dagger'))
    tracker.route(tag('popStream', self_closing: true))
    routed = tracker.route(text('back to the room.'))

    expect(routed.stream_id).to be_nil
  end

  it 'tags the popStream tag itself with the stream that is closing' do
    tracker.route(tag('pushStream', attrs: { 'id' => 'inv' }, self_closing: true))
    routed = tracker.route(tag('popStream', self_closing: true))

    expect(routed.stream_id).to eq('inv')
  end

  it 'does not restore an outer stream after an inner pushStream overwrites it' do
    tracker.route(tag('pushStream', attrs: { 'id' => 'combat' }, self_closing: true))
    tracker.route(tag('pushStream', attrs: { 'id' => 'thoughts' }, self_closing: true))
    popped = tracker.route(tag('popStream', self_closing: true))
    after  = tracker.route(text('after the pop'))

    expect(popped.stream_id).to eq('thoughts')
    expect(after.stream_id).to be_nil
  end

  it 'ignores a popStream id attribute and always returns to narrative' do
    tracker.route(tag('pushStream', attrs: { 'id' => 'combat' }, self_closing: true))
    tracker.route(tag('popStream', attrs: { 'id' => 'combat' }, self_closing: true))
    routed = tracker.route(text('narrative again'))

    expect(routed.stream_id).to be_nil
  end
end
