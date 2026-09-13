require_relative 'color'

module Grimoire
  # Default fill colors for the vitals strip (Window#build_vitals_strip),
  # plus the shared empty/background color for every bar's trough. No
  # selection or customization mechanism exists yet -- these are fixed
  # defaults, a deliberate step short of a user-selectable palette.
  #
  # _references/uberbar_eo.lic was checked for a canonical color mapping
  # first (see docs/decisions.md's entry on that script) and has none: it
  # renders through Wrayth's own named skin/image assets, never raw RGB,
  # so there was nothing to carry over. These defaults instead follow the
  # color convention common to Simutronics-client bar mods generally: red
  # for health, blue for mana, gold for stamina, white/light-gray for
  # spirit, purple for mind, and neutral gray for the two non-resource
  # bars (encumbrance, stance).
  module VitalsColors
    BACKGROUND = Color.new(red: 0, green: 0, blue: 0)

    FIELDS = {
      :health      => Color.new(red: 200, green: 0,   blue: 0),
      :mana        => Color.new(red: 0,   green: 0,   blue: 200),
      :stamina     => Color.new(red: 200, green: 160, blue: 0),
      :spirit      => Color.new(red: 200, green: 200, blue: 200),
      :mind        => Color.new(red: 128, green: 0,   blue: 200),
      :encumbrance => Color.new(red: 150, green: 150, blue: 150),
      :stance      => Color.new(red: 150, green: 150, blue: 150),
    }.freeze
  end
end
