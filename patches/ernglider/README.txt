ERNGLIDER PERFORMANCE OVERRIDE BUILDER
Upstream revision: 022854aadce519d7fc53deee1c93c13883dc0839

Windows: extract this builder archive, then double-click Build-ErnGlider.cmd.
Requires Python 3 and internet access to raw.githubusercontent.com.
This creates ErnGlider_optimized_override.zip next to the builder. It does not modify the installed mod.

Alternatively, from a command prompt, use installed original files:
  py -3 build_ernglider_optimized.py --source "D:\ModOrganizer\mods\ErnGlider"
The local source must match the pinned upstream commit exactly (CRLF checkouts accepted).

Install the generated override ZIP as a separate MO2 mod, with higher priority than ErnGlider, or extract it into the original 00 Core data directory. It contains five Lua files under scripts/ErnGlider/. No changes to plugins, OMWSCRIPTS, assets or saved data format.

Changes: independent 0.3 second collision timers; simulation-rate updraft integration; bounded empty-cell cache; no repeated zero-updraft reply; reset updraft state on exit; inactive animation callback early return; no CHIM gate generation or HUD data preparation when disabled; inactive shader uniform updates skipped. Existing surf-spell refresh and shield VFX requests retained because their engine lifecycle is not verified. Four player frame/update callbacks remain registered but perform only guards while inactive. Updraft visual effect lifecycle is unchanged. A new glide can receive updraft effects immediately rather than waiting 0.3 seconds; CHIM gate generation occurs when enabled at the start of a surf run. The raycast interval restores the original author's apparent intent but may affect collision detection at high speeds.

Validation: source blob IDs and exact replacement anchors checked against upstream source; builder syntax and replacement mechanics checked. No OpenMW runtime or full generated Lua compilation test was performed. Back up your save and test collision, updrafts, shield surfing and camera transitions before committing to the override.

Original author: Erin Pentecost. AGPL-3.0-or-later. Source: https://github.com/ernmw/ErnGlider/tree/022854aadce519d7fc53deee1c93c13883dc0839
