require_relative 'tokenizer'
require_relative 'vitals_state'

module Grimoire
  # Watches self-closing <progressBar>/<indicator>/<roundTime>/<castTime>
  # tags -- real traffic never pairs any of them with a matching close tag,
  # so unlike RoomTracker or PanelTagTracker there is no open/close bracket
  # to track -- and routes recognized vitals/status ids into structured
  # VitalsState. Everything else in the progressBar/indicator tag families
  # (buff/spell-timer progressBar ids like the Active Spells window's, the
  # experience bar's nextLvlPB, unrecognized indicator ids) is still
  # reported as non-narrative so it does not leak into the scrollback pane,
  # but is not routed into any exposed state -- the same "capture but do
  # not expose" middle ground PanelTagTracker still uses for the GUI-panel
  # tags that remain there. This is the migration TASKS.md's "Route
  # non-narrative panel tags" item flagged as the next step once a UI
  # wanted progressBar/indicator data, the same path component id='room
  # objs'|'room players' already took into RoomState -- see
  # docs/decisions.md. roundTime/castTime each carry the absolute epoch
  # second their own lock ends -- confirmed via lich-5's own xmlparser.rb
  # (`@roundtime_end`/`@cast_roundtime_end = attributes['value']`, handled
  # independently of one another there too), since no captured session in
  # _references happens to contain a roundTime tag; castTime is seen live
  # in spec/fixtures/vitals.xml's sibling raw-log excerpts. Deliberately
  # two separate VitalsState fields, not one shared "roundtime" value: hard
  # roundtime (roundTime, from most actions) and cast roundtime (castTime,
  # from spell preparation) restrict different, overlapping sets of
  # commands and tick independently -- either can be running while the
  # other is not. See docs/decisions.md.
  class VitalsTracker
    Routed = Data.define(:token, :captured) do
      def narrative?
        !captured
      end
    end

    ROUTED_TAGS = %w[progressBar indicator roundTime castTime].freeze

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
    # text-derived percent below. Lich versions before the per-game init
    # push (lich-5 `detachable_client_send_init`, lib/global_defs.rb)
    # hardcode value='0' for exactly these four fields in the one-time push
    # to a newly-attached frontend, even though text carries the correct
    # numbers -- reproduced in our own spec/fixtures/vitals.xml's init line.
    # Newer Lich sends a real value computed the same way, so the text
    # derivation agrees with it and is kept for compatibility with older
    # Lich. ProfanityFE (lib/tag_handlers.rb, handle_progress_bar_tag)
    # already works around this the same way, for the same reason -- text,
    # not value, is treated as authoritative for this tag family.
    # DragonRealms text is a bare percent ("health 100%") with no fraction,
    # so it falls back to value, which matches it. See docs/decisions.md.
    FRACTION_TEXT_IDS = %w[health mana stamina spirit].freeze
    # Current may legitimately be negative on the wire (e.g. "health
    # -5/355"); without the optional minus the match would silently read
    # it as a positive 5. Max is never negative.
    FRACTION_TEXT_PATTERN = %r{(-?\d+)/(\d+)}

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
      when 'roundTime' then handle_round_time(token)
      when 'castTime' then handle_cast_time(token)
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

    # Floor division matches how the game itself computes value (whole-
    # integer math with truncation) -- e.g. the vitals.xml fixture's
    # value='98' text='health 351/355' is exactly (351 * 100) / 355 -- so
    # this is a no-op for ordinary traffic and for newer Lich's init push,
    # and only changes the result for older Lich's value='0' init push
    # documented above (and anything else that might send an
    # inconsistent value/text pair for these four ids). The game itself
    # clamps the percent to 0 for a negative current while still reporting
    # the raw negative number in text (value='0' text='health -5/355'), so
    # the result is clamped to 0..100 here too -- which also makes the
    # difference between Ruby's flooring `/` and the game's truncation
    # irrelevant, since the two only disagree for negative operands. Vital
    # text is left untouched, so the raw -5 is still what gets displayed.
    def percent_for(id, attrs)
      return attrs['value'].to_i unless FRACTION_TEXT_IDS.include?(id)

      match = attrs['text']&.match(FRACTION_TEXT_PATTERN)
      return attrs['value'].to_i unless match

      max = match[2].to_i
      return attrs['value'].to_i if max.zero?

      ((match[1].to_i * 100) / max).clamp(0, 100)
    end

    def handle_indicator(token)
      id = token.attrs['id']
      return unless id

      @vitals_state.set_indicator(id, token.attrs['visible'] == 'y')
    end

    def handle_round_time(token)
      @vitals_state.roundtime_end = token.attrs['value'].to_i
    end

    def handle_cast_time(token)
      @vitals_state.cast_roundtime_end = token.attrs['value'].to_i
    end
  end
end
