local animation = require('openmw.animation')
local async = require('openmw.async')
local camera = require('openmw.camera')
local core = require('openmw.core')
local input = require('openmw.input')
local interfaces = require('openmw.interfaces')
local nearby = require('openmw.nearby')
local self = require('openmw.self')
local types = require('openmw.types')
local ui = require('openmw.ui')
local util = require('openmw.util')
local fishing = require('scripts.ultimatefishing_openmw.fishing')

local actor = self.object
local prefix = fishing.eventPrefix
local probeGroup = 'ufrod'
local collision = nearby.COLLISION_TYPE
local solids = { collisionType = collision.World + collision.HeightMap + collision.Door, ignore = actor }
local center = util.vector2(0.5, 0.5)
local up = util.vector3(0, 0, 1)
local active, meter, nextToken = nil, nil, 0

local function rodEquipped()
    local rod = types.Actor.getEquipment(actor, types.Actor.EQUIPMENT_SLOT.CarriedRight)
    return rod and rod.recordId == fishing.rodId
end

local function readyToFish()
    return rodEquipped() and types.Actor.getStance(actor) == types.Actor.STANCE.Weapon
        and not types.Actor.isSwimming(actor) and not types.Actor.isDead(actor)
end

local function send(cast, kind, fields)
    local data = fields or {}
    data.player = actor
    data.token = cast.token
    core.sendGlobalEvent(prefix .. kind, data)
end

local function finish(message, fishId)
    if not active then return end
    local cast = active
    active = nil
    if meter then
        meter:destroy()
        meter = nil
    end
    if cast.reelSound then core.sound.stopSound3d('mer_fish_reel', self) end
    send(cast, 'Finish', { fishId = fishId })
    if message then ui.showMessage(message) end
end

local function depthAt(surface)
    local floor = nearby.castRay(surface - up * 2, surface - up * 5000, solids)
    return floor.hit and surface.z - floor.hitPos.z or 5000
end

local function arcPoint(cast, t)
    return cast.launch * (1 - t) + cast.surface * t + up * (4 + 320 * t * (1 - t))
end

local function aim(cell)
    local height = cell.waterLevel
    if not height then return nil end
    local eye = camera.getPosition()
    local direction = camera.viewportToWorldVector(center):normalize()
    if direction.z >= -0.001 or eye.z <= height then return nil end
    local distance = (height - eye.z) / direction.z
    local surface = eye + direction * distance
    local fromPlayer = surface - actor.position
    local horizontal = util.vector3(fromPlayer.x, fromPlayer.y, 0)
    if horizontal:length() < 100 or horizontal:length() > 1800 then return nil end
    if nearby.castRay(eye, surface + up * 3, solids).hit then return nil end
    local depth = depthAt(surface)
    if depth < 40 then return nil end

    local forward = horizontal:normalize()
    local launch = actor.position + up * 100 + forward * 30
    local cast = { surface = surface, launch = launch, depth = depth, forward = forward }
    local previous = arcPoint(cast, 0)
    for segment = 1, 5 do
        local position = arcPoint(cast, segment / 5)
        if nearby.castRay(previous, position, solids).hit then return nil end
        previous = position
    end
    return cast
end

local function updateMeter(fight)
    local tension = math.floor(fight.tension * 100 + 0.5)
    local progress = math.floor(fight.progress * 100 + 0.5)
    local label = string.format('Line tension %d%%     Fish tired %d%%', tension, progress)
    local warning = tension >= 80 or tension <= 20
    if not meter then
        meter = ui.create {
            type = ui.TYPE.Text,
            layer = 'HUD',
            props = {
                relativePosition = util.vector2(0.5, 0.76),
                anchor = util.vector2(0.5, 0.5),
                textShadow = true,
                textSize = 17,
            },
        }
    end
    local props = meter.layout.props
    if props.text == label then return end
    props.text = label
    props.textColor = warning and util.color.rgb(1, 0.5, 0.29) or util.color.rgb(0.92, 0.85, 0.67)
    meter:update()
end

local function nextBite(cast, now)
    cast.phase = 'waiting'
    cast.untilTime = now + 3.5 + math.random() * 4
end

local function playFight(cast, now, dt)
    local reeling = input.isKeyPressed(input.KEY.F6)
    if reeling ~= cast.reelSound then
        if reeling then
            core.sound.playSound3d('mer_fish_reel', self, { loop = true, volume = 0.6 })
        else
            core.sound.stopSound3d('mer_fish_reel', self)
        end
        cast.reelSound = reeling
    end
    local fight = cast.fight
    local result = fishing.stepFight(fight, dt, reeling)
    if result == 'snapped' then
        core.sound.playSound3d('mer_fish_snap', self)
        finish('The line snapped.')
    elseif result == 'escaped' then
        finish('The line went slack. The fish got away.')
    elseif result == 'caught' then
        finish(nil, cast.fish.id)
    else
        local side = util.vector3(cast.forward.y, -cast.forward.x, 0)
        local movement = side * (65 * math.sin(fight.elapsed * 2.1))
            + cast.forward * (30 * math.sin(fight.elapsed * 1.4))
        local surface = cast.surface + movement
        if depthAt(surface) < 40 or nearby.castRay(cast.surface + up * 4, surface + up * 4, solids).hit then
            surface = cast.surface
        end
        local splash
        if now >= cast.nextSplash then
            splash = 'mer_fish_splash_2'
            cast.nextSplash = now + 2 + math.random()
        end
        send(cast, 'Move', { position = surface + up * (3 + 4 * math.sin(fight.elapsed * 7)), sound = splash })
        updateMeter(fight)
    end
end

local function tick(cast)
    if active ~= cast then return end
    local cell = actor.cell
    if not cell or cell.id ~= cast.cellId or not readyToFish()
        or (actor.position - cast.playerStart):length() > 180 then
        finish('Fishing interrupted.')
        return
    end
    local now = core.getSimulationTime()
    local dt = now - cast.lastTick
    cast.lastTick = now
    local interval = 0.12
    if cast.phase == 'flying' then
        local t = math.min(1, (now - cast.started) / cast.flightTime)
        if t >= 1 then
            send(cast, 'Move', { position = arcPoint(cast, 1), sound = 'mer_fish_splash_1' })
            nextBite(cast, now)
        else
            send(cast, 'Move', { position = arcPoint(cast, t) })
            interval = 0.04
        end
    elseif cast.phase == 'waiting' and now >= cast.untilTime then
        cast.phase = 'biting'
        cast.untilTime = now + 1.25
        send(cast, 'Move', { position = cast.surface - up * 8, sound = 'mer_fish_splash_2' })
        ui.showMessage('A bite! Press F6 to set the hook.')
    elseif cast.phase == 'biting' and now >= cast.untilTime then
        send(cast, 'Move', { position = arcPoint(cast, 1) })
        nextBite(cast, now)
    elseif cast.phase == 'fighting' then
        playFight(cast, now, dt)
        interval = 0.06
    end
    if active == cast then
        async:newUnsavableSimulationTimer(interval, function() tick(cast) end)
    end
end

local function startCast()
    if not rodEquipped() then return end
    if not readyToFish() then
        ui.showMessage('Draw the fishing pole and stand out of the water.')
        return
    end
    local cell = actor.cell
    local cast = cell and aim(cell)
    if not cast then
        ui.showMessage('Aim at clear, deeper water within casting range.')
        return
    end
    nextToken = nextToken + 1
    local now = core.getSimulationTime()
    cast.token = nextToken
    cast.cellId = cell.id
    cast.playerStart = actor.position
    cast.started, cast.lastTick = now, now
    cast.phase = 'flying'
    cast.flightTime = 0.35 + math.min(0.5, (cast.surface - cast.launch):length() / 3000)
    active = cast
    send(cast, 'Start', { cellId = cast.cellId, position = arcPoint(cast, 0) })
    core.sound.playSound3d('mer_fish_cast', self)
    async:newUnsavableSimulationTimer(0.04, function() tick(cast) end)
end

local function onFishingKey(key)
    if core.isWorldPaused() or interfaces.UI.getMode() then return end
    if key.code == input.KEY.F7 and active then
        finish('You reeled in the lure.')
    elseif key.code == input.KEY.F6 and not key.withCtrl and not key.withAlt and not key.withSuper then
        if key.withShift then
            if rodEquipped() and not active then
                if animation.hasGroup(actor, probeGroup) then
                    animation.playQueued(self, probeGroup, { loops = 0 })
                    ui.showMessage('Playing the third-person fishing pose.')
                else
                    ui.showMessage('Fishing pose unavailable in this view or animation setup.')
                end
            end
        elseif not active then
            startCast()
        elseif active.phase == 'biting' then
            local now = core.getSimulationTime()
            local cell = actor.cell
            if now >= active.untilTime or not cell or cell.id ~= active.cellId or not readyToFish() then return end
            active.fish = fishing.chooseCatch(active.depth, core.getGameTime() / 3600 % 24,
                cell.isExterior or cell.isQuasiExterior)
            active.phase = 'fighting'
            active.fight = fishing.startFight(active.fish)
            active.lastTick = now
            active.nextSplash = now + 1
            active.reelSound = false
            ui.showMessage('Hooked! Hold F6 to reel. Release it to ease the tension.')
            updateMeter(active.fight)
        elseif active.phase == 'waiting' then
            finish('You reeled in the lure.')
        end
    end
end

if interfaces.Combat and interfaces.Combat.addOnHitHandler then
    interfaces.Combat.addOnHitHandler(function(attack)
        if active and attack.successful then finish('Fishing interrupted.') end
    end)
end

return {
    engineHandlers = {
        onKeyPress = onFishingKey,
        onTeleported = function() finish() end,
    },
    eventHandlers = {
        UiModeChanged = function(data)
            if data.newMode then finish() end
        end,
        [prefix .. 'Rejected'] = function(token)
            if active and active.token == token then finish('Could not start this cast.') end
        end,
        [prefix .. 'Caught'] = function(name) ui.showMessage('Caught ' .. name .. '.') end,
    },
}
