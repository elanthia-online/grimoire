require 'spec_helper'
require 'yaml'

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
  end
end
