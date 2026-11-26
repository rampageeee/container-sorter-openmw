local rules = require('scripts.art_of_alchemy_retort.rules')

local brewing = {}

function brewing.effectKey(effect)
    return effect.id .. '/' .. (effect.affectedAttribute or '') .. '/' .. (effect.affectedSkill or '')
end

function brewing.getIngredientEffects(record)
    local result = {}
    if rules.insoluble[record.id:lower()] then
        return result
    end
    local poorlySoluble = rules.poorlySoluble[record.id:lower()]
    for slot, entry in pairs(record.effects) do
        if (not poorlySoluble or slot == 1) and entry.effect then
            result[#result + 1] = entry
        end
    end
    return result
end

function brewing.match(ingredients)
    local byKey = {}
    for _, ingredient in ipairs(ingredients) do
        local seen = {}
        for _, entry in ipairs(brewing.getIngredientEffects(ingredient)) do
            local key = brewing.effectKey(entry)
            if not seen[key] then
                local match = byKey[key]
                if match then
                    match.count = match.count + 1
                else
                    byKey[key] = { entry = entry, count = 1, key = key }
                end
                seen[key] = true
            end
        end
    end
    local shared, uncommon = {}, {}
    for _, match in pairs(byKey) do
        local group = match.count > 1 and shared or uncommon
        group[#group + 1] = match
    end
    local function byEffect(a, b) return a.key < b.key end
    table.sort(shared, byEffect)
    table.sort(uncommon, byEffect)
    return shared, uncommon
end

-- Sum the original diminishing returns until every later contribution rounds to zero.
local function effectiveAttribute(value)
    value = math.max(0, value)
    local result, divisor = 0, 1
    while value > 100 and divisor <= 100 do
        result = result + math.floor(100 / divisor)
        value = value - 100
        divisor = divisor + 1
    end
    return result + (divisor <= 100 and math.floor(value / divisor) or 0)
end

local function round(value)
    return math.floor(value + 0.5)
end

function brewing.effectStats(effect, power, durationMultiplier)
    local settings = rules.override[effect.id]
    if settings then
        power = power / settings.powerDiv
        if settings.duration ~= nil then
            return math.max(1, round(power / math.max(1, settings.duration))), settings.duration
        end
    end
    if not effect.hasMagnitude and not effect.hasDuration then
        return 0, 0
    elseif not effect.hasMagnitude then
        return 0, math.max(1, round(power / 48))
    elseif not effect.hasDuration then
        return math.max(1, round(power / 12)), 0
    end
    durationMultiplier = durationMultiplier or (power < 100 and 1.5 or (power < 250 and 2 or 3))
    local magnitude = math.sqrt(power / durationMultiplier)
    return math.max(1, round(magnitude)), math.max(1, round(magnitude * durationMultiplier))
end

function brewing.power(effect, magic)
    if not magic.hasMagnitude and not magic.hasDuration then
        return 300
    end
    if not magic.hasMagnitude then
        return 48 * effect.duration
    end
    local magnitude = (effect.magnitudeMin + effect.magnitudeMax) / 2
    if not magic.hasDuration then
        return 12 * magnitude
    end
    return magnitude * effect.duration
end

local standardPotions

function brewing.standardPotion(records, effect, magic)
    if not standardPotions then
        standardPotions = {}
        for _, record in pairs(records) do
            if record.id:match('^p_.*_[bcsqe]$') and #record.effects == 1 then
                local effectData = record.effects[1]
                if effectData.effect then
                    local key = brewing.effectKey(effectData)
                    local entries = standardPotions[key] or {}
                    entries[#entries + 1] = { id = record.id, power = brewing.power(effectData, effectData.effect) }
                    standardPotions[key] = entries
                end
            end
        end
        for _, entries in pairs(standardPotions) do
            table.sort(entries, function(a, b)
                if a.power ~= b.power then return a.power > b.power end
                return a.id < b.id
            end)
        end
    end
    local power = brewing.power(effect, magic)
    for _, entry in ipairs(standardPotions[brewing.effectKey(effect)] or {}) do
        if entry.power <= power then return entry.id end
    end
end

function brewing.customName(value)
    if type(value) ~= 'string' then return nil end
    local name = value:gsub('%c', ' '):match('^%s*(.-)%s*$')
    if name ~= '' and #name <= 160 then return name end
end

function brewing.chance(stats)
    return stats.alchemy + stats.intelligence / 5 + stats.luck / 10
end

function brewing.basePower(stats, quality)
    local rating = math.max(1, stats.alchemy + effectiveAttribute(stats.intelligence) / 5
        + effectiveAttribute(stats.luck) / 10)
    return math.max(1, round(rating * math.log(rating) * quality))
end

local function synergyFactor(entries)
    local synergy = 0
    for i, entry in ipairs(entries) do
        local combinations = rules.combinations[entry.id]
        for j = 1, i - 1 do
            local other = entries[j].id
            local reverse = rules.combinations[other]
            if (combinations and combinations[other]) or (reverse and reverse[entry.id]) then
                synergy = synergy + 1
            end
        end
    end
    return 1 + 0.1 * synergy
end

local function makeProduct(entries, powers, originals, durationMultiplier)
    local result = {}
    local strongest, netPower, weight = 0, 0, 0
    for i, entry in ipairs(entries) do
        local power = powers[i]
        local magnitude, duration = brewing.effectStats(entry.effect, power, durationMultiplier)
        local original = originals and originals[i]
        result[#result + 1] = {
            id = entry.id,
            affectedAttribute = entry.affectedAttribute,
            affectedSkill = entry.affectedSkill,
            magnitudeMin = original and original.magnitudeMin or magnitude,
            magnitudeMax = original and original.magnitudeMax or magnitude,
            duration = original and original.duration or duration,
        }
        strongest = math.max(strongest, power)
        netPower = netPower + (entry.effect.harmful and -power or power)
        weight = weight + (power >= 1200 and 0.25 or power >= 675 and 0.5
            or power >= 300 and 0.75 or power >= 120 and 1 or 1.5)
    end
    local bottle = strongest >= 1200 and 'exclusive' or strongest >= 625 and 'quality'
        or strongest >= 300 and 'standard' or strongest >= 120 and 'cheap' or 'bargain'
    return { effects = result, value = math.floor(math.abs(netPower) / 8), weight = weight, bottle = bottle }
end

function brewing.sideEffects(shared, uncommon)
    local opposite = {}
    if #shared == 1 and shared[1].count == 2 then
        for _, match in ipairs(uncommon) do
            if match.entry.effect.harmful ~= shared[1].entry.effect.harmful then
                opposite[#opposite + 1] = match
            end
        end
    end
    return opposite
end

function brewing.retortProduct(matches, stats, quality)
    local entries, powers = {}, {}
    for i, match in ipairs(matches) do
        entries[i] = match.entry
    end
    local basePower = brewing.basePower(stats, quality) * synergyFactor(entries)
    for i, match in ipairs(matches) do
        powers[i] = basePower * (match.count == 3 and 1.5 or 1)
    end
    return makeProduct(entries, powers)
end

function brewing.roll(shared, uncommon, stats, quality, randomInteger)
    local chance = brewing.chance(stats)
    if randomInteger(1, 100) > chance then return nil end
    local matches = shared
    if #shared == 1 and shared[1].count == 2 and randomInteger(1, 100) > chance then
        local opposite = brewing.sideEffects(shared, uncommon)
        if #opposite > 0 then matches = { shared[1], opposite[randomInteger(1, #opposite)] } end
    end
    return brewing.retortProduct(matches, stats, quality)
end

function brewing.combine(inputs, stats, quality, mode)
    local entries, powers, byKey = {}, {}, {}
    local shared, required = 0, 0
    local base = brewing.basePower(stats, quality)
    local maxPower = 2 * base
    local minPower = base / (2 * quality * quality)
    for _, effects in ipairs(inputs) do
        if #effects == 0 then return nil end
        local oldSynergy = synergyFactor(effects)
        local seen = {}
        required = math.max(required, math.ceil(#effects / 2))
        for _, effect in ipairs(effects) do
            local key = brewing.effectKey(effect)
            if not seen[key] then
                local power = brewing.power(effect, effect.effect) / oldSynergy
                local index = byKey[key]
                if not index then
                    index = #entries + 1
                    byKey[key] = index
                    entries[index], powers[index] = effect, power
                else
                    shared = shared + 1
                    if mode == 2 then
                        powers[index] = math.max(minPower, power - powers[index])
                    else
                        powers[index] = math.min(maxPower, power + powers[index])
                    end
                end
                seen[key] = true
            end
        end
    end
    if #inputs > 1 and shared < required then return nil end
    local newSynergy = synergyFactor(entries)
    for i, power in ipairs(powers) do powers[i] = power * newSynergy end
    return makeProduct(entries, powers, nil, 3)
end

function brewing.purify(effects, stats, quality, mode)
    local removeHarmful = mode ~= 2
    local targets = 0
    for _, effect in ipairs(effects) do
        if effect.effect.harmful == removeHarmful then targets = targets + 1 end
    end
    if targets == 0 then return nil end

    local entries, powers, originals = {}, {}, {}
    local reduction = round(brewing.basePower(stats, quality) / targets)
    for _, effect in ipairs(effects) do
        local power = brewing.power(effect, effect.effect)
        local targeted = effect.effect.harmful == removeHarmful
        if targeted then power = power - reduction end
        if power > 0 then
            local i = #entries + 1
            entries[i], powers[i] = effect, power
            if not targeted then originals[i] = effect end
        end
    end
    if #entries == 0 then return { effects = {} } end

    local oldSynergy, newSynergy = synergyFactor(effects), synergyFactor(entries)
    if oldSynergy ~= newSynergy then
        for i, power in ipairs(powers) do
            powers[i] = power * newSynergy / oldSynergy
        end
        originals = nil
    end
    return makeProduct(entries, powers, originals)
end

return brewing
