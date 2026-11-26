# AURA performance patch

Targets [AURA (OpenMW) 0.9.1](https://www.nexusmods.com/morrowind/mods/59428) by RageFiasco. The patch reuses record information within object scans and reduces repeated work for populated ruins, static sound sources, and sounds heard through doors.

Apply [changes.patch](changes.patch) in the directory containing `scripts/aura_openmw`, following the [patch installation guide](../README.md). Override the nine modified Lua files under the same `scripts/aura_openmw` paths and keep the original content files enabled.

The patch was applied to the source files used to develop it and reproduced all nine override files byte for byte.
