require 'fileutils'
require 'time'

module Grimoire
  # Writes two append-only log files per connection -- the raw wire feed
  # exactly as it arrived, and the narrative text NarrativeStream produced
  # from it -- so a live session against a real Lich instance can be
  # captured and reviewed afterward, the same shape as the raw/filtered
  # session-log pairs sibling project rift-nexus captured for its own
  # development (see spec/fixtures/*.xml's citations). A fresh pair, named
  # with a session label and a timestamp, is opened per instance, so
  # repeatedly connecting/reconnecting grimoire during evaluation -- as the
  # same or a different character -- never clobbers an earlier run's logs.
  #
  # The label is the character name when one is known, falling back to the
  # port otherwise (a raw --host/--port launch has no name to use). Naming
  # by character is what makes several sessions sharing one process
  # readable: ports are assigned by whichever Lich happened to bind first
  # and say nothing about who the log belongs to.
  class SessionLogger
    # Character names reach here from the executable's --character flag,
    # which is arbitrary user input on its way into a file path, so
    # anything outside this set (path separators and traversal sequences
    # above all) is dropped rather than trusted. A name that survives as
    # empty falls back to the port.
    UNSAFE_LABEL_CHARACTERS = /[^A-Za-z0-9_-]/

    def initialize(dir:, port:, character: nil, clock: Time)
      FileUtils.mkdir_p(dir)
      stamp = clock.now.strftime('%Y%m%d-%H%M%S')
      label = session_label(character, port)
      @raw    = File.open(File.join(dir, "session-#{label}-#{stamp}-raw.log"), 'a')
      @parsed = File.open(File.join(dir, "session-#{label}-#{stamp}-parsed.log"), 'a')
      [@raw, @parsed].each { |file| file.sync = true }
    end

    # The chunk exactly as Connection handed it off, before tokenizing or
    # filtering -- one entry per incoming read.
    def raw(chunk)
      @raw.write(chunk)
    end

    # The narrative text NarrativeStream#feed produced from that same
    # chunk, so the two files can be diffed side by side to see exactly
    # what got squelched or routed to structured state.
    def parsed(text)
      @parsed.write(text)
    end

    def close
      @raw.close
      @parsed.close
    end

    private

    # Case is normalized the same way SessionLocator already normalizes a
    # character name into lich-5's own session-file name
    # (downcase.capitalize), so `--character sparrow` and
    # `--character Sparrow` produce one consistent set of log names rather
    # than two that only differ in case.
    def session_label(character, port)
      safe = character.to_s.gsub(UNSAFE_LABEL_CHARACTERS, '')
      return port.to_s if safe.empty?

      safe.downcase.capitalize
    end
  end
end
