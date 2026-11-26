local types = require('openmw.types')
local brewing = require('scripts.art_of_alchemy_retort.brewing')
local rules = require('scripts.art_of_alchemy_retort.rules')

local grinding = {}

function grinding.output(record)
    return rules.groundOutput(types.Ingredient.records, record.id)
end

function grinding.recipeKey(record)
    local id = record.id
    if id:match('^ingred_6th_corprusmeat_0[1-7]$') then return 'ingred_6th_corprusmeat_g' end
    if id == 'food_kwama_egg_02' then return 'food_kwama_egg_01' end
    if id == 'ab_ingfood_kwamaeggcentwrap' then return 'ab_ingfood_kwamaeggcentcut' end
    local powder = grinding.output(record)
    return powder and powder.id or id
end

local rawInputsByPowder

function grinding.rawInputs(powderId)
    if not rawInputsByPowder then
        rawInputsByPowder = {}
        local seen = {}
        for _, group in ipairs({ rules.insoluble, rules.poorlySoluble }) do
            for id in pairs(group) do
                if not seen[id] then
                    seen[id] = true
                    local raw = types.Ingredient.records[id]
                    local ground = raw and grinding.output(raw)
                    if ground then
                        local list = rawInputsByPowder[ground.id] or {}
                        list[#list + 1] = raw
                        rawInputsByPowder[ground.id] = list
                    end
                end
            end
        end
    end
    return rawInputsByPowder[powderId] or {}
end

function grinding.effects(record)
    local effects = {}
    for _, entry in pairs(record.effects) do
        if entry.effect then effects[#effects + 1] = entry end
    end
    return effects
end

function grinding.plan(record, count, quality, stats, randomInteger)
    local output = grinding.output(record)
    if not output then return nil, 'This ingredient has no ground form in the loaded records.' end
    local attempts = math.floor(2 * quality * count)
    if attempts == 0 then return nil, 'This mortar needs a larger batch at its current quality.' end
    local limit = count * (rules.insoluble[record.id:lower()] and 3 or 1)
    local chance = brewing.chance(stats)
    local yield, elapsed = 0, attempts

    if chance >= 100 then
        yield = math.min(limit, attempts)
        elapsed = yield
    elseif chance >= 1 then
        for i = 1, attempts do
            if randomInteger(1, 100) <= chance then
                yield = yield + 1
                if yield == limit then
                    elapsed = i
                    break
                end
            end
        end
    end

    -- The original uses a half-hour divided by twice the apparatus quality per attempt.
    return { powderId = output.id, amount = yield, duration = elapsed * 1800 / (2 * quality) }
end

return grinding
