# Pay Taxes timer patch

Targets the `Pay_taxes.omwaddon` used with [Pay taxes in Morrowind](https://www.nexusmods.com/morrowind/mods/53698) on OpenMW 0.51. This patch schedules the recurring tax check just after in-game midnight.

1. Follow the [patch installation guide](../README.md) and apply [pay-taxes-addon.patch](pay-taxes-addon.patch) in a directory with a copy of the original `Pay_taxes.omwaddon`. The binary patch expects the exact source version.
2. Install the resulting `Pay_taxes.omwaddon` with this folder’s `Pay_taxes_timer.omwscripts` and `scripts` directory. Keep the add-on at its original position in the content order. Give the modified file higher file priority than the original.
3. Enable `Pay_taxes_timer.omwscripts` after `Pay_taxes.omwaddon`.

On a save with taxes already active, the original script passes its last processed date to the timer. The rate, reserve, and current cycle counter carry over. In a new game, taxes start when you choose a nonzero rate or Auto. After a time skip, an overdue timer processes the current date once and schedules the next midnight.

The binary patch reproduced the recovered add-on byte for byte. Earlier checks used a Lua harness.
