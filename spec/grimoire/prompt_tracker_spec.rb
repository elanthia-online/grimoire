require 'spec_helper'

RSpec.describe Grimoire::PromptTracker do
  def text(value)
    Grimoire::Tokenizer::Tokens::Text.new(value: value)
  end

  def tag(name, attrs: {}, closing: false, self_closing: false)
    Grimoire::Tokenizer::Tokens::Tag.new(name: name, attrs: attrs, closing: closing, self_closing: self_closing)
  end

  subject(:tracker) { described_class.new }

  it 'tags plain text with in_prompt false when no prompt is open' do
    routed = tracker.route(text('You are standing in a field.'))

    expect(routed).to be_narrative
  end

  it 'tags text between an opening and closing prompt tag as not narrative' do
    tracker.route(tag('prompt', attrs: { 'time' => '1763306658' }))
    routed = tracker.route(text('>'))

    expect(routed).not_to be_narrative
  end

  it 'returns text after the closing prompt tag to narrative' do
    tracker.route(tag('prompt', attrs: { 'time' => '1763306658' }))
    tracker.route(text('>'))
    tracker.route(tag('prompt', closing: true))
    routed = tracker.route(text('back to narrative'))

    expect(routed).to be_narrative
  end

  it 'captures the time attribute from the opening tag' do
    tracker.route(tag('prompt', attrs: { 'time' => '1763306658' }))

    expect(tracker.last_time).to eq('1763306658')
  end

  it 'updates last_time to the most recent prompt tag seen' do
    tracker.route(tag('prompt', attrs: { 'time' => '1763306658' }))
    tracker.route(text('>'))
    tracker.route(tag('prompt', closing: true))
    tracker.route(tag('prompt', attrs: { 'time' => '1763306700' }))

    expect(tracker.last_time).to eq('1763306700')
  end
end
