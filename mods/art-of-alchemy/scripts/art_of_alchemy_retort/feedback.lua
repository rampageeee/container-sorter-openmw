local core = require('openmw.core')
local types = require('openmw.types')
local util = require('openmw.util')
local vfs = require('openmw.vfs')
local world = require('openmw.world')

local feedback = {}
local fireId = 'light_fire'
local retortFireOffset = util.vector3(0, 0, -4)
local effectOffset = util.vector3(0, 0, 12)
local cueDistanceSquared = 768 * 768

function feedback.light(retort, kind)
    if kind == 'alembic' then
        return nil
    end
    local record = types.Light.records[fireId]
    if not record or record.model == '' or not vfs.fileExists(record.model) then
        return nil
    end
    local fire = world.createObject(fireId)
    local isRetort = kind == 'retort'
    local position = isRetort and retort.position + retortFireOffset or retort.position
    fire:teleport(retort.cell, position, { rotation = retort.rotation })
    fire:setScale(isRetort and 0.3 or 0.5)
    return fire
end

function feedback.playSound(id, source, volume)
    if id and core.sound.records[id] then
        core.sound.playSound3d(id, source, { volume = volume })
    end
end

local function retortIsNearby(retort)
    local player = world.players[1]
    if not player or not player.cell or not retort:isValid() or not retort.enabled
        or not retort.cell or retort.cell.id ~= player.cell.id then
        return false
    end
    local distance = retort.position - player.position
    return distance:dot(distance) <= cueDistanceSquared
end

local function potionEffect(product, retort)
    local effects = product.effects
    local record = product.standardId and types.Potion.records[product.standardId]
    if record then
        effects = record.effects
    end

    local effect = core.magic.effects.records[effects[1].id]
    if not effect then
        return
    end
    for _, id in ipairs({ effect.castStatic or '', effect.hitStatic or '' }) do
        local static = id ~= '' and types.Static.records[id]
        if static and static.model ~= '' and vfs.fileExists(static.model) then
            world.vfx.spawn(static.model, retort.position + effectOffset, {
                scale = 0.5,
                useAmbientLight = false,
                particleTextureOverride = effect.particle or '',
            })
            break
        end
    end
    return effect.castSound
end

function feedback.finish(job)
    if job.fire then
        if job.fire:isValid() then
            local sound = types.Light.record(job.fire).sound
            if sound and sound ~= '' then
                core.sound.stopSound3d(sound, job.fire)
            end
            job.fire:remove()
        end
        job.fire = nil
    end
    if job.powderId or not retortIsNearby(job.retort) then
        return
    end
    if job.product then
        local castSound = potionEffect(job.product, job.retort)
        local sound = castSound and core.sound.records[castSound] and castSound or 'potion success'
        feedback.playSound(sound, job.retort, 0.65)
    else
        feedback.playSound('potion fail', job.retort, 0.65)
    end
end

return feedback
