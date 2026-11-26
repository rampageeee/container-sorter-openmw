local content = require('openmw.content')
local brewing = require('scripts.art_of_alchemy_retort.brewing')
local rules = require('scripts.art_of_alchemy_retort.rules')

local replacementEffects = {
    ingred_kagouti_hide_g = { [3] = { 'resistblightdisease' } },
    ingred_snowbear_pelt_uniqueg = { [2] = { 'fortifyattribute', 'strength' }, [3] = { 'resistfrost' } },
    ingred_snowwolf_pelt_uniqueg = { [3] = { 'resistfrost' } },
    ingred_russula_01 = { [4] = { 'light' } },
    ingred_ectoplasm_01 = { [1] = { 'sanctuary' } },
    ingred_raw_glass_g = { [4] = { 'sanctuary' } },
    ingred_vampire_dust_01 = { [4] = { 'resistnormalweapons' } },
    ingred_daedra_skin_g = { [2] = { 'resistnormalweapons' } },
    ingred_raw_ebony_g = { [3] = { 'shield' } },
    ingred_corkbulb_root_01 = { [3] = { 'shield' } },
    ingred_netch_leather_g = { [1] = { 'poison' }, [2] = { 'fortifyattribute', 'endurance' } },
    ingred_bittergreen_petals_01 = { [1] = { 'poison' } },
    ingred_treated_bittergreen_uniq = { [1] = { 'poison' } },
}

local tier = { b = 1, c = 2, s = 3, q = 4, e = 5 }
local rating = { 40, 120, 300, 675, 1200 }
local duration = { 1, 3, 6, 12, 25 }
local magnitude = { 6, 12, 25, 50, 100 }
local recalculate = {
    restorehealth = true, restorefatigue = true, restoremagicka = true, restoreattribute = true,
    restoreskill = true, fortifymaximummagicka = true, fortifymagicka = true, fortifyhealth = true,
    fortifyfatigue = true, burden = true, sound = true,
}

local function adjustIngredient(record, changes)
    for slot, definition in pairs(changes) do
        local effect = record.effects[slot]
        effect.id = definition[1]
        effect.affectedAttribute = definition[2]
        effect.affectedSkill = nil
    end
end

local function adjustIngredients()
    local records = content.ingredients.records
    for id, changes in pairs(replacementEffects) do
        local record = records[id]
        if record then adjustIngredient(record, changes) end
    end
    local seen = {}
    for _, group in ipairs({ rules.insoluble, rules.poorlySoluble }) do
        for id in pairs(group) do
            if not seen[id] then
                seen[id] = true
                local record = records[id]
                local ground = record and rules.groundOutput(records, id)
                local changes = ground and replacementEffects[ground.id]
                if changes then adjustIngredient(record, changes) end
            end
        end
    end
end

local function adjustPotions()
    for _, potion in pairs(content.potions.records) do
        local quality = tier[potion.id:match('^p_.*_([bcsqe])$')]
        if quality and #potion.effects == 1 then
            local effect = potion.effects[1]
            local magic = content.magicEffects.records[effect.id]
            if magic then
                if recalculate[effect.id] then
                    local points, seconds = brewing.effectStats(magic, rating[quality])
                    effect.magnitudeMin, effect.magnitudeMax, effect.duration = points, points, seconds
                elseif magic.hasDuration and not magic.hasMagnitude then
                    effect.duration = duration[quality]
                elseif magic.hasMagnitude and not magic.hasDuration then
                    effect.magnitudeMin, effect.magnitudeMax = magnitude[quality], magnitude[quality]
                end
            end
        end
    end
end

return { engineHandlers = { onContentFilesLoaded = function()
    adjustIngredients()
    adjustPotions()
end } }
