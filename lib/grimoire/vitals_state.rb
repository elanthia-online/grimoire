module Grimoire
  # Plain holder for the vitals/status fields VitalsTracker populates from
  # self-closing <progressBar>/<indicator>/<roundTime>/<castTime> tags (see
  # docs/decisions.md). Health/mana/stamina/spirit/mind/encumbrance each
  # carry a percent value plus a text label on the wire; pbarStance carries
  # no text attribute at all, so #stance is a bare percent. Indicators are a
  # flat id => visible hash, populated only as ids are actually seen -- no
  # fixed icon list assumed. roundtime_end/cast_roundtime_end are each the
  # absolute epoch second the corresponding lock ends (the wire's own
  # value, not a duration) -- nil until the matching tag has actually been
  # seen; a consumer derives remaining seconds by comparing against the
  # current wall clock. The two are distinct, independently-ticking locks,
  # not one value superseding the other: hard roundtime (<roundTime>, from
  # most actions) restricts most commands, cast roundtime (<castTime>, from
  # spell preparation) restricts spells and some commands, and either can
  # be running while the other is not -- see docs/decisions.md.
  class VitalsState
    Vital = Data.define(:percent, :text)

    attr_accessor :health, :mana, :stamina, :spirit, :mind, :encumbrance, :stance,
                  :roundtime_end, :cast_roundtime_end
    attr_reader :indicators

    def initialize
      @indicators = {}
    end

    def set_indicator(id, visible)
      @indicators[id] = visible
    end
  end
end
