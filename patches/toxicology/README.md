# Toxicology performance patch

Targets the OpenMW 0.51 build of [Toxicology](https://www.nexusmods.com/morrowind/mods/58976). The patch caches parts of NPC distribution, moves some combat checks to events, and reduces maintenance polling.

Apply [changes.patch](changes.patch) in the directory containing `scripts/toxicology`, following the [patch installation guide](../README.md). Override `actor.lua`, `global.lua`, and `init.lua` under their original paths. Keep the original settings files and `Toxicology.omwscripts` enabled.

The patch was applied to the source files used to develop it and reproduced the three override files byte for byte.
