module Grimoire
  # Same-account collision check for a headless launch. An account allows
  # one logged-in character per game (the user's own statement,
  # 2026-09-16): GS3, GST and GSF share one login, as do DR, DRX, DRT and
  # DRF, while GemStone and DragonRealms are separate accounts. Logging in
  # a second character in the same game on that account forces the first
  # one off server-side. GameMaster and GameHost accounts, which are
  # exempt, are not accounted for. Before launching, this finds any *other*
  # character on the same account and game that already has a session
  # running, so the caller can warn by name and let the user launch anyway
  # (switching characters may be exactly what was intended).
  #
  # Only sees what SessionLocator.list sees: a character logged in without
  # a session file (another frontend, or Lich without --detachable-client)
  # goes unnoticed, and a stale session file left by a crashed Lich still
  # counts as running. See TASKS.md's "Headless launch" item 3.
  #
  # The same character name on another instance of the same game (Sparrow
  # on GST while Sparrow runs on GS3) also shares the login, but cannot be
  # told apart here: session files are named per character, not per
  # instance, until lich-5#1647 (UPSTREAM.md). The Connect dialog shows
  # such a row as running and attaches rather than launching, so that case
  # does not reach this check today.
  module AccountGuard
    # The LichInstall::Entry records for characters on target's account and
    # in target's game, other than target's own character, that have a
    # valid session file in sessions (SessionLocator::Session records).
    # entries should be every saved character (LichInstall#entries), not
    # just favorites -- a running character blocks the login whether or not
    # it is a favorite. Session files are named per character only, not per
    # instance, so one running character matches all of its saved entries
    # in that game; those collapse to one result per character name.
    def self.running_siblings(target, entries:, sessions:)
      running = sessions.select(&:valid?).map { |session| session.character.downcase }
      game    = game_of(target.game_code)

      entries.select do |entry|
        entry.user_id.casecmp?(target.user_id) &&
          game_of(entry.game_code) == game &&
          !entry.char_name.casecmp?(target.char_name) &&
          running.include?(entry.char_name.downcase)
      end.uniq { |entry| entry.char_name.downcase }
    end

    # The game a game code belongs to, which is what shares a login: its
    # first two letters, GS or DR.
    def self.game_of(game_code)
      game_code.to_s.upcase[0, 2]
    end
  end
end
