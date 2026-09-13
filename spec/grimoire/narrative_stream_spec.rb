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
end
