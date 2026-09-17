require 'spec_helper'

RSpec.describe Grimoire::AccountGuard do
  def entry(user_id, char_name, game_code = 'GS3', favorite: true)
    Grimoire::LichInstall::Entry.new(
      user_id: user_id, char_name: char_name, game_code: game_code, game_name: nil, favorite: favorite, favorite_order: nil
    )
  end

  def running(character)
    Grimoire::SessionLocator::Session.new(character: character, host: '127.0.0.1', port: 8000, error: nil)
  end

  def broken(character)
    Grimoire::SessionLocator::Session.new(character: character, host: nil, port: nil, error: 'malformed session file')
  end

  let(:zephyr) { entry('ALPHA', 'Zephyr') }
  let(:entries) do
    [
      zephyr,
      entry('ALPHA', 'Brisk', favorite: false),
      entry('ALPHA', 'Aldous'),
      entry('BETA', 'Morrow', 'DR'),
    ]
  end

  def siblings(target, sessions)
    described_class.running_siblings(target, entries: entries, sessions: sessions).map(&:char_name)
  end

  it 'is empty when nothing is running' do
    expect(siblings(zephyr, [])).to eq([])
  end

  it 'finds a running character on the same account' do
    expect(siblings(zephyr, [running('Aldous')])).to eq(['Aldous'])
  end

  it 'finds a running sibling that is not a favorite' do
    expect(siblings(zephyr, [running('Brisk')])).to eq(['Brisk'])
  end

  it 'ignores a running character on a different account' do
    expect(siblings(zephyr, [running('Morrow')])).to eq([])
  end

  it 'ignores the target character itself already running' do
    expect(siblings(zephyr, [running('Zephyr')])).to eq([])
  end

  it 'ignores a session file that is not valid' do
    expect(siblings(zephyr, [broken('Aldous')])).to eq([])
  end

  it 'matches names and accounts case-insensitively' do
    lowercase_target = entry('alpha', 'zephyr')

    expect(siblings(lowercase_target, [running('aldous')])).to eq(['Aldous'])
  end

  it 'reports a sibling saved in two game instances once' do
    entries << entry('ALPHA', 'Aldous', 'GSF')

    expect(siblings(zephyr, [running('Aldous')])).to eq(['Aldous'])
  end

  it 'finds a running sibling on another instance of the same game' do
    entries << entry('ALPHA', 'Tester', 'GST')

    expect(siblings(zephyr, [running('Tester')])).to eq(['Tester'])
  end

  # GemStone and DragonRealms are separate logins, so a running character in
  # the other game never collides, even under the same account name.
  it 'ignores a running character on the same account name in the other game' do
    entries << entry('ALPHA', 'Drifter', 'DRF')

    expect(siblings(zephyr, [running('Drifter')])).to eq([])
  end

  it 'reports every running sibling' do
    expect(siblings(zephyr, [running('Aldous'), running('Brisk'), running('Morrow')])).to contain_exactly('Aldous', 'Brisk')
  end
end
