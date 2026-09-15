module Grimoire
  # Collapses the 13 confirmed wire indicator ids (VitalsState#indicators)
  # into a fixed 4-slot display -- posture, group, stealth, status -- the
  # user's own spec (2026-09-15): each slot is always present and holds at
  # most one icon filename (assets/indicators/*.png) or nil ("blank"),
  # rather than a variable-width list of every currently-true indicator.
  # The baseline/idle state is a single posture icon (standing, once any
  # posture has been seen at all) plus the other three slots blank -- the
  # user's own later spec (2026-09-15): posture is never blank once
  # populated, group/stealth/status are the three placeholders. Pure
  # logic, no GTK -- keeps the priority rules unit-testable without a live
  # window. This is the layer Window#build_indicator_block drives in the
  # real game window, superseding the older text-based active-indicators
  # label (e.g. "STUNNED BLEEDING") removed 2026-09-15; IndicatorWindow
  # (the all-13 review tool) is untouched by this.
  module IndicatorGroups
    Slots = Data.define(:posture, :group, :stealth, :status)

    # Posture: dead implies prone (a dead body is always prone, and
    # posture cannot change while dead -- the user's own spec, 2026-09-15)
    # so dead simply outranks prone here rather than needing separate
    # handling. Standing shows its own icon (revised from the original
    # "blank while standing" design, the user's own later spec,
    # 2026-09-15) -- posture is meant to be the one slot that always shows
    # something once populated, establishing the 4-icon block's baseline
    # state, unlike ProfanityFE's own precedent of leaving it unbound.
    # Priority beyond dead/prone (sitting over kneeling over standing) is
    # a defensive fallback only -- postures are mutually exclusive by game
    # rule, so more than one true at once should never actually happen;
    # if the wire ever glitches, something still has to win, with standing
    # (the least specific state) ranked last.
    POSTURE_ICONS = {
      'IconDEAD'     => 'dead.png',
      'IconPRONE'    => 'prone.png',
      'IconSITTING'  => 'sitting.png',
      'IconKNEELING' => 'kneeling.png',
      'IconSTANDING' => 'standing.png',
    }.freeze

    GROUP_ICONS = {
      'IconJOINED' => 'joined.png',
    }.freeze

    # Stealth: confirmed mutually exclusive by an actual captured game log
    # (2026-09-15) -- hiding is refused outright while invisible ("A tad
    # paranoid, aren't we?"), and casting invisibility while hidden forces
    # "You come out of hiding." first. invisible outranking hidden here is
    # a defensive fallback only, the same as posture's sitting/kneeling
    # order above -- this pairing should never actually have both true at
    # once.
    STEALTH_ICONS = {
      'IconINVISIBLE' => 'invisible.png',
      'IconHIDDEN'    => 'hidden.png',
    }.freeze

    # Status: unlike posture/stealth, these five are NOT mutually
    # exclusive -- multiple can genuinely be true at once (e.g. bleeding
    # while poisoned). This slot deliberately shows only the
    # highest-priority one, trading away simultaneous visibility for a
    # static 4-icon width -- the user's own explicit choice (2026-09-15).
    # Priority order (most action-restricting first, the user's own spec):
    # stunned (no actions at all) > webbed (limited actions) > poisoned >
    # diseased > bleeding. Diseased outranks bleeding (revised from the
    # original stunned/webbed/poisoned/bleeding/diseased order, the user's
    # own spec, 2026-09-15): bleeding already gets its own separate
    # representation wherever the wounds indicator is shown, so it does
    # not need to win this slot's priority the way diseased -- which has
    # no other visual representation -- does.
    STATUS_ICONS = {
      'IconSTUNNED'  => 'stunned.png',
      'IconWEBBED'   => 'webbed.png',
      'IconPOISONED' => 'poisoned.png',
      'IconDISEASED' => 'diseased.png',
      'IconBLEEDING' => 'bleeding.png',
    }.freeze

    def self.slots(indicators)
      Slots.new(
        posture: pick(indicators, POSTURE_ICONS),
        group: pick(indicators, GROUP_ICONS),
        stealth: pick(indicators, STEALTH_ICONS),
        status: pick(indicators, STATUS_ICONS)
      )
    end

    # icons is an ordered Hash (id => filename), so #find walks it in
    # priority order -- the highest-priority id that is currently visible
    # wins; nil ("blank") if none of the group's ids are currently true.
    def self.pick(indicators, icons)
      _id, filename = icons.find { |id, _filename| indicators[id] }
      filename
    end

    private_class_method :pick
  end
end
