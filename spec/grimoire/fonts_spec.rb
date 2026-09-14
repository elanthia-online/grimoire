require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe Grimoire::Fonts do
  describe '.font_files' do
    it 'finds the real bundled Overpass/Overpass Mono files under assets/fonts' do
      expect(described_class.font_files).not_to be_empty
      expect(described_class.font_files).to all(match(/\.(ttf|otf)\z/))
    end

    it 'returns an empty list rather than raising when the directory does not exist' do
      stub_const('Grimoire::Fonts::DIR', '/no/such/directory')

      expect(described_class.font_files).to eq([])
    end

    it 'finds .ttf and .otf files anywhere under the directory, recursively' do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, 'overpass-mono'))
        ttf = File.join(dir, 'top-level.ttf')
        otf = File.join(dir, 'overpass-mono', 'nested.otf')
        txt = File.join(dir, 'README.md')
        [ttf, otf, txt].each { |path| File.write(path, '') }
        stub_const('Grimoire::Fonts::DIR', dir)

        expect(described_class.font_files).to contain_exactly(ttf, otf)
      end
    end
  end

  describe '.load_bundled!' do
    # Pango::CairoFontMap's real methods are generated dynamically via
    # GObject Introspection rather than declared statically on the class,
    # so RSpec's verifying doubles (instance_double) cannot see
    # add_font_file even though it genuinely works at runtime (confirmed
    # directly against the real Pango::CairoFontMap.default while building
    # this feature) -- a plain double stands in for the font map here.
    it 'registers every found font file with the given font map' do
      allow(described_class).to receive(:font_files).and_return(['/fonts/a.ttf', '/fonts/b.otf'])
      font_map = double('font map')
      allow(font_map).to receive(:add_font_file)

      described_class.load_bundled!(font_map: font_map)

      expect(font_map).to have_received(:add_font_file).with('/fonts/a.ttf')
      expect(font_map).to have_received(:add_font_file).with('/fonts/b.otf')
    end

    it 'does nothing, without error, when no bundled fonts exist' do
      allow(described_class).to receive(:font_files).and_return([])
      font_map = double('font map')

      expect { described_class.load_bundled!(font_map: font_map) }.not_to raise_error
    end

    it 'warns and continues rather than raising when the font map has no add_font_file (Pango < 1.52)' do
      allow(described_class).to receive(:font_files).and_return(['/fonts/a.ttf'])
      font_map_with_no_such_method = Object.new

      expect { described_class.load_bundled!(font_map: font_map_with_no_such_method) }.not_to raise_error
    end
  end
end
