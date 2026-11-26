# Lua NPC Schedule performance patch

Targets [Lua NPC Schedule](https://www.nexusmods.com/morrowind/mods/58635) on OpenMW 0.51.0. Install this folder as a separate OpenMW data directory with higher file priority than Lua NPC Schedule. Keep the original `Lua NPC Schedule.omwscripts` enabled.

Animated departures share the configured batch size and delay. The global schedule uses a simulation timer. An NPC’s half-second checks run while it is traveling, delaying a departure, or waiting for a chore. Ordinary routes use one engine Travel package per destination. The patch uses the existing save format and recreates its transient timers after loading.

Earlier verification covered Lua syntax and simulated engine events. In-game frame times and navigation still need testing. The [upstream license notice](LICENSE) is included.
