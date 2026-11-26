local core = require('openmw.core')
local types = require('openmw.types')
local brewing = require('scripts.art_of_alchemy_retort.brewing')

local discovery = {}

function discovery.threshold(actor)
    local skill = types.NPC.stats.skills.alchemy(actor).modified
    local perEffect = tonumber(core.getGMST('fWortChanceValue')) or 15
    return math.max(0, math.min(4, math.floor(skill / math.max(1, perEffect))))
end

-- OpenMW's ingredient slots are numbered from one in the record table, even when a slot is empty.
function discovery.visible(known, record, effect, threshold)
    return (effect.index or 0) + 1 <= threshold
        or (known[record.id] and known[record.id][brewing.effectKey(effect)]) == true
end

function discovery.learn(known, record, effect)
    local key = brewing.effectKey(effect)
    local effects = known[record.id] or {}
    known[record.id] = effects
    if effects[key] then return false end
    effects[key] = true
    return true
end

return discovery
