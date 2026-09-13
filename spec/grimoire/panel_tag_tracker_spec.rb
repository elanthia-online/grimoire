require 'spec_helper'

RSpec.describe Grimoire::PanelTagTracker do
  def text(value)
    Grimoire::Tokenizer::Tokens::Text.new(value: value)
  end

  def tag(name, attrs: {}, closing: false, self_closing: false)
    Grimoire::Tokenizer::Tokens::Tag.new(name: name, attrs: attrs, closing: closing, self_closing: self_closing)
  end

  subject(:tracker) { described_class.new }

  it 'reports plain narrative text as narrative' do
    expect(tracker.route(text('You are standing in a field.'))).to be_narrative
  end

  it 'reports an unrelated tag as narrative' do
    expect(tracker.route(tag('a', attrs: { 'exist' => '1', 'noun' => 'dagger' }))).to be_narrative
  end

  it 'squelches a lone self-closing status tag' do
    expect(tracker.route(tag('roommeta', attrs: { 'weather' => '0' }, self_closing: true))).not_to be_narrative
  end

  it 'does not persist state after a self-closing drop tag' do
    tracker.route(tag('roommeta', self_closing: true))

    expect(tracker.route(text("\r\n"))).to be_narrative
  end

  it 'squelches bare text wrapped by an open/close drop tag pair' do
    tracker.route(tag('spell'))
    routed = tracker.route(text('None'))
    tracker.route(tag('spell', closing: true))

    expect(routed).not_to be_narrative
  end

  it 'returns to narrative after a drop tag pair closes' do
    tracker.route(tag('spell'))
    tracker.route(text('None'))
    tracker.route(tag('spell', closing: true))

    expect(tracker.route(text('Real narrative.'))).to be_narrative
  end

  it 'keeps a self-closing child tag inside an open drop container squelched' do
    tracker.route(tag('dialogData', attrs: { 'id' => 'Cooldowns' }))
    routed = tracker.route(tag('progressBar', self_closing: true))
    closing = tracker.route(tag('dialogData', closing: true))

    expect(routed).not_to be_narrative
    expect(closing).not_to be_narrative
    expect(tracker.route(text('after'))).to be_narrative
  end

  it 'handles two same-name drop containers back to back independently' do
    tracker.route(tag('dialogData', attrs: { 'id' => 'Cooldowns' }))
    tracker.route(tag('dialogData', closing: true))
    tracker.route(tag('dialogData', attrs: { 'id' => 'Cooldowns' }))
    routed = tracker.route(tag('label', self_closing: true))
    tracker.route(tag('dialogData', closing: true))

    expect(routed).not_to be_narrative
    expect(tracker.route(text('after'))).to be_narrative
  end

  it 'does not close an open drop container on an unrelated closing tag' do
    tracker.route(tag('dialogData', attrs: { 'id' => 'combat' }))
    tracker.route(tag('label', closing: true))

    expect(tracker.route(text('still inside dialogData'))).not_to be_narrative
  end
end
