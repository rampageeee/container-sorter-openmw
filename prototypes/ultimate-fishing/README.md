# Ultimate Fishing for OpenMW 0.51.0

First playable prototype based on Ultimate Fishing 1.6.15. It uses the original fishing pole, lure, fish records, and sounds. The OpenMW scripts handle the cast, the bite window, and the tension-based fight. The initial catch pool contains five species or variants, with simple depth, time, and interior restrictions.

## Install

1. Install [OAAB Data](https://www.nexusmods.com/morrowind/mods/49042) and [Ultimate Fishing 1.6.15](https://www.nexusmods.com/morrowind/mods/52872). OpenMW uses the original mod's `UltimateFishing.esp` and its art and sound folders. The MWSE scripts, Skills Module, and The Crafting Framework are unnecessary for this prototype.
2. Install this folder as a separate MO2 mod. The mod root should directly contain `UltimateFishingOpenMW.esp`. For a manual installation, add this folder as an OpenMW data directory.
3. Check the OpenMW content order. The original plugin must be active, with its own masters above it. Place the new plugin and script list after it.

   ```ini
   content=UltimateFishing.esp
   content=UltimateFishingOpenMW.esp
   content=UltimateFishingOpenMW.omwscripts
   ```

   In MO2, verify the resulting `openmw.cfg` after export. The `.omwscripts` entry is required.

## Try a cast

1. Open the in-game console and add the original pole for this test build.

   ```text
   player->AddItem "mer_fishing_pole_01" 1
   ```

2. Equip the pole and draw it with your usual weapon-ready key. Try a clear shoreline such as the Seyda Neen docks. Aim down at open water a short distance from shore and press **F6**.
3. When the bite message appears, press **F6** again within the bite window. Hold it to reel, then release before the tension reaches 100%. Reel again before it falls to 0%. Tire the fish to land it in your inventory.
4. Press **F7** to cancel. Moving away, swimming, sheathing, changing cells, taking a combat hit, or opening a menu also ends the cast. Loading a save ends any cast that was in progress.

## Third-person pose test

Switch to third person, equip and draw the pole, then press **Shift+F6** while idle. The archive includes the upstream `xfishing_idle.kf` with its two `Idle9` text keys renamed to the unique group `ufrod`. The original vanilla group is unaffected.

The pose test requires this setting under the existing `[Game]` section in `settings.cfg`. Restart OpenMW after changing it. The core fishing loop works without changing this setting.

```ini
[Game]
use additional anim sources = true
```

This is a test of one baked third-person pose. The original first-person and procedural rod, line, and player animations have no implementation in this build. The larger catch tables, bait, skills, loot, merchants, filleting, and nets are outside this prototype.

## Performance and verification

The player script has no `onUpdate` or `onFrame` handler. Its cast timers are created on demand, and the global script reacts to events. Movement and water-depth checks are limited to an active cast or fight. Simulated gameplay tests covered catches, line breaks, cancellation, and cleanup. An OpenMW 0.51 test game verified lure creation, movement, removal, and inventory rewards. Lure visibility, shoreline aiming, and pose playback still need a test with Morrowind data.

Based on [Ultimate Fishing v1.6.15](https://github.com/jhaakma/fishing/tree/f61000fc642109b5b6491473d61a6d99a1edef1c) by Merlord, Greatness7, and Melchior Dahrk. See `LICENSE` for the upstream MIT notice.
