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

  describe 'command echo rewriting' do
    # A ">>> <command>" line was initially assumed to be Lich's own echo of
    # a submitted command (based on a sample in _references/session-logs);
    # real captures showed Lich never echoes a command at all, so this
    # rewrite is a harmless no-op safeguard rather than the confirmed
    # mechanism -- see docs/decisions.md and App#handle_command's own local
    # echo, which is what real usage actually relies on.

    it 'rewrites a ">>> <command>" echo to "> <command>" using the default prompt character' do
      expect(narrative.feed(">>> look\r\n")).to eq("> look\r\n")
    end

    it 'uses a custom prompt character when given one' do
      custom = described_class.new(prompt_char: '$')

      expect(custom.feed(">>> look\r\n")).to eq("$ look\r\n")
    end

    it 'only rewrites the echo marker at the very start of the line' do
      text = narrative.feed("Sarah says, \"look at that >>> sign.\"\r\n")

      expect(text).to eq("Sarah says, \"look at that >>> sign.\"\r\n")
    end
  end

  describe 'orphaned line terminators after a squelch' do
    # Lich delivers one line at a time, each still carrying its own
    # terminator (confirmed CRLF in sibling project rift-nexus's own
    # decisions.md). A tag that is squelched in full and occupies an
    # entire line leaves that line's terminator stranded as ordinary text
    # arriving after the tracker has already flipped back to narrative.
    # Once real narrative text has already appeared earlier in the
    # session, that terminator is kept as the one separator between the
    # narrative before the squelch and whatever comes after -- so distinct
    # completed outputs stay visually separated instead of running
    # together. Before any real narrative text has appeared yet, it is
    # still dropped as pure noise (see the PanelTagTracker squelch-only
    # fixtures below, which have no narrative text on either side).

    it 'leaves exactly one blank line after a prompt that occupies its own line' do
      lines = ["You stand in a room.\r\n", "<prompt time=\"1\">&gt;</prompt>\r\n", "You swing your sword.\r\n"]

      text = lines.map { |line| narrative.feed(line) }.join

      expect(text).to eq("You stand in a room.\r\n\r\nYou swing your sword.\r\n")
    end

    it 'leaves exactly one blank line after a bare room-update component on its own line' do
      lines = ["You stand in a room.\r\n", "<component id='room objs'>A banshee appears.</component>\r\n",
               "You swing your sword.\r\n"]

      text = lines.map { |line| narrative.feed(line) }.join

      expect(text).to eq("You stand in a room.\r\n\r\nYou swing your sword.\r\n")
    end

    it 'leaves exactly one blank line after a pushStream/popStream bracket on its own line' do
      lines = ["You see a rusty dagger.\r\n", "<pushStream id=\"inv\"/>hidden\r\n<popStream/>\r\n",
               "back to the room.\r\n"]

      text = lines.map { |line| narrative.feed(line) }.join

      expect(text).to eq("You see a rusty dagger.\r\n\r\nback to the room.\r\n")
    end

    it 'collapses a run of several consecutive squelched lines to just one blank line, not one per line' do
      lines = [
        "You stand in a room.\r\n",
        "<prompt time=\"1\">&gt;</prompt>\r\n",
        "<component id='room objs'>A banshee appears.</component>\r\n",
        "<dialogData id=\"injuries\"><image id=\"head\" name=\"head\" height=\"0\" width=\"0\"/></dialogData>\r\n",
        "You swing your sword.\r\n",
      ]

      text = lines.map { |line| narrative.feed(line) }.join

      expect(text).to eq("You stand in a room.\r\n\r\nYou swing your sword.\r\n")
    end

    it 'drops the orphaned terminator with no separator when nothing narrative has appeared yet' do
      lines = ["<prompt time=\"1\">&gt;</prompt>\r\n", "You swing your sword.\r\n"]

      text = lines.map { |line| narrative.feed(line) }.join

      expect(text).to eq("You swing your sword.\r\n")
    end

    it 'still keeps a genuine blank line that follows a squelched line, not just the orphaned one' do
      lines = ["<prompt time=\"1\">&gt;</prompt>\r\n", "\r\n", "Next narrative.\r\n"]

      text = lines.map { |line| narrative.feed(line) }.join

      expect(text).to eq("\r\nNext narrative.\r\n")
    end
  end

  describe 'squelching GUI-panel/status tags (PanelTagTracker)' do
    # These reproduce exact lines pulled from a real live-captured session
    # (log/session-8000-20260913-153637-raw.log) that leaked into the
    # scrollback before PanelTagTracker existed -- see docs/decisions.md.

    it 'drops a lone self-closing status tag instead of leaving a blank line' do
      text = narrative.feed('<roommeta weather="0" bonfire="0" inside="0" water="0" ' \
                             'sanctuary="1" realm="0" climate="6" terrain="10"/>' \
                             "\r\n")

      expect(text).to eq('')
    end

    it 'drops spell/left/right hand-state tags instead of leaking their bare values' do
      # The real line this reproduces (Lich's initial vitals push) produced
      # "Nonegreen crackersEmpty" before PanelTagTracker existed -- see
      # docs/decisions.md. Since every tag on this line is squelched, the
      # line's own trailing terminator is correctly swallowed too, the
      # same as the lone-<roommeta/>-line case above.
      text = narrative.feed(
        "<spell>None</spell><indicator id='IconSTANDING' visible='y'/>" \
        "<right>green crackers</right><left>Empty</left>\r\n"
      )

      expect(text).to eq('')
    end

    it 'drops a dialogData panel block, including its self-closing children' do
      text = narrative.feed(
        "<dialogData id='Cooldowns' clear='t'></dialogData><dialogData id='Cooldowns'>" \
        "<progressBar id='1' value='14' text=\"Adrenal Surge\" time='00:00:42'/>" \
        "<label id='l1' value='42s ' /></dialogData>\r\n"
      )

      expect(text).to eq('')
    end

    it 'keeps real narrative text around a squelched tag on the same line' do
      text = narrative.feed('<resource picture="0"/><style id="roomName" />[Shattered Nexus - 20239] (u7199)' \
                             "\r\n")

      expect(text).to eq("[Shattered Nexus - 20239] (u7199)\r\n")
    end
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

    it 'drops an entire move-triggered room-entry bracket and routes it into room_state instead' do
      text = narrative.feed(fixture('room_transition.xml'))

      # .strip (not eq('')) only to tolerate the blank line this fixture file itself inserts
      # between its two spliced-together excerpts from different points in the same real
      # session -- not a stand-in for the orphaned-line-terminator bug covered separately
      # above, which this fixture's own brackets no longer exhibit either.
      expect(text.strip).to eq('')
      # The fixture's second, later excerpt (a different real session, a different room) is
      # what room_state ends up holding -- a real room entry resets every field, so this also
      # confirms the first excerpt's objects/players/exits do not linger.
      expect(narrative.room_state.number).to eq('3201029')
      expect(narrative.room_state.title).to eq('Gardenia Commons - 3201029')
      expect(narrative.room_state.description).to eq('[Room window disabled at this location.]')
      expect(narrative.room_state.objects).to be_nil
    end

    it 'keeps real narrative text from a periodic room-update chunk, routing the rest into room_state' do
      text = narrative.feed(fixture('room_update.xml'))

      expect(text).to include('Sugi chants a short but reverent orison')
      expect(text).not_to include('&gt;')
      expect(text).not_to include('smouldering skeletal dreadsteed')
      expect(text).not_to include('Also here:')
      expect(narrative.room_state.objects).to include('smouldering skeletal dreadsteed')
      expect(narrative.room_state.players).to eq('Also here: Kleterae, Thioniobre, Sugi')
    end

    it 'drops the initial vitals push into vitals_state and keeps narrative text around later updates' do
      text = narrative.feed(fixture('vitals.xml'))

      expect(text).not_to include('mana 132/655')
      expect(text).to include('You focus on Ganz and narrow your concentration')
      expect(text).to include('You infuse Ganz with your own strength')

      expect(narrative.vitals_state.health.text).to eq('health 351/355')
      expect(narrative.vitals_state.mana.text).to eq('mana 132/655')
      # The fixture's init line carries Lich's real value='0' init-push bug
      # (see VitalsTracker::FRACTION_TEXT_IDS/docs/decisions.md) -- spirit
      # is 10/10 on the wire despite that, and VitalsTracker now derives
      # 100 from the text rather than trusting the buggy value.
      expect(narrative.vitals_state.spirit.percent).to eq(100)
      expect(narrative.vitals_state.stance).to eq(80)
      expect(narrative.vitals_state.mind.text).to eq('must rest')
      expect(narrative.vitals_state.encumbrance.text).to eq('None')
      expect(narrative.vitals_state.indicators['IconSTANDING']).to be(true)
      expect(narrative.vitals_state.indicators['IconBLEEDING']).to be(true)
    end
  end
end
