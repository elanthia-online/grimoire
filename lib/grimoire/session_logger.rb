require 'fileutils'
require 'time'

module Grimoire
  # Writes two append-only log files per connection -- the raw wire feed
  # exactly as it arrived, and the narrative text NarrativeStream produced
  # from it -- so a live session against a real Lich instance can be
  # captured and reviewed afterward, the same shape as the raw/filtered
  # session-log pairs sibling project rift-nexus captured for its own
  # development (see spec/fixtures/*.xml's citations). A fresh pair,
  # named with the port and a timestamp, is opened per instance, so
  # repeatedly connecting/reconnecting grimoire during evaluation -- to
  # the same or a different Lich port -- never clobbers an earlier run's
  # logs.
  class SessionLogger
    def initialize(dir:, port:, clock: Time)
      FileUtils.mkdir_p(dir)
      stamp = clock.now.strftime('%Y%m%d-%H%M%S')
      @raw    = File.open(File.join(dir, "session-#{port}-#{stamp}-raw.log"), 'a')
      @parsed = File.open(File.join(dir, "session-#{port}-#{stamp}-parsed.log"), 'a')
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
  end
end
