require 'fileutils'
require 'yaml'
require_relative 'theme'
require_relative 'config_template'

module Grimoire
  # Loads configs/config.yml into a Theme, overriding Theme::DEFAULT
  # field-by-field so a config file only needs to mention the settings it
  # wants to change -- see configs/defaults.yml (ConfigTemplate, generated
  # from Theme::DEFAULT -- see .ensure_defaults_file! below) for the full
  # key layout and every built-in default, or docs/configuration.md for the
  # human-facing reference (every key, type, default, description).
  # YAML.safe_load_file (no aliases, no custom classes) is enough here since
  # config.yml only ever holds plain scalars/mappings, never needs Ruby
  # object round-tripping.
  class Config
    class Error < StandardError; end

    # Checked in order; the first one that exists on disk wins. A bare
    # configs/config.yml under the working directory suits a git checkout
    # run in place (`bundle exec ./grimoire`); the XDG-style path suits a
    # cloned/archived copy run from elsewhere (same non-gem-install
    # distribution model CLAUDE.md already documents for the executable
    # itself). If neither exists yet, .load creates the first one itself
    # (see .default_path/.create_default_config_file!) rather than only
    # falling back to Theme::DEFAULT in memory -- the user's own spec
    # (2026-09-13): running grimoire with no settings file should leave one
    # behind to edit, not silently do nothing on disk.
    DEFAULT_PATHS = [
      File.join(Dir.pwd, 'configs', 'config.yml'),
      File.join(Dir.home, '.config', 'grimoire', 'config.yml'),
    ].freeze

    # The auto-generated, fully-commented reference copy of Theme::DEFAULT
    # -- see .ensure_defaults_file!. Paired with DEFAULT_PATHS.first (both
    # Dir.pwd-relative) rather than the XDG path: this is not per-user data,
    # so one canonical copy is enough regardless of which config.yml
    # location a given run actually resolves to.
    DEFAULTS_PATH = File.join(Dir.pwd, 'configs', 'defaults.yml')

    # dig-paths #theme reads out of a parsed config.yml, reused by
    # #missing_keys? to detect a settings key a newer grimoire version added
    # that an existing file predates (see #migrate!). Kept as its own
    # explicit list alongside #theme's own explicit field-by-field reads,
    # rather than one data-driven table driving both -- matches this
    # project's stated preference for plain, explicit code over a shared
    # abstraction (see CLAUDE.md); the two lists are short and change
    # together rarely enough that the duplication is cheaper than the
    # indirection would be.
    KEY_PATHS = [
      [:global, :padding], [:global, :padding_bg],
      [:title_bar, :bg], [:title_bar, :fg],
      [:game_window, :bg], [:game_window, :fg],
      [:game_window, :border, :color], [:game_window, :border, :width],
      [:font, :family], [:font, :size],
      [:command_bar, :bg], [:command_bar, :fg],
      [:command_bar, :font, :family], [:command_bar, :font, :size],
      *Theme::DEFAULT.vitals_colors.keys.map { |field| [:vitals, field] },
      [:vitals, :fg], [:vitals, :indicator_fg],
      [:vitals, :border, :color], [:vitals, :border, :width],
      [:roundtime, :hard], [:roundtime, :cast], [:roundtime, :fg],
    ].freeze

    private_constant :KEY_PATHS

    def self.load(path = nil)
      ensure_defaults_file!
      path ||= default_path

      new(path).theme
    end

    # Regenerates configs/defaults.yml from Theme::DEFAULT on every call,
    # unconditionally overwriting whatever was there -- it is not
    # user-editable data (nothing else ever writes to it), so there is
    # nothing to preserve by leaving a stale copy in place.
    #
    # This used to only write the file when it was missing ("deleting it is
    # what forces a refresh"), but that turned out to be a trap in
    # practice: reported live (2026-09-14) after Theme::DEFAULT's own
    # values changed (see TASKS.md's "Three Theme::DEFAULT values promoted"
    # entry) -- a defaults.yml already sitting on disk from before that
    # change kept satisfying "not missing" and was never revisited, so
    # every fresh config.yml it went on to seed (.create_default_config_file!)
    # silently carried the *old* defaults forward, with nothing on screen
    # to explain why deleting config.yml and rerunning did not actually
    # pick up the new ones -- deleting defaults.yml too was supposed to be
    # the fix, but is easy to get wrong (delete only one of the two, a typo
    # in the path, a second copy of the repo) with no error either way to
    # catch the mistake. Unconditional regeneration removes the whole
    # failure class: there is no "stale but not missing" state left for a
    # partial/mistaken deletion to land in.
    #
    # Runs before .default_path is resolved, independent of which
    # config.yml path a given call to .load will actually use --
    # .create_default_config_file! and #migrate! both need this file to
    # already exist and be current.
    def self.ensure_defaults_file!
      FileUtils.mkdir_p(File.dirname(DEFAULTS_PATH))
      File.write(DEFAULTS_PATH, ConfigTemplate.render(Theme::DEFAULT))
    end

    # The first DEFAULT_PATHS entry that already exists on disk, or --
    # if neither does -- DEFAULT_PATHS.first itself, freshly created by
    # copying .ensure_defaults_file!'s own output (already guaranteed to
    # exist by the time .load calls this). Only the implicit, no-`--config`
    # lookup auto-creates a file this way; an explicit --config PATH that
    # does not exist still raises Error from #initialize below rather than
    # silently creating one there, since the user named that exact file.
    def self.default_path
      DEFAULT_PATHS.find { |candidate| File.file?(candidate) } || create_default_config_file!
    end

    def self.create_default_config_file!
      path = DEFAULT_PATHS.first
      FileUtils.mkdir_p(File.dirname(path))
      FileUtils.cp(DEFAULTS_PATH, path)
      path
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

      built = Theme.new(
        game_window_bg: color(theme_data.dig(:game_window, :bg), Theme::DEFAULT.game_window_bg, 'game_window.bg'),
        game_window_fg: color(theme_data.dig(:game_window, :fg), Theme::DEFAULT.game_window_fg, 'game_window.fg'),
        font_family: font_family(theme_data.dig(:font, :family), Theme::DEFAULT.font_family, 'font.family'),
        font_size: integer(theme_data.dig(:font, :size), Theme::DEFAULT.font_size, 'font.size', min: 1),
        vitals_colors: vitals_colors(theme_data[:vitals]),
        roundtime_hard: color(theme_data.dig(:roundtime, :hard), Theme::DEFAULT.roundtime_hard, 'roundtime.hard'),
        roundtime_cast: color(theme_data.dig(:roundtime, :cast), Theme::DEFAULT.roundtime_cast, 'roundtime.cast'),
        roundtime_fg: color(theme_data.dig(:roundtime, :fg), Theme::DEFAULT.roundtime_fg, 'roundtime.fg'),
        title_bar_bg: color(theme_data.dig(:title_bar, :bg), Theme::DEFAULT.title_bar_bg, 'title_bar.bg'),
        title_bar_fg: color(theme_data.dig(:title_bar, :fg), Theme::DEFAULT.title_bar_fg, 'title_bar.fg'),
        padding: integer(theme_data.dig(:global, :padding), Theme::DEFAULT.padding, 'global.padding', min: 0),
        padding_bg: color(theme_data.dig(:global, :padding_bg), Theme::DEFAULT.padding_bg, 'global.padding_bg'),
        border_color: color(
          theme_data.dig(:game_window, :border, :color), Theme::DEFAULT.border_color, 'game_window.border.color'
        ),
        border_width: integer(
          theme_data.dig(:game_window, :border, :width), Theme::DEFAULT.border_width, 'game_window.border.width', min: 0
        ),
        vitals_border_color: color(
          theme_data.dig(:vitals, :border, :color), Theme::DEFAULT.vitals_border_color, 'vitals.border.color'
        ),
        vitals_border_width: integer(
          theme_data.dig(:vitals, :border, :width), Theme::DEFAULT.vitals_border_width, 'vitals.border.width', min: 0
        ),
        vitals_fg: color(theme_data.dig(:vitals, :fg), Theme::DEFAULT.vitals_fg, 'vitals.fg'),
        indicator_fg: color(
          theme_data.dig(:vitals, :indicator_fg), Theme::DEFAULT.indicator_fg, 'vitals.indicator_fg'
        ),
        command_bar_bg: color(theme_data.dig(:command_bar, :bg), Theme::DEFAULT.command_bar_bg, 'command_bar.bg'),
        command_bar_fg: color(theme_data.dig(:command_bar, :fg), Theme::DEFAULT.command_bar_fg, 'command_bar.fg'),
        command_bar_font_family: font_family(
          theme_data.dig(:command_bar, :font, :family), Theme::DEFAULT.command_bar_font_family, 'command_bar.font.family'
        ),
        command_bar_font_size: integer(
          theme_data.dig(:command_bar, :font, :size), Theme::DEFAULT.command_bar_font_size,
          'command_bar.font.size', min: 1
        )
      )

      migrate!(built) if missing_keys?(theme_data)
      built
    rescue TypeError, NoMethodError => e
      raise Error, "#{@path}: malformed theme section (#{e.message})"
    end

    private

    def missing_keys?(theme_data)
      KEY_PATHS.any? { |key_path| theme_data.dig(*key_path).nil? }
    end

    # Rewrites @path from scratch via ConfigTemplate, fed the Theme #theme
    # just built (Theme::DEFAULT already filling in whatever #missing_keys?
    # found missing, this file's own values preserved for everything else)
    # -- the "safe full rewrite" migration path per the user's own spec
    # (2026-09-13): always structurally correct and never silently drops a
    # value the user actually set, at the cost of not preserving any
    # comments/formatting they hand-added to this file themselves.
    def migrate!(theme)
      File.write(@path, ConfigTemplate.render(theme))
    end

    def vitals_colors(vitals_data)
      Theme::DEFAULT.vitals_colors.keys.to_h do |field|
        [field, color(vitals_data&.dig(field), Theme::DEFAULT.vitals_colors[field], "vitals.#{field}")]
      end
    end

    def color(value, default, key)
      return default if value.nil?

      Color.from_hex(value)
    rescue ArgumentError => e
      raise Error, "#{@path}: #{key}: #{e.message}"
    end

    # Guards the numeric settings (font size, padding, border widths) the
    # way #color already guards colors -- config.yml is free-form YAML, so
    # nothing stops a user (or a hand-edited defaults.yml, see the user's
    # own note 2026-09-13 that its contents are not otherwise checked
    # before being copied into a fresh config.yml) from writing a string, a
    # float, or a negative number into a field the rest of the code assumes
    # is a sane non-negative Integer -- left unchecked, that would only
    # surface later as broken/silently-ignored CSS (Window interpolates
    # these straight into generated stylesheet text), not a clear error at
    # load time. min: is 1 for font_size (a zero or negative point size is
    # meaningless) and 0 for padding/border widths (0 is the valid "off"
    # value; negative is not).
    def integer(value, default, key, min:)
      return default if value.nil?
      raise Error, "#{@path}: #{key}: must be an integer >= #{min} (got #{value.inspect})" unless value.is_a?(Integer)
      raise Error, "#{@path}: #{key}: must be an integer >= #{min} (got #{value})" if value < min

      value
    end

    def font_family(value, default, key)
      return default if value.nil?
      raise Error, "#{@path}: #{key}: must be a non-empty string (got #{value.inspect})" unless nonblank_string?(value)

      value
    end

    def nonblank_string?(value)
      value.is_a?(String) && !value.strip.empty?
    end
  end
end
