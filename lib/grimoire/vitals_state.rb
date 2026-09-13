module Grimoire
  # Plain holder for the vitals/status fields VitalsTracker populates from
  # self-closing <progressBar>/<indicator> tags (see docs/decisions.md).
  # Health/mana/stamina/spirit/mind/encumbrance each carry a percent value
  # plus a text label on the wire; pbarStance carries no text attribute at
  # all, so #stance is a bare percent. Indicators are a flat id => visible
  # hash, populated only as ids are actually seen -- no fixed icon list
  # assumed.
  class VitalsState
    Vital = Data.define(:percent, :text)

    attr_accessor :health, :mana, :stamina, :spirit, :mind, :encumbrance, :stance
    attr_reader :indicators

    def initialize
      @indicators = {}
    end

    def set_indicator(id, visible)
      @indicators[id] = visible
    end
  end
end
