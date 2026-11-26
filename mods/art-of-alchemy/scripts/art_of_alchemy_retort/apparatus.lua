local types = require('openmw.types')
local brewing = require('scripts.art_of_alchemy_retort.brewing')
local grinding = require('scripts.art_of_alchemy_retort.grinding')

local apparatus = {}
local maxPotionBatch = 3

local function potionEffects(record)
    local effects = {}
    for _, effect in ipairs(record.effects) do
        if effect.effect then effects[#effects + 1] = effect end
    end
    return effects
end

apparatus.retort = {
    input = types.Ingredient,
    effects = brewing.getIngredientEffects,
    recipeKey = grinding.recipeKey,
    slots = 3,
    minimum = 2,
    maxBatch = maxPotionBatch,
    inputLabel = 'Ingredients',
    action = 'Brew',
    activity = 'Brewing',
}
apparatus.alembic = {
    input = types.Potion,
    effects = potionEffects,
    slots = 2,
    minimum = 1,
    maxBatch = maxPotionBatch,
    allowRepeated = true,
    inputLabel = 'Potions',
    action = 'Combine',
    activity = 'Combining',
    modes = { 'Concentrate', 'Filter' },
}
apparatus.calcinator = {
    input = types.Potion,
    effects = potionEffects,
    slots = 1,
    minimum = 1,
    maxBatch = maxPotionBatch,
    inputLabel = 'Potion',
    action = 'Purify',
    activity = 'Purifying',
    modes = { 'Clear negative', 'Clear positive' },
}

apparatus.mortar = {
    input = types.Ingredient,
    effects = grinding.effects,
    output = grinding.output,
    slots = 1,
    minimum = 1,
    inputLabel = 'Ingredient',
    action = 'Grind',
    activity = 'Grinding',
}

local byType = {
    [types.Apparatus.TYPE.MortarPestle] = 'mortar',
    [types.Apparatus.TYPE.Retort] = 'retort',
    [types.Apparatus.TYPE.Alembic] = 'alembic',
    [types.Apparatus.TYPE.Calcinator] = 'calcinator',
}

function apparatus.kind(record)
    return byType[record.type]
end

local qualityTiers = { a = 0.75, j = 1, m = 1.25, g = 1.5 }

function apparatus.quality(record, useOriginalTiers)
    local tier = useOriginalTiers and qualityTiers[record.id:match('^apparatus_([ajmg])_')]
    return tier or math.max(0.01, record.quality)
end

function apparatus.stats(actor)
    local attributes = types.Actor.stats.attributes
    return {
        alchemy = types.NPC.stats.skills.alchemy(actor).modified,
        intelligence = attributes.intelligence(actor).modified,
        luck = attributes.luck(actor).modified,
    }
end

function apparatus.refine(kind, inputs, stats, quality, mode)
    if kind == 'alembic' then
        local product = brewing.combine(inputs, stats, quality, mode)
        if product then return product end
        return nil, 'The potions need to share at least half the effects of each potion.'
    end
    local product = brewing.purify(inputs[1], stats, quality, mode)
    if product then return product end
    return nil, 'This potion has no effects of the selected kind.'
end

return apparatus
