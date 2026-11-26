local async = require('openmw.async')
local core = require('openmw.core')
local types = require('openmw.types')
local world = require('openmw.world')
local fishing = require('scripts.ultimatefishing_openmw.fishing')
local prefix = fishing.eventPrefix
local active

local function removeLure(lure)
    if lure and lure:isValid() then lure:remove() end
end

local function clearCast()
    if active then
        removeLure(active.lure)
        active = nil
    end
end

local function isCurrent(data)
    return active and active.player == data.player and active.token == data.token
end

local function start(data)
    if isCurrent(data) then return end
    clearCast()
    local player = data.player
    if not player:isValid() or player ~= world.players[1] then return end
    local cell = player.cell
    local rod = types.Actor.getEquipment(player, types.Actor.EQUIPMENT_SLOT.CarriedRight)
    if not rod or rod.recordId ~= fishing.rodId or not cell or cell.id ~= data.cellId then
        player:sendEvent(prefix .. 'Rejected', data.token)
        return
    end

    local ok, lure = pcall(world.createObject, fishing.lureId)
    if not ok then
        print('[Ultimate Fishing OpenMW] Could not create lure: ' .. tostring(lure))
        player:sendEvent(prefix .. 'Rejected', data.token)
        return
    end
    active = { player = player, token = data.token, cell = cell, lure = lure }
    lure:teleport(cell, data.position)
end

local function move(data)
    if isCurrent(data) and active.lure:isValid() then
        active.lure:teleport(active.cell, data.position)
        if data.sound then core.sound.playSound3d(data.sound, active.lure) end
    end
end

local function finish(data)
    if not isCurrent(data) then return end
    clearCast()
    local fish = fishing.catches[data.fishId]
    local player = data.player
    if fish and player:isValid() and not types.Actor.isDead(player) then
        world.createObject(fish.id):moveInto(types.Actor.inventory(player))
        player:sendEvent(prefix .. 'Caught', fish.name)
    end
end

return {
    engineHandlers = {
        onSave = function()
            return active and { lure = active.lure }
        end,
        onLoad = function(data)
            active = nil
            if data and data.lure then
                -- World references are populated as the saved cells finish loading.
                async:newUnsavableSimulationTimer(0, function() removeLure(data.lure) end)
            end
        end,
    },
    eventHandlers = {
        [prefix .. 'Start'] = start,
        [prefix .. 'Move'] = move,
        [prefix .. 'Finish'] = finish,
    },
}
