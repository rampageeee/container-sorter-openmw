# Talking Matters Remastered compatibility patches

Targets the OpenMW build of [Talking Matters Remastered 1.2](https://www.nexusmods.com/morrowind/mods/56832) and its mwse2openmw adapter. The mod patch recovers its configuration if menu setup fails or runs out of order. The adapter patch checks that a settings group was registered before it tries to duplicate the group’s storage.

Following the [patch installation guide](../README.md), apply each patch in the directory containing its target file.

| Patch | Target file |
| --- | --- |
| [talking-matters.patch](talking-matters.patch) | `main.lua` in the mod’s `talkingMatters` folder |
| [mwse2openmw.patch](mwse2openmw.patch) | `mcm.lua` in the adapter’s `omw_mwse` folder |

Keep the respective paths when installing the overrides. Both patches reproduced the recovered override files byte for byte when applied to the original scripts.
