module Grimoire
  # The rows the Connect dialog offers, worked out without any GTK so the
  # rules are specced directly: every Lich favorite, in Lich's own order,
  # then every running session that is not a favorite (so attaching still
  # works with no lich.dir configured). Each row says what connecting to it
  # would do, via status:
  #
  # - :attached    -- already open in a tab; connecting focuses it.
  # - :launching   -- grimoire launched it and is waiting for its session.
  # - :running     -- a valid session file exists; connecting attaches.
  # - :not_running -- a favorite with no session; connecting launches it.
  #
  # Session files are named per character, not per game, so a character
  # saved as a favorite in two game instances shows the same running
  # session on both rows.
  module ConnectList
    # entry is the LichInstall::Entry (nil for a running session that is
    # not a favorite); session is the SessionLocator::Session (nil when not
    # running).
    Row = Struct.new(:character, :game, :status, :entry, :session, keyword_init: true)

    # favorites: LichInstall#favorites (empty when launching is
    # unavailable). sessions: SessionLocator.list. attached: called with
    # (host, port), true when a live tab holds that session. launching:
    # names of characters being launched, any case.
    def self.build(favorites:, sessions:, attached:, launching:)
      running  = sessions.select(&:valid?).to_h { |session| [session.character.downcase, session] }
      waiting  = launching.map(&:downcase)
      favored  = favorites.map { |entry| entry.char_name.downcase }

      favorite_rows = favorites.map do |entry|
        session = running[entry.char_name.downcase]
        Row.new(
          character: entry.char_name, game: entry.game_name || entry.game_code, entry: entry, session: session,
          status: status(entry.char_name, session, attached, waiting)
        )
      end

      other_rows = running.reject { |name, _session| favored.include?(name) }.values.sort_by(&:character).map do |session|
        Row.new(
          character: session.character, game: nil, entry: nil, session: session,
          status: status(session.character, session, attached, waiting)
        )
      end

      favorite_rows + other_rows
    end

    # A launch in progress wins over a session file, since the file may be
    # this launch's own, written a moment before it is attached.
    def self.status(character, session, attached, waiting)
      return :attached if session && attached.call(session.host, session.port)
      return :launching if waiting.include?(character.downcase)
      return :running if session

      :not_running
    end
  end
end
