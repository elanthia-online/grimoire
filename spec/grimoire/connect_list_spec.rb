require 'spec_helper'

RSpec.describe Grimoire::ConnectList do
  def favorite(char_name, game_code = 'GS3', game_name: 'GemStone IV')
    Grimoire::LichInstall::Entry.new(
      user_id: 'ALPHA', char_name: char_name, game_code: game_code, game_name: game_name, favorite: true, favorite_order: nil
    )
  end

  def session(character, port)
    Grimoire::SessionLocator::Session.new(character: character, host: '127.0.0.1', port: port, error: nil)
  end

  def build(favorites: [], sessions: [], attached_ports: [], launching: [])
    described_class.build(
      favorites: favorites, sessions: sessions,
      attached: ->(_host, port) { attached_ports.include?(port) }, launching: launching
    )
  end

  def summary(rows)
    rows.map { |row| [row.character, row.status] }
  end

  it 'is empty with no favorites and nothing running' do
    expect(build).to eq([])
  end

  it 'lists favorites in the order given, not running by default' do
    rows = build(favorites: [favorite('Zephyr'), favorite('Aldous')])

    expect(summary(rows)).to eq([['Zephyr', :not_running], ['Aldous', :not_running]])
    expect(rows.first.game).to eq('GemStone IV')
    expect(rows.first.entry.char_name).to eq('Zephyr')
  end

  it 'falls back to the game code when a favorite has no game name' do
    expect(build(favorites: [favorite('Zephyr', 'GSF', game_name: nil)]).first.game).to eq('GSF')
  end

  it 'marks a favorite with a session file as running, matching names case-insensitively' do
    rows = build(favorites: [favorite('Zephyr')], sessions: [session('zephyr', 4100)])

    expect(summary(rows)).to eq([['Zephyr', :running]])
    expect(rows.first.session.port).to eq(4100)
  end

  it 'marks a session already open in a tab as attached' do
    rows = build(favorites: [favorite('Zephyr')], sessions: [session('Zephyr', 4100)], attached_ports: [4100])

    expect(summary(rows)).to eq([['Zephyr', :attached]])
  end

  it 'marks a favorite being launched, even once its session file appears' do
    expect(summary(build(favorites: [favorite('Zephyr')], launching: ['zephyr']))).to eq([['Zephyr', :launching]])
    expect(summary(build(favorites: [favorite('Zephyr')], sessions: [session('Zephyr', 4100)], launching: ['Zephyr'])))
      .to eq([['Zephyr', :launching]])
  end

  it 'lists running sessions that are not favorites after the favorites, by name' do
    rows = build(favorites: [favorite('Zephyr')], sessions: [session('Wren', 4102), session('Brisk', 4101)])

    expect(summary(rows)).to eq([['Zephyr', :not_running], ['Brisk', :running], ['Wren', :running]])
    expect(rows.last.entry).to be_nil
  end

  it 'lists running sessions with no favorites at all, as when lich.dir is unset' do
    rows = build(sessions: [session('Wren', 4102)], attached_ports: [4102])

    expect(summary(rows)).to eq([['Wren', :attached]])
  end

  it 'ignores session files that are not valid' do
    broken = Grimoire::SessionLocator::Session.new(character: 'Wren', host: nil, port: nil, error: 'malformed')

    expect(build(favorites: [favorite('Wren')], sessions: [broken]).map(&:status)).to eq([:not_running])
  end

  it 'shows one running session on both rows of a character saved in two games' do
    rows = build(favorites: [favorite('Zephyr', 'GS3'), favorite('Zephyr', 'GSF')], sessions: [session('Zephyr', 4100)])

    expect(rows.map(&:status)).to eq(%i[running running])
  end
end
