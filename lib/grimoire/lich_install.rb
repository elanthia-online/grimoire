require 'yaml'

module Grimoire
  # A lich-5 install on disk (config.yml's lich.dir -- see Config#lich_dir),
  # which grimoire launches headless sessions from: #problem checks that
  # the directory is actually usable, and #entries/#favorites read the
  # characters Lich itself has saved logins for, from its own
  # data/entry.yaml (lich-5 lib/common/authentication/entry_store.rb).
  #
  # Strictly read-only, and never reads the password: grimoire does not
  # write to entry.yaml (marking a favorite stays a Lich GUI action), and
  # the only per-account field it takes is the account name itself, used
  # as a grouping key by AccountGuard -- Lich owns every part of login, per
  # CLAUDE.md's "Connection model". YAML.safe_load_file still parses the
  # whole file (password included) into a transient Hash; nothing from it
  # beyond the fields in Entry is kept once #entries returns.
  #
  # Assumes the common layout where data/ sits beside lich.rbw. A Lich run
  # with --home pointing its data directory elsewhere is a known gap (see
  # TASKS.md's "Headless launch" item 1).
  class LichInstall
    # entry.yaml exists but cannot be read or parsed into the expected
    # shape. #problem does not raise this; only #entries/#favorites do.
    Error = Class.new(StandardError)

    # One saved character. user_id is the account name (lich-5 stores it
    # upcased), char_name the character (stored title-cased), game_code the
    # game instance (GS3, GSF, DR, ...), which --login needs alongside the
    # name since one name can be saved in more than one instance.
    Entry = Struct.new(:user_id, :char_name, :game_code, :game_name, :favorite, :favorite_order, keyword_init: true) do
      def favorite?
        favorite
      end
    end

    # Where an Entry with no favorite_order sorts -- after every ordered
    # favorite, matching lich-5's own saved-login tab (which uses 999999
    # for the same purpose).
    UNORDERED = Float::INFINITY

    attr_reader :dir

    def initialize(dir)
      @dir = File.expand_path(dir)
    end

    def lich_rbw_path
      File.join(@dir, 'lich.rbw')
    end

    def entry_yaml_path
      File.join(@dir, 'data', 'entry.yaml')
    end

    # nil when the install looks usable, otherwise a message naming the
    # first thing missing -- a String rather than a raise, since the
    # caller (the Connect dialog) shows it as a reason launching is
    # unavailable, not as a failure.
    def problem
      return "#{@dir}: no such directory" unless File.directory?(@dir)
      return "#{lich_rbw_path}: not found (is #{@dir} a lich-5 install?)" unless File.file?(lich_rbw_path)
      unless File.file?(entry_yaml_path)
        return "#{entry_yaml_path}: not found (save a login in Lich's own login window first)"
      end

      nil
    end

    # Every saved character, in file order. A character record missing its
    # name or game is skipped rather than failing the whole list: it could
    # not be launched with --login anyway.
    def entries
      data = YAML.safe_load_file(entry_yaml_path, permitted_classes: [Symbol]) || {}
      raise Error, "#{entry_yaml_path}: top level must be a mapping" unless data.is_a?(Hash)

      accounts = data['accounts'] || {}
      raise Error, "#{entry_yaml_path}: accounts must be a mapping" unless accounts.is_a?(Hash)

      accounts.flat_map { |user_id, account| account_entries(user_id, account) }
    rescue Psych::Exception => e
      raise Error, "#{entry_yaml_path}: invalid YAML (#{e.message})"
    rescue SystemCallError => e
      raise Error, "#{entry_yaml_path}: cannot read (#{e.message})"
    end

    # Favorites only, in lich-5's own display order (favorite_order, unset
    # last, then name). lich-5 can save one character more than once,
    # differing only by frontend or custom launch command; a headless
    # launch uses neither, so those collapse to one entry per account,
    # character and game.
    def favorites
      entries.select(&:favorite?)
             .sort_by { |entry| [entry.favorite_order || UNORDERED, entry.char_name.downcase] }
             .uniq { |entry| [entry.user_id.upcase, entry.char_name.downcase, entry.game_code.upcase] }
    end

    private

    def account_entries(user_id, account)
      return [] unless user_id.is_a?(String) && account.is_a?(Hash) && account['characters'].is_a?(Array)

      account['characters'].filter_map do |character|
        next unless character.is_a?(Hash) && nonblank_string?(character['char_name'])
        next unless nonblank_string?(character['game_code'])

        Entry.new(
          user_id: user_id,
          char_name: character['char_name'],
          game_code: character['game_code'],
          game_name: character['game_name'],
          favorite: character['is_favorite'] == true,
          favorite_order: character['favorite_order'].is_a?(Integer) ? character['favorite_order'] : nil
        )
      end
    end

    def nonblank_string?(value)
      value.is_a?(String) && !value.strip.empty?
    end
  end
end
