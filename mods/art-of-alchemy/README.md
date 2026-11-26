# The Art of Alchemy

Experimental build 0.6.0 for OpenMW 0.51.0. Based on VitruvianGuar’s The Art of Alchemy 1.0.4. This build uses the apparatus already in your Morrowind installation and the ground ingredients from the original mod.

## Install or update in Mod Organizer 2

1. Install the mod ZIP or package this folder as a ZIP for MO2. The mod’s data directory contains `Art_of_Alchemy_Retort.omwscripts` and `scripts`.
2. If updating, replace the previous MO2 version and keep the same script list enabled. Its name also identifies the scripts that store pending batches.
3. For grinding, also enable the original `The Art of Alchemy.ESP` and its meshes, textures, and icons. Keep the original directory structure. Enable the mod and export through OpenMW Player. Confirm that `Art_of_Alchemy_Retort.omwscripts` appears in your OpenMW content list.

For a manual install, point `openmw.cfg` at the extracted folder.

```ini
data="D:\OpenMWMods\Art_of_Alchemy"
content=The Art of Alchemy.ESP
content=Art_of_Alchemy_Retort.omwscripts
```

## Use placed apparatus

Drop and activate an apparatus to see your available inputs, the selected recipe, and its preview in one window. Click a carried item to add it and click a selected item to remove it. Single-slot apparatus let you click another item to replace the selection. **Clear** empties the recipe. **Search** finds item names and known effects.

Click a known effect to filter the list by its exact target, such as Fortify Strength. The number beside each effect counts distinct eligible items. **Pin** places the effect at the top of this character’s list, and **All** clears the effect filter. **Matching only** narrows the list to known effects shared with your current selection. Unknown effects remain available for experimentation with this toggle off.

The recipe preview shows expected magnitude and duration on success. The retort also shows the carried bottle count and flags recipes with a possible side effect. The alembic and calcinator show strength changes and removed effects.

| Apparatus | Workflow |
| --- | --- |
| Retort | Brew with two or three different ingredients that share an effect. Three matching ingredients strengthen that effect. Raw and ground forms of an ingredient and equivalent variants such as small and large kwama eggs count as one ingredient. |
| Alembic | Refine one potion or use two to combine their effects. With two potions, at least half of each potion’s effects must match. **Concentrate** strengthens shared effects. **Filter** subtracts the first potion’s shared strength from the second, with a minimum based on skill and apparatus quality. |
| Mortar and pestle | Choose an eligible ingredient and grind it into the original ESP’s dust or powder. The ground material goes straight into your inventory at completion. |
| Calcinator | Choose a potion and select **Clear negative** or **Clear positive**. The selected effects weaken or disappear. |

Use **−**, **+**, or **Max** to set the batch size. The retort, alembic, and calcinator can each make up to three potions per batch. The quantity is taken from each filled slot. **Custom** makes a generated potion. Choose **Standard**, or hold Ctrl while starting, to look up an existing single-effect potion of the appropriate target and strength. If no standard potion matches, the apparatus makes a custom potion.

Drop multiple apparatuses to process separate batches at the same time. Activate working apparatus to see its progress bar. The default brewing time is one in-game hour. Grinding time depends on the mortar’s quality and the number of attempts needed. The batch outcome is rolled at the start and becomes available at completion. An idle portable apparatus can be picked up with **Take**. Faction-owned equipment requires the appropriate rank and a current membership in good standing. Use **Help** in an apparatus menu for its controls.

Collecting a finished retort batch uses one carried **Bottle** per potion. The ordinary Morrowind clutter items named Bottle work for any potion strength. Brewing can begin with zero bottles. If you have fewer bottles than finished potions, you can bottle what you have room for and collect the rest later. A custom name applies to the whole batch. The requirement also applies to standard and special retort potions and pending retort batches from 0.4.0. Alembic and calcinator outputs reuse their input vessels.

The retort’s **Bottle** submenu lets you choose a custom potion’s appearance by its inventory icon. **Random** picks one available icon and matching world model per batch. Appearance is cosmetic. Identical potions in different bottles appear in separate stacks.

After selecting a brewable mixture, open **Recipes**, enter a name, and choose **Save mixture**. Select a saved recipe to restore its ingredients, bottle choice, and Custom or Standard mode. You need to carry its ingredients to load it. The recipe name becomes the default name of its custom potion. OpenMW keeps recipes in its persistent player storage, shared across characters using the same OpenMW configuration.

## Discovery, naming, and settings

The ingredient picker shows `?` for unknown effects and filters by known effects. Alchemy skill, tasting, and brewing reveal effects. Selecting a ground ingredient, grinding one, or tasting it can carry known effects back to its raw forms. Matching known effects and harmful effects use different colors in the picker. Discovery is stored in the character’s save.

Collecting a custom potion opens a naming dialog with the effects and strength. Enter a name and click **Collect**, or use **Use default**. Standard potions keep their existing record and name. The Jack of All Trades recipe awards its eight timed Fortify Attribute effects from the original recipe.

OpenMW’s **Scripts → The Art of Alchemy** settings include brewing time, XP multiplier, knowledge discovery, potion naming, inventory restrictions, apparatus help, and the original quality tiers. XP from the mod scales with the brewing-time setting. At 60 game minutes it uses the base award. The inventory restriction covers the normal item-use path in OpenMW 0.51. The engine’s quick-key and MWScript paths can bypass the item-use hook.

Enable `Art_of_Alchemy_Record_Balance.omwscripts` to apply the original ingredient and standard potion balance changes once when OpenMW loads content. It updates the relevant fields of the records resolved by your load order. This is optional and separate from the original apparatus quality option, which changes the mod’s calculations. The optional apparatus model substitutions remain pending.

## Feedback and performance

- The retort and calcinator use the original `Light_Fire` offsets and scales. Their world fires go out at completion. Completion plays a positional cue and, when available, a magic effect from the resulting potion. Menu and collection sounds use the installed game’s sound records.
- Each batch schedules one saved game-time timer. Progress is calculated on activation. There are no per-frame gameplay callbacks. Let pending batches finish before removing the mod so their fires can be cleaned up.
- The menu indexes carried inputs on activation. Search, matching, and scrolling use that index. Use the mouse wheel over a list or drag its scrollbar. Recipe calculations run when the selection or brewing mode changes. Standard potions are indexed on first use and identical generated recipes reuse their records.

## Mortar visuals and animation

The ESP contains 109 ingredient records and no stationary apparatus placements. Keep its original asset directories enabled so the game can display the ground ingredients. The mod looks up the matching ESP output for each eligible carried ingredient. It resolves numbered beetle shells to their specific outputs where present.

The mortar plays stock ingredient handling sounds. The player grinding animation still needs the binary files shown in the screenshots. The MWSE mod temporarily loads `AM_Alchemist.nif`, plays `idle9`, and attaches separate mortar and pestle meshes near the hand bones. In OpenMW 0.51, the route to test is an additional animation source, for example a KF under `Animations/xbase_anim/` when using the standard third-person animation base. Give the sequence a dedicated text-key group so it can be played on demand without changing ordinary idle animations. OpenMW’s bone-attached VFX API could display the props, with any necessary transform offsets baked into the models. This has yet to be tested with the original binaries.

## Scope and verification

This build handles unscripted retorts, alembics, calcinators, and mortars. The apparatus activation route can overlap with other alchemy mods. Tests used the OpenMW 0.51.0 runtime with synthetic game data and the provided ESP for grinding. The combined build was tested with the normal ingredient consumption event, protected raw minerals, configurable brewing time, custom potion naming, the eight-effect recipe, the optional record balance, and a pending mortar batch saved in 0.3.0.

The mortar animation and apparatus model substitutions still need work. Discovery and effect presentation are in the mod’s own picker and recipe UI. Behavior with the full Tamriel Rebuilt and Skill Evolution load order remains unverified.

## License and attribution

The [MIT License](LICENSE) applies to the OpenMW source and documentation authored for this project. The original MWSE mod, ESP, and assets remain under VitruvianGuar’s terms. Get the original ESP and assets from the original mod.
