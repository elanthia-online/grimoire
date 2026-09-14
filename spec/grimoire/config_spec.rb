require 'spec_helper'
require 'tmpdir'

RSpec.describe Grimoire::Config do
  def write_config(contents)
    dir  = Dir.mktmpdir
    path = File.join(dir, 'config.yml')
    File.write(path, contents)
    path
  end

  describe 'DEFAULT_PATHS' do
    it 'checks configs/config.yml under the working directory before the XDG-style path' do
      expect(described_class::DEFAULT_PATHS).to eq(
        [
          File.join(Dir.pwd, 'configs', 'config.yml'),
          File.join(Dir.home, '.config', 'grimoire', 'config.yml'),
        ]
      )
    end
  end

  describe '.load' do
    it 'returns the default theme when no path is given and no default file exists' do
      allow(File).to receive(:file?).and_return(false)

      expect(described_class.load).to eq(Grimoire::Theme::DEFAULT)
    end

    it 'overrides only the settings a config file mentions' do
      path = write_config(<<~YAML)
        theme:
          main:
            background: '#111111'
          vitals:
            health: '#ff0000'
          font:
            family: 'Fira Code'
      YAML

      theme = described_class.load(path)

      expect(theme.main_background).to eq(Grimoire::Color.from_hex('#111111'))
      expect(theme.main_foreground).to eq(Grimoire::Theme::DEFAULT.main_foreground)
      expect(theme.vitals_colors[:health]).to eq(Grimoire::Color.from_hex('#ff0000'))
      expect(theme.vitals_colors[:mana]).to eq(Grimoire::Theme::DEFAULT.vitals_colors[:mana])
      expect(theme.font_family).to eq('Fira Code')
      expect(theme.font_size).to eq(Grimoire::Theme::DEFAULT.font_size)
    end

    it 'overrides the roundtime colors independently of the vitals colors' do
      path = write_config(<<~YAML)
        theme:
          roundtime:
            hard: '#00ff00'
      YAML

      theme = described_class.load(path)

      expect(theme.roundtime_hard).to eq(Grimoire::Color.from_hex('#00ff00'))
      expect(theme.roundtime_cast).to eq(Grimoire::Theme::DEFAULT.roundtime_cast)
    end

    it 'returns the default theme untouched for an empty file' do
      path = write_config('')

      expect(described_class.load(path)).to eq(Grimoire::Theme::DEFAULT)
    end

    it 'raises Config::Error for malformed YAML' do
      path = write_config("theme:\n  main: [unbalanced\n")

      expect { described_class.load(path) }.to raise_error(described_class::Error, /invalid YAML/)
    end

    it 'raises Config::Error when the top level is not a mapping' do
      path = write_config('- just a list')

      expect { described_class.load(path) }.to raise_error(described_class::Error, /top level must be a mapping/)
    end

    it 'raises Config::Error for an invalid color value, naming the file' do
      path = write_config(<<~YAML)
        theme:
          vitals:
            health: 'not-a-color'
      YAML

      expect { described_class.load(path) }.to raise_error(described_class::Error, /#{Regexp.escape(path)}.*invalid color/)
    end

    it 'raises Config::Error for an explicit path that does not exist' do
      expect { described_class.load('/no/such/config.yml') }.to raise_error(described_class::Error, /no such file/)
    end
  end
end
