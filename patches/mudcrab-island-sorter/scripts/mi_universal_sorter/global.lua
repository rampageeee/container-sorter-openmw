local types = require('openmw.types')
local I = require('openmw.interfaces')
local world = require('openmw.world')

local TARGET = 'mi_chest_ingredients'
-- Change to false if you also want to store scripted ingredients automatically.
local SKIP_SCRIPTED = true
local excluded = {
    -- ['ingredient_record_id'] = true,
}

local function isTarget(chest)
    return chest and chest:isValid() and chest.type == types.Container
        and chest.recordId == TARGET and chest.enabled
end

local function isAccessible(chest)
    local trap = types.Lockable.getTrapSpell(chest)
    return not types.Lockable.isLocked(chest) and not (trap and trap ~= '')
end

I.Activation.addHandlerForType(types.Container, function(chest, actor)
    if actor.type ~= types.Player or not isTarget(chest) or not isAccessible(chest) then
        return
    end
    actor:sendEvent('MIUniversalSorterPrompt', {chest = chest})
    return false
end)

local function onChoice(data)
    local player = world.players[1]
    local chest = data.chest
    if not player or not player:isValid() or not isTarget(chest)
        or not isAccessible(chest) or player.cell ~= chest.cell then
        if player then player:sendEvent('MIUniversalSorterUnavailable', {}) end
        return
    end

    local skipped = 0
    local failed = 0
    if data.sort == true then
        -- Copy the list before modifying inventory. A stack is moved in one call.
        local snapshot = {}
        for _, item in ipairs(types.Actor.inventory(player):getAll(types.Ingredient)) do
            snapshot[#snapshot + 1] = item
        end
        for _, item in ipairs(snapshot) do
            if item:isValid() and item.parentContainer == player then
                local record = types.Ingredient.record(item)
                if excluded[item.recordId] or (SKIP_SCRIPTED and record.mwscript and record.mwscript ~= '') then
                    skipped = skipped + item.count
                else
                    local ok, err = pcall(function() item:moveInto(chest) end)
                    if not ok then
                        failed = failed + 1
                        print('[MI Universal Sorter] Transfer error: ' .. tostring(err))
                    end
                end
            end
        end
    end
    player:sendEvent('MIUniversalSorterOpen', {chest = chest, skipped = skipped, failed = failed})
end

return {eventHandlers = {MIUniversalSorterChoice = onChoice}}
