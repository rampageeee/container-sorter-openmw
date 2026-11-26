# Potion Thrower message compatibility patch

Targets OpenMW 0.51 and [Potion Thrower for OpenMW](https://www.nexusmods.com/morrowind/mods/56825) by YossarianO. Potion Thrower’s messages use a `text` field. The patch lets the handler ignore other `ShowMessage` events, including OpenMW notifications that use `message`.

Apply [changes.patch](changes.patch) from the directory containing the original `pt_player.lua`, following the [patch installation guide](../README.md). Install the resulting file as an override at the same path as the original script.

The patch was applied to the original script and reproduced the recovered override byte for byte.
