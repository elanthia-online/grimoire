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
            mind: '#ff0000'
          command_bar:
            command_vitals:
              health: '#00ff00'
          font:
            family: 'Fira Code'
      YAML

      theme = described_class.load(path)

      expect(theme.game_window_bg).to eq(Grimoire::Color.from_hex('#111111'))
      expect(theme.game_window_fg).to eq(Grimoire::Theme::DEFAULT.game_window_fg)
      expect(theme.vitals_colors[:mind]).to eq(Grimoire::Color.from_hex('#ff0000'))
      expect(theme.vitals_colors[:encumbrance]).to eq(Grimoire::Theme::DEFAULT.vitals_colors[:encumbrance])
      expect(theme.command_vitals_colors[:health]).to eq(Grimoire::Color.from_hex('#00ff00'))
      expect(theme.command_vitals_colors[:mana]).to eq(Grimoire::Theme::DEFAULT.command_vitals_colors[:mana])
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

    # GTK3's CSS engine has no max-height property (confirmed live,
    # 2026-09-15), so the command entry's height (pinned to a 32px floor
    # via Window's own min-height CSS) can only be capped from above by
    # restricting the font size that could grow it past that floor -- the
    # user's own spec (2026-09-15: "we will restrict font size").
    it 'accepts a command bar font size up to the max' do
      path = write_config(<<~YAML)
        theme:
          command_bar:
            font:
              size: 16
      YAML

      expect(described_class.load(path).command_bar_font_size).to eq(16)
    end

    it 'raises Config::Error for a command bar font size above the max' do
      path = write_config(<<~YAML)
        theme:
          command_bar:
            font:
              size: 17
      YAML

      expect { described_class.load(path) }.to raise_error(described_class::Error, /command_bar\.font\.size.*<= 16/)
    end

    it 'does not cap the scrollback font size the same way -- only command_bar_font_size has a max' do
      path = write_config(<<~YAML)
        theme:
          font:
            size: 40
      YAML

      expect(described_class.load(path).font_size).to eq(40)
    end

    it 'overrides the roundtime colors independently of the vitals colors' do
      path = write_config(<<~YAML)
        theme:
          command_bar:
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
          command_bar:
            roundtime:
              hard: '#00ff00'
              fg: '#123456'
      YAML

      theme = described_class.load(path)

      expect(theme.roundtime_hard).to eq(Grimoire::Color.from_hex('#00ff00'))
      expect(theme.roundtime_fg).to eq(Grimoire::Color.from_hex('#123456'))
    end

    it 'overrides roundtime.min_rt independently of the fill colors' do
      path = write_config(<<~YAML)
        theme:
          command_bar:
            roundtime:
              min_rt: 7
      YAML

      theme = described_class.load(path)

      expect(theme.roundtime_min_rt).to eq(7)
      expect(theme.roundtime_hard).to eq(Grimoire::Theme::DEFAULT.roundtime_hard)
    end

    it 'clamps a roundtime.min_rt below 3 up to 3, rather than raising' do
      path = write_config(<<~YAML)
        theme:
          command_bar:
            roundtime:
              min_rt: 1
      YAML

      expect(described_class.load(path).roundtime_min_rt).to eq(3)
    end

    it 'raises Config::Error for a non-integer roundtime.min_rt' do
      path = write_config(<<~YAML)
        theme:
          command_bar:
            roundtime:
              min_rt: 'fast'
      YAML

      expect { described_class.load(path) }.to raise_error(described_class::Error, /command_bar\.roundtime\.min_rt.*integer/)
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
            mind: '#ff0000'
            border:
              color: '#00ffff'
              width: 1
      YAML

      theme = described_class.load(path)

      expect(theme.vitals_colors[:mind]).to eq(Grimoire::Color.from_hex('#ff0000'))
      expect(theme.vitals_border_color).to eq(Grimoire::Color.from_hex('#00ffff'))
      expect(theme.vitals_border_width).to eq(1)
    end

    it 'overrides the command_vitals overlaid number text color independently of the fill colors' do
      path = write_config(<<~YAML)
        theme:
          command_bar:
            command_vitals:
              health: '#ff0000'
          vitals:
            fg: '#123456'
      YAML

      theme = described_class.load(path)

      expect(theme.command_vitals_colors[:health]).to eq(Grimoire::Color.from_hex('#ff0000'))
      expect(theme.vitals_fg).to eq(Grimoire::Color.from_hex('#123456'))
    end

    it 'overrides the roundtime-bar visibility independently of the other widget toggles' do
      path = write_config(<<~YAML)
        theme:
          command_bar:
            roundtime:
              enabled: false
      YAML

      theme = described_class.load(path)

      expect(theme.show_roundtime_bar).to be(false)
    end

    it 'raises Config::Error for a non-boolean command_bar.roundtime.enabled value' do
      path = write_config(<<~YAML)
        theme:
          command_bar:
            roundtime:
              enabled: 1
      YAML

      expect { described_class.load(path) }.to raise_error(
        described_class::Error, /command_bar\.roundtime\.enabled.*true or false/
      )
    end

    it 'overrides the debug menu visibility independently of the other widget toggles' do
      path = write_config(<<~YAML)
        theme:
          debug:
            enabled: true
      YAML

      theme = described_class.load(path)

      expect(theme.show_debug_menu).to be(true)
      expect(theme.show_roundtime_bar).to be(true)
    end

    it 'raises Config::Error for a non-boolean debug.enabled value' do
      path = write_config(<<~YAML)
        theme:
          debug:
            enabled: 'on'
      YAML

      expect { described_class.load(path) }.to raise_error(described_class::Error, /debug\.enabled.*true or false/)
    end

    # command_vitals.enabled defaults true (2026-09-15), so this overrides
    # it *off* to actually demonstrate the override.
    it 'overrides command_vitals enabled/show_numbers independently of every other widget toggle' do
      path = write_config(<<~YAML)
        theme:
          command_bar:
            command_vitals:
              enabled: false
              show_numbers: false
      YAML

      theme = described_class.load(path)

      expect(theme.show_command_vitals).to be(false)
      expect(theme.command_vitals_show_numbers).to be(false)
      expect(theme.show_roundtime_bar).to be(true)
    end

    it 'raises Config::Error for a non-boolean command_bar.command_vitals.enabled value' do
      path = write_config(<<~YAML)
        theme:
          command_bar:
            command_vitals:
              enabled: 'yes'
      YAML

      expect { described_class.load(path) }.to raise_error(
        described_class::Error, /command_bar\.command_vitals\.enabled.*true or false/
      )
    end

    it 'raises Config::Error for a non-boolean command_bar.command_vitals.show_numbers value' do
      path = write_config(<<~YAML)
        theme:
          command_bar:
            command_vitals:
              show_numbers: 1
      YAML

      expect { described_class.load(path) }.to raise_error(
        described_class::Error, /command_bar\.command_vitals\.show_numbers.*true or false/
      )
    end

    it 'ignores a legacy command_vitals.number_justify key rather than erroring, since it is no longer a setting' do
      path = write_config(<<~YAML)
        theme:
          command_vitals:
            number_justify: 'left'
      YAML

      expect { described_class.load(path) }.not_to raise_error
    end

    # show_indicators defaults true (2026-09-15), so this overrides it
    # *off* to actually demonstrate the override, independently of every
    # other widget toggle's own default.
    it 'overrides the indicator-block visibility independently of every other widget toggle' do
      path = write_config(<<~YAML)
        theme:
          command_bar:
            status_indicators:
              enabled: false
      YAML

      theme = described_class.load(path)

      expect(theme.show_indicators).to be(false)
      expect(theme.show_command_vitals).to be(true)
    end

    it 'raises Config::Error for a non-boolean command_bar.status_indicators.enabled value' do
      path = write_config(<<~YAML)
        theme:
          command_bar:
            status_indicators:
              enabled: 'yes'
      YAML

      expect { described_class.load(path) }.to raise_error(
        described_class::Error, /command_bar\.status_indicators\.enabled.*true or false/
      )
    end

    it 'overrides status_indicators_location to :left independently of every other setting' do
      path = write_config(<<~YAML)
        theme:
          command_bar:
            status_indicators:
              location: 'left'
      YAML

      theme = described_class.load(path)

      expect(theme.status_indicators_location).to eq(:left)
      expect(theme.show_indicators).to be(true)
    end

    it 'accepts right explicitly, not just the default' do
      path = write_config(<<~YAML)
        theme:
          command_bar:
            status_indicators:
              location: 'right'
      YAML

      expect(described_class.load(path).status_indicators_location).to eq(:right)
    end

    it 'raises Config::Error for an unrecognized command_bar.status_indicators.location value' do
      path = write_config(<<~YAML)
        theme:
          command_bar:
            status_indicators:
              location: 'top'
      YAML

      expect { described_class.load(path) }.to raise_error(
        described_class::Error, /command_bar\.status_indicators\.location.*left\/right/
      )
    end

    it 'ignores a legacy vitals.background key rather than erroring, since it is no longer a setting' do
      path = write_config(<<~YAML)
        theme:
          vitals:
            background: '#ff00ff'
      YAML

      expect { described_class.load(path) }.not_to raise_error
    end

    # health/mana/stamina/spirit moved from vitals.* to
    # command_bar.command_vitals.* on 2026-09-15 -- an old config.yml still
    # setting them under vitals is not an error, it just silently falls
    # back to command_vitals_colors' own default for each, the same
    # graceful-degradation vitals.background gets above.
    it 'ignores the pre-2026-09-15 vitals.health/mana/stamina/spirit keys rather than erroring' do
      path = write_config(<<~YAML)
        theme:
          vitals:
            health: '#ff0000'
      YAML

      theme = described_class.load(path)

      expect(theme.command_vitals_colors[:health]).to eq(Grimoire::Theme::DEFAULT.command_vitals_colors[:health])
    end

    # roundtime/status_indicators moved under command_bar and every plain
    # `show` key renamed to `enabled` on 2026-09-15 -- an old config.yml
    # using the pre-move structure is not an error, it just silently falls
    # back to the new defaults for every key that moved, the same
    # graceful-degradation already established for a removed setting like
    # vitals.background above.
    it 'ignores the pre-2026-09-15 top-level roundtime:/indicators: sections and show: keys rather than erroring' do
      path = write_config(<<~YAML)
        theme:
          vitals:
            show: false
          roundtime:
            hard: '#00ff00'
            show: false
          debug:
            show: true
          command_vitals:
            show: true
          indicators:
            show: false
      YAML

      theme = nil
      expect { theme = described_class.load(path) }.not_to raise_error
      expect(theme).to eq(Grimoire::Theme::DEFAULT)
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

    it 'adds an unset lich.dir to a file that predates it, without dropping theme values' do
      path = write_config(Grimoire::ConfigTemplate.render(Grimoire::Theme::DEFAULT).sub(/^lich:\n(  .*\n)+/, ''))
      File.write(path, File.read(path).sub("bg: '#000000'", "bg: '#111111'"))
      expect(YAML.safe_load_file(path)).not_to have_key('lich')

      described_class.load(path)

      rewritten = YAML.safe_load_file(path)
      expect(rewritten['lich']).to eq('dir' => nil)
      expect(rewritten.dig('theme', 'game_window', 'bg')).to eq('#111111')
    end

    it 'keeps a configured lich.dir, as written, when rewriting for another missing key' do
      path = write_config(<<~YAML)
        theme:
          game_window:
            bg: '#111111'
        lich:
          dir: '~/lich-5'
      YAML

      described_class.load(path)

      expect(YAML.safe_load_file(path)['lich']).to eq('dir' => '~/lich-5')
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
          command_bar:
            command_vitals:
              health: 'not-a-color'
      YAML

      expect { described_class.load(path) }.to raise_error(
        described_class::Error, /#{Regexp.escape(path)}.*command_bar\.command_vitals\.health.*invalid color/
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

  describe '.resolve' do
    it 'returns the Config for an explicit path' do
      path = write_config("lich:\n  dir: '/opt/lich-5'\n")

      expect(described_class.resolve(path).lich_dir).to eq('/opt/lich-5')
    end

    it 'falls back to the default path lookup, creating config.yml like .load does' do
      config_path = File.join(Dir.mktmpdir, 'configs', 'config.yml')
      stub_const('Grimoire::Config::DEFAULT_PATHS', [config_path].freeze)

      config = described_class.resolve

      expect(File).to exist(config_path)
      expect(config.lich_dir).to be_nil
      expect(config.theme).to eq(Grimoire::Theme::DEFAULT)
    end
  end

  describe '#lich_dir' do
    def lich_dir_for(contents)
      described_class.new(write_config(contents)).lich_dir
    end

    it 'is nil when the lich section is absent' do
      expect(lich_dir_for("theme: {}\n")).to be_nil
    end

    it 'is nil when dir is left empty' do
      expect(lich_dir_for("lich:\n  dir:\n")).to be_nil
    end

    it 'returns the path exactly as written, without expanding ~' do
      expect(lich_dir_for("lich:\n  dir: '~/lich-5'\n")).to eq('~/lich-5')
    end

    it 'raises Config::Error when lich is not a mapping' do
      expect { lich_dir_for("lich: '/opt/lich-5'\n") }.to raise_error(described_class::Error, /lich: must be a mapping/)
    end

    it 'raises Config::Error when dir is not a string' do
      expect { lich_dir_for("lich:\n  dir: 5\n") }.to raise_error(described_class::Error, /lich\.dir: must be a non-empty string/)
    end

    it 'raises Config::Error when dir is blank' do
      expect { lich_dir_for("lich:\n  dir: '  '\n") }.to raise_error(described_class::Error, /lich\.dir: must be a non-empty string/)
    end
  end
end
