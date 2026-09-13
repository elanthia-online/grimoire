require 'spec_helper'

RSpec.describe Grimoire::Tokenizer do
  def text(value)
    described_class::Tokens::Text.new(value: value)
  end

  def tag(name, attrs: {}, closing: false, self_closing: false)
    described_class::Tokens::Tag.new(name: name, attrs: attrs, closing: closing, self_closing: self_closing)
  end

  subject(:tokenizer) { described_class.new }

  it 'emits a plain text run with no tags' do
    expect(tokenizer.feed('You are standing in a field.')).to eq([text('You are standing in a field.')])
  end

  it 'emits text and tag tokens in order' do
    tokens = tokenizer.feed("Hello <pushStream id='room'/>world")

    expect(tokens).to eq([
                           text('Hello '),
                           tag('pushStream', attrs: { 'id' => 'room' }, self_closing: true),
                           text('world'),
                         ])
  end

  it 'parses a closing tag' do
    expect(tokenizer.feed('</prompt>')).to eq([tag('prompt', closing: true)])
  end

  it 'parses double-quoted attributes' do
    tokens = tokenizer.feed('<prompt time="1234567890">')
    expect(tokens).to eq([tag('prompt', attrs: { 'time' => '1234567890' })])
  end

  it 'parses multiple attributes on one tag' do
    tokens = tokenizer.feed("<component id='room objs' other=\"x\">")
    expect(tokens).to eq([tag('component', attrs: { 'id' => 'room objs', 'other' => 'x' })])
  end

  it 'tolerates a literal ">" inside a quoted attribute value' do
    tokens = tokenizer.feed("<d cmd=\"score>xp\">")
    expect(tokens).to eq([tag('d', attrs: { 'cmd' => 'score>xp' })])
  end

  it 'decodes the minimum literal entity set' do
    tokens = tokenizer.feed('&gt;&lt;&amp;&apos;&quot;')
    expect(tokens).to eq([text('><&\'"')])
  end

  it 'decodes entities inside attribute values' do
    tokens = tokenizer.feed("<a href='Tom &amp; Jerry'>")
    expect(tokens).to eq([tag('a', attrs: { 'href' => 'Tom & Jerry' })])
  end

  it 'leaves an unrecognized entity undecoded' do
    expect(tokenizer.feed('AT&amp;T &nbsp; done')).to eq([text('AT&T &nbsp; done')])
  end

  it 'buffers a tag split across two reads and emits it once complete' do
    expect(tokenizer.feed("<pushStream id='ro")).to eq([])
    expect(tokenizer.feed("om'/>")).to eq([tag('pushStream', attrs: { 'id' => 'room' }, self_closing: true)])
  end

  it 'buffers an entity split across two reads and emits decoded text once complete' do
    expect(tokenizer.feed('Tom &am')).to eq([text('Tom ')])
    expect(tokenizer.feed('p; Jerry')).to eq([text('& Jerry')])
  end

  it 'does not lose a CRLF split across two reads' do
    first  = tokenizer.feed("line one\r")
    second = tokenizer.feed("\nline two")

    expect(first.map(&:value).join + second.map(&:value).join).to eq("line one\r\nline two")
  end

  it 'holds a trailing bare "&" back until more data resolves it' do
    expect(tokenizer.feed('five &')).to eq([text('five ')])
    expect(tokenizer.feed('amp; dime')).to eq([text('& dime')])
  end
end
