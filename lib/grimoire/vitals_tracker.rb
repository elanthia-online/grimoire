require_relative 'tokenizer'
require_relative 'vitals_state'

module Grimoire
  # Watches self-closing <progressBar>/<indicator> tags -- real traffic
  # never pairs either with a matching close tag, so unlike RoomTracker or
  # PanelTagTracker there is no open/close bracket to track -- and routes
  # recognized vitals/status ids into structured VitalsState. Everything
  # else in these two tag families (buff/spell-timer progressBar ids like
  # the Active Spells window's, the experience bar's nextLvlPB, unrecognized
  # indicator ids) is still reported as non-narrative so it does not leak
  # into the scrollback pane, but is not routed into any exposed state --
  # the same "capture but do not expose" middle ground PanelTagTracker still
  # uses for the GUI-panel tags that remain there. This is the migration
  # TASKS.md's "Route non-narrative panel tags" item flagged as the next
  # step once a UI wanted progressBar/indicator data, the same path
  # component id='room objs'|'room players' already took into RoomState --
  # see docs/decisions.md.
  class VitalsTracker
    Routed = Data.define(:token, :captured) do
      def narrative?
        !captured
      end
    end

    ROUTED_TAGS = %w[progressBar indicator].freeze

    VITAL_FIELDS = {
      'health'     => :health,
      'mana'       => :mana,
      'stamina'    => :stamina,
      'spirit'     => :spirit,
      'mindState'  => :mind,
      'encumlevel' => :encumbrance,
    }.freeze

    # health/mana/stamina/spirit carry a "<label> current/max" text (e.g.
    # "health 351/355"); mindState/encumlevel's text ("must rest", "None")
    # has no such fraction, so only these four are eligible for the
    # text-derived percent below. Confirmed against lich-5's own source
    # (`detachable_client_send_init`, lib/global_defs.rb): the one-time
    # initial push to a newly-attached frontend hardcodes value='0' for
    # exactly these four fields regardless of the character's real vitals,
    # even though text carries the correct numbers -- reproduced in our own
    # spec/fixtures/vitals.xml's init line. ProfanityFE (lib/tag_handlers.rb,
    # handle_progress_bar_tag) already works around this the same way, for
    # the same reason -- text, not value, is treated as authoritative for
    # this tag family. See docs/decisions.md.
    FRACTION_TEXT_IDS = %w[health mana stamina spirit].freeze
    FRACTION_TEXT_PATTERN = %r{(\d+)/(\d+)}

    attr_reader :vitals_state

    def initialize(vitals_state: VitalsState.new)
      @vitals_state = vitals_state
    end

    def route(token)
      handle(token) if relevant?(token) && token.self_closing
      Routed.new(token: token, captured: relevant?(token))
    end

    private

    def relevant?(token)
      token.is_a?(Tokenizer::Tokens::Tag) && ROUTED_TAGS.include?(token.name)
    end

    def handle(token)
      case token.name
      when 'progressBar' then handle_progress_bar(token)
      when 'indicator' then handle_indicator(token)
      end
    end

    def handle_progress_bar(token)
      id = token.attrs['id']

      if id == 'pbarStance'
        @vitals_state.stance = token.attrs['value'].to_i
      elsif (field = VITAL_FIELDS[id])
        @vitals_state.public_send("#{field}=", VitalsState::Vital.new(
                                                 percent: percent_for(id, token.attrs),
                                                 text: token.attrs['text']
                                               ))
      end
    end

    # Floor division matches how Lich itself computes value on a real
    # (non-init) update -- e.g. the vitals.xml fixture's value='98'
    # text='health 351/355' is exactly (351 * 100) / 355 -- so this is a
    # no-op for ordinary traffic and only changes the result for the
    # documented init-push bug above (and anything else that might send an
    # inconsistent value/text pair for these four ids).
    def percent_for(id, attrs)
      return attrs['value'].to_i unless FRACTION_TEXT_IDS.include?(id)

      match = attrs['text']&.match(FRACTION_TEXT_PATTERN)
      return attrs['value'].to_i unless match

      max = match[2].to_i
      return attrs['value'].to_i if max.zero?

      (match[1].to_i * 100) / max
    end

    def handle_indicator(token)
      id = token.attrs['id']
      return unless id

      @vitals_state.set_indicator(id, token.attrs['visible'] == 'y')
    end
  end
end
