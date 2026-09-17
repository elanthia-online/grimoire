require 'spec_helper'
require 'fileutils'
require 'tmpdir'

RSpec.describe Grimoire::LichInstall do
  around do |example|
    Dir.mktmpdir do |dir|
      @lich_dir = dir
      example.run
    end
  end

  def install
    described_class.new(@lich_dir)
  end

  def write_lich_rbw
    File.write(File.join(@lich_dir, 'lich.rbw'), "# lich.rbw stand-in\n")
  end

  def write_entry_yaml(contents)
    FileUtils.mkdir_p(File.join(@lich_dir, 'data'))
    File.write(File.join(@lich_dir, 'data', 'entry.yaml'), contents)
  end

  def use_fixture_install
    write_lich_rbw
    write_entry_yaml(File.read(File.join(FixtureHelpers::FIXTURE_DIR, 'entry.yaml')))
  end

  describe '#dir' do
    it 'expands ~ and relative paths' do
      expect(described_class.new('~/lich-5').dir).to eq(File.join(Dir.home, 'lich-5'))
      expect(described_class.new('lich-5').dir).to eq(File.join(Dir.pwd, 'lich-5'))
    end
  end

  describe '#problem' do
    it 'is nil when lich.rbw and data/entry.yaml both exist' do
      use_fixture_install

      expect(install.problem).to be_nil
    end

    it 'reports a directory that does not exist' do
      missing = described_class.new(File.join(@lich_dir, 'nope'))

      expect(missing.problem).to match(/nope: no such directory/)
    end

    it 'reports a missing lich.rbw' do
      write_entry_yaml("accounts: {}\n")

      expect(install.problem).to match(%r{/lich\.rbw: not found})
    end

    it 'reports a missing data/entry.yaml' do
      write_lich_rbw

      expect(install.problem).to match(%r{/data/entry\.yaml: not found})
    end
  end

  describe '#entries' do
    before { use_fixture_install }

    it 'returns every saved character across accounts, favorite or not, in file order' do
      names = install.entries.map { |entry| [entry.user_id, entry.char_name, entry.game_code] }

      expect(names).to eq(
        [
          %w[ALPHA Zephyr GS3], %w[ALPHA Zephyr GS3], %w[ALPHA Zephyr GSF], %w[ALPHA Brisk GS3], %w[ALPHA Aldous GS3],
          %w[BETA Morrow DR], %w[BETA Quill DR],
        ]
      )
    end

    it 'carries favorite status and order' do
      brisk  = install.entries.find { |entry| entry.char_name == 'Brisk' }
      aldous = install.entries.find { |entry| entry.char_name == 'Aldous' }

      expect(brisk.favorite?).to be(false)
      expect(aldous.favorite?).to be(true)
      expect(aldous.favorite_order).to be_nil
    end

    it 'skips a character record with no name' do
      expect(install.entries.map(&:char_name)).to all(be_a(String))
    end

    it 'never carries a password out of the file' do
      carried = install.entries.flat_map(&:to_a).map(&:to_s)

      expect(carried.grep(/fixture-password/)).to be_empty
      expect(described_class::Entry.members).not_to include(:password)
    end

    it 'returns no entries for a file with no accounts' do
      write_entry_yaml("encryption_mode: plaintext\n")

      expect(install.entries).to eq([])
    end

    it 'returns no entries for an empty file' do
      write_entry_yaml('')

      expect(install.entries).to eq([])
    end

    it 'raises Error for malformed YAML' do
      write_entry_yaml("accounts: [unbalanced\n")

      expect { install.entries }.to raise_error(described_class::Error, /invalid YAML/)
    end

    it 'raises Error when the top level is not a mapping' do
      write_entry_yaml("- just a list\n")

      expect { install.entries }.to raise_error(described_class::Error, /top level must be a mapping/)
    end

    it 'raises Error when accounts is not a mapping' do
      write_entry_yaml("accounts: [ALPHA]\n")

      expect { install.entries }.to raise_error(described_class::Error, /accounts must be a mapping/)
    end

    it 'raises Error when entry.yaml is missing' do
      FileUtils.rm(install.entry_yaml_path)

      expect { install.entries }.to raise_error(described_class::Error, /cannot read/)
    end

    # entry.yaml is Lich's own file; grimoire must never rewrite it.
    it 'leaves entry.yaml untouched' do
      before_contents = File.read(install.entry_yaml_path)
      before_mtime    = File.mtime(install.entry_yaml_path)

      install.favorites

      expect(File.read(install.entry_yaml_path)).to eq(before_contents)
      expect(File.mtime(install.entry_yaml_path)).to eq(before_mtime)
    end
  end

  describe '#favorites' do
    before { use_fixture_install }

    it 'lists favorites only, ordered by favorite_order with unordered ones last' do
      order = install.favorites.map { |entry| [entry.char_name, entry.game_code] }

      expect(order).to eq([%w[Morrow DR], %w[Zephyr GS3], %w[Zephyr GSF], %w[Aldous GS3]])
    end

    it 'collapses entries that differ only by frontend, keeping the lower favorite_order' do
      zephyr_gs3 = install.favorites.select { |entry| entry.char_name == 'Zephyr' && entry.game_code == 'GS3' }

      expect(zephyr_gs3.size).to eq(1)
      expect(zephyr_gs3.first.favorite_order).to eq(2)
    end

    it 'keeps one character saved in two game instances as two favorites' do
      zephyr_games = install.favorites.select { |entry| entry.char_name == 'Zephyr' }.map(&:game_code)

      expect(zephyr_games).to eq(%w[GS3 GSF])
    end

    it 'breaks favorite_order ties by name, case-insensitively' do
      write_entry_yaml(<<~YAML)
        accounts:
          ALPHA:
            characters:
            - { char_name: zed, game_code: GS3, is_favorite: true }
            - { char_name: Abe, game_code: GS3, is_favorite: true }
      YAML

      expect(install.favorites.map(&:char_name)).to eq(%w[Abe zed])
    end
  end
end
