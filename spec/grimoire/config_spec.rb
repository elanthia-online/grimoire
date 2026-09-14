require 'spec_helper'
require 'tmpdir'

RSpec.describe Grimoire::Config do
  # Every #load call runs through .ensure_defaults_file!, which would
  # otherwise read/write the real repo's configs/defaults.yml -- stub it to
  # a fresh tmp path per example so no spec ever touches that file.
  let(:defaults_path) { File.join(Dir.mktmpdir, 'defaults.yml') }

  before do
    stub_const('Grimoire::Config::DEFAULTS_PATH', defaults_path)
  end

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

  describe '.ensure_defaults_file!' do
    it 'creates configs/defaults.yml rendered from Theme::DEFAULT when missing' do
      described_class.ensure_defaults_file!

      expect(File.read(defaults_path)).to eq(Grimoire::ConfigTemplate.render(Grimoire::Theme::DEFAULT))
    end

    # Regression test: a defaults.yml left over from before a Theme::DEFAULT
    # change used to silently keep satisfying "not missing" forever, so
    # every config.yml it went on to seed carried stale defaults forward
    # with nothing to explain why -- reported live (2026-09-14). Regenerating
    # unconditionally removes that "stale but not missing" state entirely.
    it 'overwrites an existing (stale) defaults.yml rather than leaving it in place' do
      FileUtils.mkdir_p(File.dirname(defaults_path))
      File.write(defaults_path, 'stale content')

      described_class.ensure_defaults_file!

      expect(File.read(defaults_path)).to eq(Grimoire::ConfigTemplate.render(Grimoire::Theme::DEFAULT))
    end
  end

  describe '.load' do
    it 'creates configs/config.yml from defaults.yml when neither default path exists' do
      config_path = File.join(Dir.mktmpdir, 'configs', 'config.yml')
      xdg_path    = File.join(Dir.mktmpdir, 'config.yml')
      stub_const('Grimoire::Config::DEFAULT_PATHS', [config_path, xdg_path].freeze)

      theme = described_class.load

      expect(File).to exist(config_path)
      expect(File.read(config_path)).to eq(File.read(defaults_path))
      expect(theme).to eq(Grimoire::Theme::DEFAULT)
    end

    it 'uses the XDG path when it exists rather than creating a new config.yml' do
      config_path = File.join(Dir.mktmpdir, 'configs', 'config.yml')
      xdg_path    = write_config(<<~YAML)
        theme:
          game_window:
            bg: '#123456'
      YAML
      stub_const('Grimoire::Config::DEFAULT_PATHS', [config_path, xdg_path].freeze)

      theme = described_class.load

      expect(File).not_to exist(config_path)
      expect(theme.game_window_bg).to eq(Grimoire::Color.from_hex('#123456'))
    end

    it 'overrides only the settings a config file mentions' do
      path = write_config(<<~YAML)
        theme:
          game_window:
            bg: '#111111'
          vitals:
            health: '#ff0000'
          font:
            family: 'Fira Code'
      YAML

      theme = described_class.load(path)

      expect(theme.game_window_bg).to eq(Grimoire::Color.from_hex('#111111'))
      expect(theme.game_window_fg).to eq(Grimoire::Theme::DEFAULT.game_window_fg)
      expect(theme.vitals_colors[:health]).to eq(Grimoire::Color.from_hex('#ff0000'))
      expect(theme.vitals_colors[:mana]).to eq(Grimoire::Theme::DEFAULT.vitals_colors[:mana])
      expect(theme.font_family).to eq('Fira Code')
      expect(theme.font_size).to eq(Grimoire::Theme::DEFAULT.font_size)
    end

    it 'overrides the command bar colors/font independently of the game window' do
      path = write_config(<<~YAML)
        theme:
          command_bar:
            bg: '#111111'
            fg: '#eeeeee'
            font:
              family: 'Fira Code'
              size: 13
      YAML

      theme = described_class.load(path)

      expect(theme.command_bar_bg).to eq(Grimoire::Color.from_hex('#111111'))
      expect(theme.command_bar_fg).to eq(Grimoire::Color.from_hex('#eeeeee'))
      expect(theme.command_bar_font_family).to eq('Fira Code')
      expect(theme.command_bar_font_size).to eq(13)
      expect(theme.game_window_bg).to eq(Grimoire::Theme::DEFAULT.game_window_bg)
      expect(theme.font_family).to eq(Grimoire::Theme::DEFAULT.font_family)
    end

    it 'raises Config::Error for a non-integer command bar font size' do
      path = write_config(<<~YAML)
        theme:
          command_bar:
            font:
              size: 'huge'
      YAML

      expect { described_class.load(path) }.to raise_error(described_class::Error, /command_bar\.font\.size.*integer/)
    end

    it 'raises Config::Error for an empty command bar font family' do
      path = write_config(<<~YAML)
        theme:
          command_bar:
            font:
              family: ''
      YAML

      expect { described_class.load(path) }.to raise_error(
        described_class::Error, /command_bar\.font\.family.*non-empty string/
      )
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

    it 'overrides the roundtime label text color independently of the fill colors' do
      path = write_config(<<~YAML)
        theme:
          roundtime:
            hard: '#00ff00'
            fg: '#123456'
      YAML

      theme = described_class.load(path)

      expect(theme.roundtime_hard).to eq(Grimoire::Color.from_hex('#00ff00'))
      expect(theme.roundtime_fg).to eq(Grimoire::Color.from_hex('#123456'))
    end

    it 'overrides padding_bg independently of the game window colors' do
      path = write_config(<<~YAML)
        theme:
          global:
            padding_bg: '#333333'
      YAML

      theme = described_class.load(path)

      expect(theme.padding_bg).to eq(Grimoire::Color.from_hex('#333333'))
      expect(theme.game_window_bg).to eq(Grimoire::Theme::DEFAULT.game_window_bg)
    end

    it 'overrides the title bar colors independently of the game window colors' do
      path = write_config(<<~YAML)
        theme:
          title_bar:
            bg: '#222222'
            fg: '#eeeeee'
      YAML

      theme = described_class.load(path)

      expect(theme.title_bar_bg).to eq(Grimoire::Color.from_hex('#222222'))
      expect(theme.title_bar_fg).to eq(Grimoire::Color.from_hex('#eeeeee'))
      expect(theme.game_window_bg).to eq(Grimoire::Theme::DEFAULT.game_window_bg)
    end

    it 'overrides the global padding independently of the game-window border color/width' do
      path = write_config(<<~YAML)
        theme:
          global:
            padding: 8
          game_window:
            border:
              color: '#ff00ff'
              width: 2
      YAML

      theme = described_class.load(path)

      expect(theme.padding).to eq(8)
      expect(theme.border_color).to eq(Grimoire::Color.from_hex('#ff00ff'))
      expect(theme.border_width).to eq(2)
    end

    it 'overrides the vitals border color/width independently of the vitals fill colors' do
      path = write_config(<<~YAML)
        theme:
          vitals:
            health: '#ff0000'
            border:
              color: '#00ffff'
              width: 1
      YAML

      theme = described_class.load(path)

      expect(theme.vitals_colors[:health]).to eq(Grimoire::Color.from_hex('#ff0000'))
      expect(theme.vitals_border_color).to eq(Grimoire::Color.from_hex('#00ffff'))
      expect(theme.vitals_border_width).to eq(1)
    end

    it 'overrides the vitals label text color independently of the fill colors' do
      path = write_config(<<~YAML)
        theme:
          vitals:
            health: '#ff0000'
            fg: '#123456'
      YAML

      theme = described_class.load(path)

      expect(theme.vitals_colors[:health]).to eq(Grimoire::Color.from_hex('#ff0000'))
      expect(theme.vitals_fg).to eq(Grimoire::Color.from_hex('#123456'))
    end

    it 'overrides the status-indicator label color independently of the vitals label text color' do
      path = write_config(<<~YAML)
        theme:
          vitals:
            fg: '#123456'
            indicator_fg: '#abcdef'
      YAML

      theme = described_class.load(path)

      expect(theme.vitals_fg).to eq(Grimoire::Color.from_hex('#123456'))
      expect(theme.indicator_fg).to eq(Grimoire::Color.from_hex('#abcdef'))
    end

    it 'ignores a legacy vitals.background key rather than erroring, since it is no longer a setting' do
      path = write_config(<<~YAML)
        theme:
          vitals:
            background: '#ff00ff'
      YAML

      expect { described_class.load(path) }.not_to raise_error
    end

    it 'returns a theme equal to the default for an empty file, filling it in on disk' do
      path = write_config('')

      expect(described_class.load(path)).to eq(Grimoire::Theme::DEFAULT)
      expect(File.read(path)).to eq(Grimoire::ConfigTemplate.render(Grimoire::Theme::DEFAULT))
    end

    it 'fills in a key a newer version added, preserving values the file already set' do
      path = write_config(<<~YAML)
        theme:
          game_window:
            bg: '#111111'
      YAML

      theme = described_class.load(path)

      expect(theme.game_window_bg).to eq(Grimoire::Color.from_hex('#111111'))
      rewritten = File.read(path)
      expect(rewritten).to include("bg: '#111111'")
      expect(rewritten).to include('title_bar:')
      expect(rewritten).to include("width: #{Grimoire::Theme::DEFAULT.border_width}")
    end

    it 'does not rewrite config.yml when every key is already present' do
      path = write_config(Grimoire::ConfigTemplate.render(Grimoire::Theme::DEFAULT))
      original_contents = File.read(path)

      described_class.load(path)

      expect(File.read(path)).to eq(original_contents)
    end

    it 'raises Config::Error for malformed YAML' do
      path = write_config("theme:\n  game_window: [unbalanced\n")

      expect { described_class.load(path) }.to raise_error(described_class::Error, /invalid YAML/)
    end

    it 'raises Config::Error when the top level is not a mapping' do
      path = write_config('- just a list')

      expect { described_class.load(path) }.to raise_error(described_class::Error, /top level must be a mapping/)
    end

    it 'raises Config::Error for an invalid color value, naming the file and the setting' do
      path = write_config(<<~YAML)
        theme:
          vitals:
            health: 'not-a-color'
      YAML

      expect { described_class.load(path) }.to raise_error(
        described_class::Error, /#{Regexp.escape(path)}.*vitals\.health.*invalid color/
      )
    end

    it 'raises Config::Error for a non-integer font size' do
      path = write_config(<<~YAML)
        theme:
          font:
            size: 'huge'
      YAML

      expect { described_class.load(path) }.to raise_error(described_class::Error, /font\.size.*integer/)
    end

    it 'raises Config::Error for a zero or negative font size' do
      path = write_config(<<~YAML)
        theme:
          font:
            size: 0
      YAML

      expect { described_class.load(path) }.to raise_error(described_class::Error, /font\.size.*>= 1/)
    end

    it 'raises Config::Error for a negative padding value' do
      path = write_config(<<~YAML)
        theme:
          global:
            padding: -1
      YAML

      expect { described_class.load(path) }.to raise_error(described_class::Error, /global\.padding.*>= 0/)
    end

    it 'raises Config::Error for a negative game-window border width' do
      path = write_config(<<~YAML)
        theme:
          game_window:
            border:
              width: -1
      YAML

      expect { described_class.load(path) }.to raise_error(described_class::Error, /game_window\.border\.width.*>= 0/)
    end

    it 'raises Config::Error for a negative vitals border width' do
      path = write_config(<<~YAML)
        theme:
          vitals:
            border:
              width: -1
      YAML

      expect { described_class.load(path) }.to raise_error(described_class::Error, /vitals\.border\.width.*>= 0/)
    end

    it 'allows a zero border width and zero padding (the valid "off" values)' do
      path = write_config(<<~YAML)
        theme:
          global:
            padding: 0
          game_window:
            border:
              width: 0
      YAML

      theme = described_class.load(path)

      expect(theme.padding).to eq(0)
      expect(theme.border_width).to eq(0)
    end

    it 'raises Config::Error for an empty font family' do
      path = write_config(<<~YAML)
        theme:
          font:
            family: ''
      YAML

      expect { described_class.load(path) }.to raise_error(described_class::Error, /font\.family.*non-empty string/)
    end

    it 'raises Config::Error for a non-string font family' do
      path = write_config(<<~YAML)
        theme:
          font:
            family: 42
      YAML

      expect { described_class.load(path) }.to raise_error(described_class::Error, /font\.family.*non-empty string/)
    end

    it 'raises Config::Error for an explicit path that does not exist' do
      expect { described_class.load('/no/such/config.yml') }.to raise_error(described_class::Error, /no such file/)
    end
  end
end
