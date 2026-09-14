require 'yaml'
require_relative 'theme'

module Grimoire
  # Loads configs/config.yml into a Theme, overriding Theme::DEFAULT
  # field-by-field so a config file only needs to mention the settings it
  # wants to change -- see configs/examples/config-default.yml for the
  # full key layout and a commented-out copy of every default.
  # YAML.safe_load_file (no aliases, no custom classes) is enough here
  # since config.yml only ever holds plain scalars/mappings, never needs
  # Ruby object round-tripping.
  class Config
    class Error < StandardError; end

    # Checked in order; the first one that exists on disk wins. A bare
    # configs/config.yml under the working directory suits a git checkout
    # run in place (`bundle exec ./grimoire`); the XDG-style path suits a
    # cloned/archived copy run from elsewhere (same non-gem-install
    # distribution model CLAUDE.md already documents for the executable
    # itself). Neither is required -- .load falls back to Theme::DEFAULT
    # if nothing is found, so grimoire runs with no config file at all.
    DEFAULT_PATHS = [
      File.join(Dir.pwd, 'configs', 'config.yml'),
      File.join(Dir.home, '.config', 'grimoire', 'config.yml'),
    ].freeze

    def self.load(path = nil)
      path ||= DEFAULT_PATHS.find { |candidate| File.file?(candidate) }
      return Theme::DEFAULT unless path

      new(path).theme
    end

    def initialize(path)
      @path = path
      @data = YAML.safe_load_file(path, symbolize_names: true) || {}
      raise Error, "#{path}: top level must be a mapping" unless @data.is_a?(Hash)
    rescue Psych::SyntaxError => e
      raise Error, "#{path}: invalid YAML (#{e.message})"
    rescue Errno::ENOENT
      raise Error, "#{path}: no such file"
    end

    def theme
      theme_data = @data[:theme] || {}

      Theme.new(
        main_background: color(theme_data.dig(:main, :background), Theme::DEFAULT.main_background),
        main_foreground: color(theme_data.dig(:main, :foreground), Theme::DEFAULT.main_foreground),
        font_family: theme_data.dig(:font, :family) || Theme::DEFAULT.font_family,
        font_size: theme_data.dig(:font, :size) || Theme::DEFAULT.font_size,
        vitals_colors: vitals_colors(theme_data[:vitals]),
        vitals_background: color(theme_data.dig(:vitals, :background), Theme::DEFAULT.vitals_background),
        roundtime_hard: color(theme_data.dig(:roundtime, :hard), Theme::DEFAULT.roundtime_hard),
        roundtime_cast: color(theme_data.dig(:roundtime, :cast), Theme::DEFAULT.roundtime_cast)
      )
    rescue TypeError, NoMethodError => e
      raise Error, "#{@path}: malformed theme section (#{e.message})"
    end

    private

    def vitals_colors(vitals_data)
      Theme::DEFAULT.vitals_colors.keys.to_h do |field|
        [field, color(vitals_data&.dig(field), Theme::DEFAULT.vitals_colors[field])]
      end
    end

    def color(value, default)
      return default if value.nil?

      Color.from_hex(value)
    rescue ArgumentError => e
      raise Error, "#{@path}: #{e.message}"
    end
  end
end
