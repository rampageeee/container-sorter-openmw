# Mudcrab Island Ingredient Sorter

An OpenMW 0.51.0 prototype for the ingredient chest in [Mudcrab Island](https://www.nexusmods.com/morrowind/mods/43449).

1. In the Construction Set, make a separate compatibility plugin overriding the `MI_chest_ingredients` container record. Clear its `Script` field, which references `MI_ingredient_chest_script`. Load the override after Mudcrab Island and other overrides affecting the chest.
2. Add the folder containing `MI_UniversalSorter.omwscripts` as an OpenMW data directory. Enable the script list after Mudcrab Island.
3. Activate the chest. **Yes** deposits ingredient stacks and opens it. **No** opens it without depositing items. **Escape** cancels the prompt.

The sorter skips scripted ingredients by default. Add any other records you want to exclude to the table in [global.lua](scripts/mi_universal_sorter/global.lua).

Earlier verification covered Lua syntax. The OpenMW runtime and compatibility with other activation mods still need testing.
