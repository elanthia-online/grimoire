require 'spec_helper'

RSpec.describe Grimoire::IndicatorGroups do
  describe '.slots' do
    it 'returns all four slots blank when nothing has been seen yet' do
      slots = described_class.slots({})

      expect(slots.posture).to be_nil
      expect(slots.group).to be_nil
      expect(slots.stealth).to be_nil
      expect(slots.status).to be_nil
    end

    describe 'posture' do
      # Revised from an earlier "blank while standing" design -- the
      # user's own later spec (2026-09-15): posture is meant to always
      # show something once populated, establishing the 4-icon block's
      # baseline state (a single posture icon plus three blank
      # placeholders), rather than being blank in the common case.
      it 'shows standing in its own icon rather than leaving the slot blank' do
        slots = described_class.slots('IconSTANDING' => true)

        expect(slots.posture).to eq('standing.png')
      end

      it 'shows kneeling/sitting/prone in their own icon' do
        expect(described_class.slots('IconKNEELING' => true).posture).to eq('kneeling.png')
        expect(described_class.slots('IconSITTING' => true).posture).to eq('sitting.png')
        expect(described_class.slots('IconPRONE' => true).posture).to eq('prone.png')
      end

      it 'shows dead, not prone, when both are true -- dead always implies prone' do
        slots = described_class.slots('IconDEAD' => true, 'IconPRONE' => true)

        expect(slots.posture).to eq('dead.png')
      end

      it 'falls back to a fixed priority order if more than one posture is ever true at once (a wire glitch, not a real state)' do
        slots = described_class.slots('IconSITTING' => true, 'IconKNEELING' => true)

        expect(slots.posture).to eq('sitting.png')
      end

      it 'prioritizes any other posture over standing if both are ever true at once (a wire glitch, not a real state)' do
        slots = described_class.slots('IconSTANDING' => true, 'IconKNEELING' => true)

        expect(slots.posture).to eq('kneeling.png')
      end

      it 'ignores a false/absent flag alongside a true one' do
        slots = described_class.slots('IconKNEELING' => false, 'IconPRONE' => true)

        expect(slots.posture).to eq('prone.png')
      end
    end

    describe 'group' do
      it 'shows joined when true' do
        expect(described_class.slots('IconJOINED' => true).group).to eq('joined.png')
      end

      it 'is blank when not joined' do
        expect(described_class.slots('IconJOINED' => false).group).to be_nil
      end

      it 'has no bearing on any other slot, including posture/death' do
        slots = described_class.slots('IconJOINED' => true, 'IconDEAD' => true)

        expect(slots.group).to eq('joined.png')
        expect(slots.posture).to eq('dead.png')
      end
    end

    describe 'stealth' do
      it 'shows hidden or invisible in their own icon' do
        expect(described_class.slots('IconHIDDEN' => true).stealth).to eq('hidden.png')
        expect(described_class.slots('IconINVISIBLE' => true).stealth).to eq('invisible.png')
      end

      it 'is blank when neither is true' do
        expect(described_class.slots('IconHIDDEN' => false, 'IconINVISIBLE' => false).stealth).to be_nil
      end

      # Confirmed mutually exclusive by an actual captured game log
      # (2026-09-15): hiding is refused outright while invisible, and
      # casting invisibility while hidden forces "You come out of hiding."
      # first -- both true at once should never really happen, but the
      # priority order still needs to pick one if it does.
      it 'falls back to invisible over hidden if both are ever true at once (a wire glitch, not a real state)' do
        slots = described_class.slots('IconHIDDEN' => true, 'IconINVISIBLE' => true)

        expect(slots.stealth).to eq('invisible.png')
      end
    end

    describe 'status' do
      it 'shows each affliction in its own icon when it is the only one active' do
        expect(described_class.slots('IconSTUNNED' => true).status).to eq('stunned.png')
        expect(described_class.slots('IconWEBBED' => true).status).to eq('webbed.png')
        expect(described_class.slots('IconPOISONED' => true).status).to eq('poisoned.png')
        expect(described_class.slots('IconBLEEDING' => true).status).to eq('bleeding.png')
        expect(described_class.slots('IconDISEASED' => true).status).to eq('diseased.png')
      end

      it 'is blank when no affliction is active' do
        expect(described_class.slots({}).status).to be_nil
      end

      # The user's own spec (2026-09-15): unlike posture/stealth, these
      # five are not mutually exclusive -- multiple can genuinely be true
      # at once. This slot deliberately shows only the highest-priority
      # one (most action-restricting first), trading simultaneous
      # visibility for a static 4-icon width.
      it 'prioritizes stunned over every other simultaneous affliction' do
        slots = described_class.slots(
          'IconSTUNNED' => true, 'IconWEBBED' => true, 'IconPOISONED' => true,
          'IconBLEEDING' => true, 'IconDISEASED' => true
        )

        expect(slots.status).to eq('stunned.png')
      end

      it 'prioritizes webbed over poisoned/bleeding/diseased when not stunned' do
        slots = described_class.slots('IconWEBBED' => true, 'IconPOISONED' => true, 'IconBLEEDING' => true)

        expect(slots.status).to eq('webbed.png')
      end

      it 'prioritizes poisoned over diseased/bleeding when not stunned or webbed' do
        slots = described_class.slots('IconPOISONED' => true, 'IconBLEEDING' => true, 'IconDISEASED' => true)

        expect(slots.status).to eq('poisoned.png')
      end

      # Diseased outranks bleeding (2026-09-15): bleeding already gets its
      # own separate representation wherever the wounds indicator is
      # shown, so it does not need to win this slot too.
      it 'prioritizes diseased over bleeding when nothing higher-priority is active' do
        slots = described_class.slots('IconBLEEDING' => true, 'IconDISEASED' => true)

        expect(slots.status).to eq('diseased.png')
      end
    end

    it 'ignores indicator ids that do not belong to any of the four groups' do
      slots = described_class.slots('IconSOMETHINGUNKNOWN' => true)

      expect(slots.posture).to be_nil
      expect(slots.group).to be_nil
      expect(slots.stealth).to be_nil
      expect(slots.status).to be_nil
    end

    it 'fills all four slots independently from one combined snapshot' do
      slots = described_class.slots(
        'IconKNEELING' => true, 'IconJOINED' => true, 'IconHIDDEN' => true, 'IconBLEEDING' => true
      )

      expect(slots.posture).to eq('kneeling.png')
      expect(slots.group).to eq('joined.png')
      expect(slots.stealth).to eq('hidden.png')
      expect(slots.status).to eq('bleeding.png')
    end
  end
end
