# Universal Container Sorter

A standalone Lua mod for OpenMW 0.51. Hold the sorter modifier and activate a container to preview a category deposit or a Terraria-style Quick Stack. The sorter opens over the container's regular inventory window.

## Install

Add the folder containing `UniversalContainerSorter.omwscripts`, `scripts`, and `l10n` as an OpenMW data directory. Enable `UniversalContainerSorter.omwscripts` in the launcher, or add `content=UniversalContainerSorter.omwscripts` to `openmw.cfg`. The mod uses only Lua and can be added to an existing save without a migration. Uninstalling it leaves completed deposits in the game world.

The modifier defaults to **T**. OpenMW also defaults **Rest** to **T**. Rebind Rest under Controls or set the sorter to a free key such as **F8** under **Options → Scripts → Universal Container Sorter**. The modifier setting takes OpenMW key names such as `T`, `F8`, or `LeftCtrl`. Press and hold the modifier before activating, and keep it held until the container window appears. Enable **Debug logging** in the same script settings if the sorter does not open; look for `[Universal Container Sorter]` in `openmw.log`.

## Deposit items

- Select any combination of categories, or use **Select all**.
- Select **Quick Stack** to deposit items whose base record is already present in the target. The engine handles merging compatible stacks, so two instances of the same record can still stay in separate stacks.
- Category and Quick Stack counts show eligible units. The **Deposit** button shows how many units fit as whole stacks, and the capacity note reports the remainder. The sorter considers stacks in inventory order and can fit a smaller stack after skipping a larger one.
- **Cancel** returns to the regular container window. Confirming closes both windows and reports the deposit. If the selected stack IDs or counts change before confirmation, the sorter displays the updated preview for a fresh confirmation.

## Protections

| Scope | Behavior |
| --- | --- |
| Equipment, currency, and keys | Equipped stacks and engine gold records stay in your inventory. Keys stay in your inventory by default. Enable key deposits in the mod's settings if desired. |
| Favorites | With Inventory Extender 1.1 installed, favorite stacks are protected by their instance IDs. |
| Ownership | Containers and item references owned by another actor or faction are excluded. |
| Locks and traps | OpenMW handles activation normally. A container that starts the activation locked or trapped is skipped on that activation. |
| Organic or respawning containers | Excluded from sorting. |
| Scripted objects | MWScript items are always protected; MWScript containers are protected by default, with a setting to allow them. CUSTOM Lua container and item protection are separate opt-in settings, since mods can dynamically attach scripts to ordinary objects. Use favorites and the blacklist for special items and containers, including attachments defined in binary plugins. A script or blacklist rejection always logs the exact matching script or record ID. With both Lua protection settings off, no manifest scanning or Lua attachment queries occur. |
| Blacklist | Enter comma-separated item or container record IDs under **Protected record IDs**. |

The sorter uses OpenMW's record types for ordinary and mod-added Morrowind items. Its categories follow Inventory Extender, including the convention of grouping enchanted books with scrolls and lights with tools.

## Compatibility and implementation

The sorter reacts to the native `UiModeChanged` event, which supplies the opened container reference, and checks the physical modifier once. It does not subscribe to key presses, input actions, or per-frame updates. A short tap released before the UI event may fall through to normal activation.

The global container activation handler records whether the target was locked or trapped before the native action and leaves the engine's activation chain in place. The preview request validates that it matches that activation, consumes the record, and rechecks all normal container protections. A native activation that cannot be verified is rejected rather than bypassing protections. The sorter uses the stock Morrowind UI templates, so Inventory Extender can supply its own underlying inventory and container windows. Type-wide UI bookkeeping scripts, including Inventory Extender's, do not by themselves block sorting.

Inventory reads occur at preview and confirmation. Category toggles use the temporary preview data. The global script rechecks protections and capacity at confirmation and calls `GameObject:moveInto` once per approved stack. The preview is discarded on close, and the sorter writes no session data to the save.

## Validation

Run `lua tests/plan.lua` from this mod’s folder to check the capacity and stack-selection logic independently of OpenMW. Engine testing uses OpenMW 0.51.0 with a synthetic fixture and covers the input, UI, and transfer APIs separately from syntax and planner tests.

## Credits

Inspired by Mudcrab Island's ingredient sorter and Terraria's Quick Stack. Category conventions and favorite integration reference Ralts's Inventory Extender 1.1 (MIT). Its license is included in `LICENSE.InventoryExtender`. The sorter uses OpenMW's built-in UI assets.
