require 'spec_helper'
require 'yaml'
require 'tmpdir'

RSpec.describe Grimoire::ConfigTemplate do
  describe '.render' do
    it 'renders valid YAML that Config can load back into an equal theme' do
      rendered = described_class.render(Grimoire::Theme::DEFAULT)
      path = File.join(Dir.mktmpdir, 'config.yml')
      File.write(path, rendered)

      expect(Grimoire::Config.new(path).theme).to eq(Grimoire::Theme::DEFAULT)
    end

    it 'renders every color field as a "#rrggbb" hex string' do
      rendered = described_class.render(Grimoire::Theme::DEFAULT)

      expect(rendered).to include("bg: '#{Grimoire::Theme::DEFAULT.game_window_bg.to_hex}'")
      expect(rendered).to include("fg: '#{Grimoire::Theme::DEFAULT.game_window_fg.to_hex}'")
      expect(rendered).to include("padding_bg: '#{Grimoire::Theme::DEFAULT.padding_bg.to_hex}'")
      expect(rendered).to include("bg: '#{Grimoire::Theme::DEFAULT.title_bar_bg.to_hex}'")
      expect(rendered).to include("health: '#{Grimoire::Theme::DEFAULT.vitals_colors[:health].to_hex}'")
    end

    it 'identifies the fg/bg abbreviations for readers' do
      rendered = described_class.render(Grimoire::Theme::DEFAULT)

      expect(rendered).to match(/fg.*=.*foreground/i)
      expect(rendered).to match(/bg.*=.*background/i)
    end

    it 'renders a custom theme value back out, not just the built-in default' do
      theme = Grimoire::Theme::DEFAULT.with(
        game_window_bg: Grimoire::Color.new(red: 17, green: 34, blue: 51),
        padding: 9,
        border_width: 3
      )

      rendered = described_class.render(theme)

      expect(rendered).to include("bg: '#112233'")
      expect(rendered).to include('padding: 9')
      expect(rendered).to include('width: 3')
    end

    it 'renders the command bar as its own section, independent of the game window' do
      theme = Grimoire::Theme::DEFAULT.with(
        command_bar_bg: Grimoire::Color.new(red: 1, green: 2, blue: 3),
        command_bar_fg: Grimoire::Color.new(red: 4, green: 5, blue: 6),
        command_bar_font_family: 'Fira Code',
        command_bar_font_size: 13
      )

      rendered = described_class.render(theme)

      expect(rendered).to include('command_bar:')
      expect(rendered).to include("bg: '#010203'")
      expect(rendered).to include("fg: '#040506'")
      expect(rendered).to include("family: 'Fira Code'")
      expect(rendered).to include('size: 13')
      expect(rendered).to include("family: '#{Grimoire::Theme::DEFAULT.font_family}'")
    end

    it 'renders the vitals label text color, independent of the fill colors' do
      theme = Grimoire::Theme::DEFAULT.with(vitals_fg: Grimoire::Color.new(red: 7, green: 8, blue: 9))

      rendered = described_class.render(theme)

      expect(rendered).to include("fg: '#070809'")
    end

    it 'renders the status-indicator label color, independent of the vitals label text color' do
      theme = Grimoire::Theme::DEFAULT.with(indicator_fg: Grimoire::Color.new(red: 10, green: 11, blue: 12))

      rendered = described_class.render(theme)

      expect(rendered).to include("indicator_fg: '#0a0b0c'")
    end

    it 'renders the roundtime label text color, independent of the fill colors' do
      theme = Grimoire::Theme::DEFAULT.with(roundtime_fg: Grimoire::Color.new(red: 13, green: 14, blue: 15))

      rendered = described_class.render(theme)

      expect(rendered).to include("fg: '#0d0e0f'")
    end

    # Every plain `show` key renamed to `enabled` on 2026-09-15 --
    # `indicator_show`/`show_numbers` are unchanged (compound names,
    # neither literally `show`).
    it 'renders each widget-visibility toggle as a plain YAML boolean, using `enabled` not `show`' do
      theme = Grimoire::Theme::DEFAULT.with(
        show_vitals_bar: false, show_roundtime_bar: false, show_status_bar: false, show_debug_menu: true
      )

      rendered = described_class.render(theme)
      path = File.join(Dir.mktmpdir, 'config.yml')
      File.write(path, rendered)

      expect(rendered).to include('enabled: false')
      expect(rendered).to include('indicator_show: false')
      expect(rendered).to include("debug:\n    enabled: true")
      # Not a bare `show:` key anywhere -- indicator_show:/show_numbers:
      # legitimately contain "show" as a substring, so this checks for the
      # standalone key specifically, not a raw string search.
      expect(rendered).not_to match(/^\s*show:/)
      expect(Grimoire::Config.new(path).theme).to eq(theme)
    end

    # command_vitals moved under command_bar on 2026-09-15, alongside
    # roundtime/status_indicators making the same move earlier that day.
    it 'renders command_vitals nested under command_bar, round-tripping enabled/show_numbers' do
      theme = Grimoire::Theme::DEFAULT.with(show_command_vitals: false, command_vitals_show_numbers: false)

      rendered = described_class.render(theme)
      path = File.join(Dir.mktmpdir, 'config.yml')
      File.write(path, rendered)

      expect(rendered).to include("command_vitals:\n      enabled: false\n      show_numbers: false")
      expect(rendered).not_to match(/^  command_vitals:/)
      expect(Grimoire::Config.new(path).theme).to eq(theme)
    end

    # roundtime/status_indicators moved under command_bar on 2026-09-15 --
    # no more top-level roundtime:/indicators: sections.
    it 'renders roundtime/status_indicators nested under command_bar, not as top-level sections' do
      theme = Grimoire::Theme::DEFAULT.with(
        roundtime_hard: Grimoire::Color.new(red: 20, green: 30, blue: 40),
        roundtime_min_rt: 7,
        show_roundtime_bar: false,
        show_indicators: false
      )

      rendered = described_class.render(theme)
      path = File.join(Dir.mktmpdir, 'config.yml')
      File.write(path, rendered)

      expect(rendered).to include("command_bar:")
      expect(rendered).to include("hard: '#141e28'")
      expect(rendered).to include('min_rt: 7')
      expect(rendered).to include("roundtime:\n      hard:")
      expect(rendered).to include("status_indicators:\n      enabled: false")
      expect(rendered).not_to match(/^  roundtime:/)
      expect(rendered).not_to match(/^  indicators:/)
      expect(Grimoire::Config.new(path).theme).to eq(theme)
    end

    it 'renders status_indicators.location, round-tripping :left' do
      theme = Grimoire::Theme::DEFAULT.with(status_indicators_location: :left)

      rendered = described_class.render(theme)
      path = File.join(Dir.mktmpdir, 'config.yml')
      File.write(path, rendered)

      expect(rendered).to include("location: 'left'")
      expect(Grimoire::Config.new(path).theme).to eq(theme)
    end
  end
end
