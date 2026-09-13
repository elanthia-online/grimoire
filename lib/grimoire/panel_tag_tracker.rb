require_relative 'tokenizer'

module Grimoire
  # TEMPORARY, evidence-based suppression (2026-09-13): squelches a set of
  # GUI-panel/status tags confirmed, against a real live-captured session
  # (see docs/decisions.md), to otherwise leak straight into the
  # scrollback -- either as garbled concatenated fragments (spell/left/
  # right have no separator between them on the wire: a real capture
  # produced "Nonegreen crackersEmpty") or as a bare orphaned blank line
  # (a line made entirely of self-closing status tags, e.g. a lone
  # <roommeta/>, has no real Text token of its own for the trailing CRLF
  # to belong to). None of these carry narrative content -- they are
  # vitals bars, indicators, and Wrayth-style dialog panels (dialogData,
  # openDialog and their self-closing children) that this client does not
  # render as separate widgets. This is the same "drop tag and content"
  # shape sibling project rift-nexus converged on for the same category
  # of tag in its own display_filter.py (dialogData, openDialog, spell,
  # left, right), which this class does not port code from but does agree
  # with on approach.
  #
  # This is explicitly not the long-term home for this data -- see
  # TASKS.md's "Route non-narrative panel tags to structured state" item,
  # still open. Nothing here is consumed into structured state; it is
  # dropped outright, the same way StreamTracker's pushStream/popStream
  # content already is. Revisit if any of these tags turn out to carry
  # information the UI needs (e.g. `spell`/`left`/`right` for a future
  # hands/prepared-spell indicator strip).
  class PanelTagTracker
    DROP_TAGS = %w[
      dialogData openDialog roommeta spell left right indicator
      progressBar resource style skin image pulse label compass castTime
    ].freeze

    Routed = Data.define(:token, :captured) do
      def narrative?
        !captured
      end
    end

    def initialize
      @current = nil
    end

    def route(token)
      return close_current(token) if @current

      return Routed.new(token: token, captured: false) unless drop_open?(token)

      @current = token.name unless token.self_closing
      Routed.new(token: token, captured: true)
    end

    private

    def drop_open?(token)
      tag?(token) && !token.closing && DROP_TAGS.include?(token.name)
    end

    def tag?(token)
      token.is_a?(Tokenizer::Tokens::Tag)
    end

    def close_current(token)
      @current = nil if tag?(token) && token.closing && token.name == @current
      Routed.new(token: token, captured: true)
    end
  end
end
