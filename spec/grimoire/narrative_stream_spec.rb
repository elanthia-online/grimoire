require 'spec_helper'

RSpec.describe Grimoire::NarrativeStream do
  subject(:narrative) { described_class.new }

  it 'passes plain text straight through' do
    expect(narrative.feed('You are standing in a field.')).to eq('You are standing in a field.')
  end

  it 'drops text between pushStream and popStream' do
    text = narrative.feed(
      "You see a rusty dagger.\r\n<pushStream id=\"inv\"/>a rusty dagger\r\n<popStream/>back to the room.\r\n"
    )

    expect(text).to eq("You see a rusty dagger.\r\nback to the room.\r\n")
  end

  it 'drops narrative-looking text inside a stream regardless of stream id' do
    text = narrative.feed('<pushStream id="thoughts"/>You ponder deeply.<popStream/>')

    expect(text).to eq('')
  end

  it 'stays consistent across multiple feed calls (chunk boundaries)' do
    first  = narrative.feed('before <pushStream id="inv"/>hidden')
    second = narrative.feed(' still hidden<popStream/> after')

    expect(first + second).to eq('before  after')
  end

  it 'squelches the prompt marker but keeps narrative text around it' do
    text = narrative.feed('Sugi chants a short orison.<prompt time="1763306658">&gt;</prompt>')

    expect(text).to eq('Sugi chants a short orison.')
  end

  describe 'on_prompt' do
    it 'fires once per closed prompt tag with the captured time' do
      seen = []
      narrative = described_class.new(on_prompt: ->(time) { seen << time })

      narrative.feed('<prompt time="1763306658">&gt;</prompt>')
      narrative.feed('more narrative<prompt time="1763306700">&gt;</prompt>')

      expect(seen).to eq(%w[1763306658 1763306700])
    end

    it 'does not fire on the opening prompt tag' do
      seen = []
      narrative = described_class.new(on_prompt: ->(time) { seen << time })

      narrative.feed('<prompt time="1763306658">')

      expect(seen).to be_empty
    end
  end

  describe 'against real captured stream fixtures' do
    it 'keeps a bare worn-items sentence but drops the clearStream/pushStream id=inv bracket' do
      text = narrative.feed(fixture('inventory.xml'))

      expect(text).to include('You are wearing a crystal amulet')
      expect(text).not_to include('Your worn items are:')
    end

    it 'drops an entire move-triggered room-entry bracket (nav/streamWindow/compDef/popStream)' do
      text = narrative.feed(fixture('room_transition.xml'))

      expect(text.strip).to eq('')
    end

    it 'keeps real narrative text from a periodic room-update chunk, squelching its prompt marker' do
      text = narrative.feed(fixture('room_update.xml'))

      expect(text).to include('Sugi chants a short but reverent orison')
      expect(text).not_to include('&gt;')
      expect(text).not_to match(/^>\s*$/)
      # The bare <component id='room objs'|'room players'> tags in this fixture are not
      # bracketed by pushStream/popStream, so their text is not yet filtered out here --
      # tracked by TASKS.md's still-open "Route non-narrative panel tags" item. Not
      # asserted either way so this spec does not need to flip when that lands.
    end
  end
end
