require 'spec_helper'

RSpec.describe Grimoire::VitalsTracker do
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

  %w[health mana stamina spirit].each do |id|
    it "captures the #{id} progressBar into vitals_state and reports it as not narrative" do
      routed = tracker.route(tag('progressBar', attrs: { 'id' => id, 'value' => '98', 'text' => "#{id} 351/355" },
                                                self_closing: true))

      expect(routed).not_to be_narrative
      vital = tracker.vitals_state.public_send(id)
      expect(vital.percent).to eq(98)
      expect(vital.text).to eq("#{id} 351/355")
    end
  end

  # Real bug in Lich versions before the per-game init push, confirmed
  # against lich-5 source and reproduced in spec/fixtures/vitals.xml's init
  # line: the one-time initial push to a newly-attached frontend hardcoded
  # value='0' for health/mana/stamina/spirit regardless of the character's
  # actual vitals, while text still carried the correct current/max numbers.
  # Newer Lich sends a matching real value, but older Lich is still in use.
  # ProfanityFE already derives the percent from text for this exact
  # reason -- see docs/decisions.md.
  it 'derives percent from text current/max, ignoring a stale/buggy value attribute' do
    routed = tracker.route(tag('progressBar', attrs: { 'id' => 'mana', 'value' => '0', 'text' => 'mana 132/655' },
                                              self_closing: true))

    expect(routed).not_to be_narrative
    expect(tracker.vitals_state.mana.percent).to eq(20)
    expect(tracker.vitals_state.mana.text).to eq('mana 132/655')
  end

  # The game clamps the percent to 0 for a negative current but still
  # reports the raw negative number in text.
  it 'clamps a negative current to 0 percent while keeping the raw negative text' do
    tracker.route(tag('progressBar', attrs: { 'id' => 'health', 'value' => '0', 'text' => 'health -5/355' },
                                     self_closing: true))

    expect(tracker.vitals_state.health.percent).to eq(0)
    expect(tracker.vitals_state.health.text).to eq('health -5/355')
  end

  it 'falls back to the wire value when text carries no current/max fraction' do
    tracker.route(tag('progressBar', attrs: { 'id' => 'health', 'value' => '42' }, self_closing: true))

    expect(tracker.vitals_state.health.percent).to eq(42)
  end

  it 'falls back to the wire value rather than dividing by a zero max' do
    tracker.route(tag('progressBar', attrs: { 'id' => 'stamina', 'value' => '37', 'text' => 'stamina 0/0' },
                                     self_closing: true))

    expect(tracker.vitals_state.stamina.percent).to eq(37)
  end

  it 'does not derive a percent for mindState/encumlevel, which never carry a current/max text' do
    tracker.route(tag('progressBar', attrs: { 'id' => 'encumlevel', 'value' => '15', 'text' => 'Light 5/50' },
                                     self_closing: true))

    expect(tracker.vitals_state.encumbrance.percent).to eq(15)
  end

  it 'captures mindState into vitals_state.mind' do
    tracker.route(tag('progressBar', attrs: { 'id' => 'mindState', 'value' => '100', 'text' => 'must rest' },
                                     self_closing: true))

    expect(tracker.vitals_state.mind.percent).to eq(100)
    expect(tracker.vitals_state.mind.text).to eq('must rest')
  end

  it 'captures encumlevel into vitals_state.encumbrance' do
    tracker.route(tag('progressBar', attrs: { 'id' => 'encumlevel', 'value' => '0', 'text' => 'None' },
                                     self_closing: true))

    expect(tracker.vitals_state.encumbrance.percent).to eq(0)
    expect(tracker.vitals_state.encumbrance.text).to eq('None')
  end

  it 'captures pbarStance as a bare percent, with no text attribute on the wire' do
    tracker.route(tag('progressBar', attrs: { 'id' => 'pbarStance', 'value' => '80' }, self_closing: true))

    expect(tracker.vitals_state.stance).to eq(80)
  end

  it 'captures an indicator id into vitals_state.indicators' do
    tracker.route(tag('indicator', attrs: { 'id' => 'IconBLEEDING', 'visible' => 'y' }, self_closing: true))

    expect(tracker.vitals_state.indicators['IconBLEEDING']).to be(true)
  end

  it 'drops an unrecognized progressBar id (a buff/spell timer) without exposing it in vitals_state' do
    routed = tracker.route(tag('progressBar', attrs: { 'id' => '1125', 'value' => '79', 'text' => "Troll's Blood" },
                                              self_closing: true))

    expect(routed).not_to be_narrative
    expect(tracker.vitals_state.health).to be_nil
  end

  it 'drops the experience bar (nextLvlPB) without exposing it in vitals_state' do
    routed = tracker.route(tag('progressBar', attrs: { 'id' => 'nextLvlPB', 'value' => '100' },
                                              self_closing: true))

    expect(routed).not_to be_narrative
  end

  it 'captures a roundTime tag into vitals_state.roundtime_end and reports it as not narrative' do
    routed = tracker.route(tag('roundTime', attrs: { 'value' => '1788826158' }, self_closing: true))

    expect(routed).not_to be_narrative
    expect(tracker.vitals_state.roundtime_end).to eq(1_788_826_158)
  end

  it 'captures a castTime tag into vitals_state.cast_roundtime_end and reports it as not narrative' do
    routed = tracker.route(tag('castTime', attrs: { 'value' => '1788826158' }, self_closing: true))

    expect(routed).not_to be_narrative
    expect(tracker.vitals_state.cast_roundtime_end).to eq(1_788_826_158)
  end

  it 'tracks roundTime and castTime independently, neither overwriting the other' do
    tracker.route(tag('roundTime', attrs: { 'value' => '100' }, self_closing: true))
    tracker.route(tag('castTime', attrs: { 'value' => '200' }, self_closing: true))

    expect(tracker.vitals_state.roundtime_end).to eq(100)
    expect(tracker.vitals_state.cast_roundtime_end).to eq(200)
  end
end
