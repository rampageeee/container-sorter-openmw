local self   = require('openmw.self')
local core   = require('openmw.core')
local types  = require('openmw.types')
local nearby = require('openmw.nearby')
local util   = require('openmw.util')
local async  = require('openmw.async')

local shared          = require('scripts.npcschedule_shared')
local SAFE_KEYWORDS   = shared.SAFE_KEYWORDS
local SHOP_KEYWORDS   = shared.SHOP_KEYWORDS
local RECORD_ID_STRIP = shared.RECORD_ID_STRIP
local DEFAULTS        = shared.DEFAULTS
local BLACKLISTED_INTERIORS = shared.BLACKLISTED_INTERIORS
local EXEMPT_SHOP_CELLS = shared.EXEMPT_SHOP_CELLS
local TRIBUNAL_TEMPLE_CELLS = shared.TRIBUNAL_TEMPLE_CELLS
local IMPERIAL_SHRINE_CELLS = shared.IMPERIAL_SHRINE_CELLS

local DOOR_OVERRIDES = shared.DOOR_OVERRIDES
local NPC_HOME_CELLS = shared.NPC_HOME_CELLS
local NPC_DOOR_OVERRIDES = shared.NPC_DOOR_OVERRIDES
local NPC_OVERRIDE_PATH_TO_DOORS = shared.NPC_OVERRIDE_PATH_TO_DOORS

local I        = require('openmw.interfaces')
local AI       = I.AI
local Door     = types.Door
local Lockable = types.Lockable

local logEnabled = false

local function log(...)
    if logEnabled then print('[NPCSch N]', self.object.recordId, ...) end
end

-- states: nil, 'delaying', 'walking', 'disabled', 'inside', 'walkingOut', 'returning', 'waitSnap'
local state        = nil
local savedWander  = nil
local targetDoor   = nil
local targetDoorPos = nil
local arrivalDist  = 200
local isSafe       = false
local isShop       = false
local isTemple     = false
local homeCellName = nil
local scanRange    = 3000
local doorInsidePos = nil
local doorInsideRot = nil
local doorExitRot   = nil
local doorLockLevel = nil
local inDialogue    = false

-- multi-point override path to a door
local pathPoints = nil
local pathIndex  = nil

-- walkOutAndReturn data
local walkOutStartPos  = nil
local walkOutStartCell = nil
local walkOutStartRot  = nil
local walkOutWander    = nil

-- shop visit: one visit per activation cycle
local shopVisitDone = false
-- temple visit: independent daily flag
local templeVisitDone = false

-- stuck detection
local lastPos    = nil
local stuckTimer = 0
local STUCK_TIME = 5

local CHECK_RATE = 0.5
local checkCallback
local checkState
local lastGameTime = nil
local finishDelay
local walkOutWaiting = nil

-- safe place reservation
local pendingReservation = nil
local reservationRequestId = 0
local reservationCellName = nil
local triedSafeCells = {}
local triedDoors = {}

-- save/load helpers for vector and rotation
local function vec3T(v) return v and { x = v.x, y = v.y, z = v.z } or nil end
local function tVec3(t) return t and util.vector3(t.x, t.y, t.z) or nil end
local function rotT(r)
    if not r then return nil end
    return r:getYaw()
end
local function tRot(y) return y and util.transform.rotateZ(y) or nil end

-- save and restore for Wander
local function saveWander()
    if savedWander then return end
    local pkg = AI.getActivePackage()
    if pkg and pkg.type == 'Wander' then
        savedWander = {
            type     = 'Wander',
            distance = pkg.distance,
            duration = pkg.duration * 3600,
            idle     = pkg.idle,
            isRepeat = pkg.isRepeat,
        }
        log('Saved wander d:', pkg.distance)
    end
end



local function restoreOriginalWander()
    if savedWander then
        AI.removePackages('Wander')
        AI.removePackages('Travel')
        AI.startPackage(savedWander)
        log('Restored original wander')
    end
    savedWander = nil
end

local function syncChecks()
    local needsCheck = walkOutWaiting or state == 'walking' or state == 'returning'
        or state == 'walkingOut' or state == 'delaying'
    if not needsCheck then
        checkCallback = nil
        return
    end
    if checkCallback or not self:isActive() then return end

    local lastCheckTime = core.getSimulationTime()
    local function callback()
        if checkCallback ~= callback then return end
        local now = core.getSimulationTime()
        local elapsed = now - lastCheckTime
        lastCheckTime = now
        -- Reuse this callback until the actor changes to a state that needs no checks.
        async:newUnsavableSimulationTimer(CHECK_RATE, callback)
        checkState(elapsed)
    end
    checkCallback = callback
    async:newUnsavableSimulationTimer(CHECK_RATE, callback)
end

local function setState(newState)
    if newState == 'delaying' and state ~= 'delaying' then
        lastGameTime = core.getGameTime()
    elseif newState ~= 'delaying' then
        finishDelay = nil
        lastGameTime = nil
    end
    state = newState
    syncChecks()
end

-- safe cell check
local function isSafeCell(name)
    if not name then return false end
    local lo = name:lower()
    for _, kw in ipairs(SAFE_KEYWORDS) do
        if lo:find(kw, 1, true) then return true end
    end
    return false
end

-- shop cell check
local function isShopCell(name)
    if not name then return false end
    local lo = name:lower()
    if EXEMPT_SHOP_CELLS[lo] then return false end
    for _, kw in ipairs(SHOP_KEYWORDS) do
        if lo:find(kw, 1, true) then return true end
    end
    return false
end

-- find shop door candidates within range (random order, not sorted)
local function findShopDoors(range)
    local candidates = {}
    for _, d in ipairs(nearby.doors) do
        if d:isValid() and Door.isTeleport(d) and not Lockable.isLocked(d) then
            local dc = Door.destCell(d)
            if dc and not dc.isExterior then
                local cn = dc.name or ''
                local lo = cn:lower()
                if not BLACKLISTED_INTERIORS[lo] and isShopCell(cn) then
                    local dist = (d.position - self.object.position):length()
                    if dist <= range then
                        table.insert(candidates, { door = d, dist = dist, cellName = cn })
                    end
                end
            end
        end
    end
    return candidates
end

-- find temple door candidates within range for given cult
local function findTempleDoors(range, cult)
    local whitelist = (cult == "tribunal") and TRIBUNAL_TEMPLE_CELLS
                                             or IMPERIAL_SHRINE_CELLS
    local candidates = {}
    for _, d in ipairs(nearby.doors) do
        if d:isValid() and Door.isTeleport(d) and not Lockable.isLocked(d) then
            local dc = Door.destCell(d)
            if dc and not dc.isExterior then
                local cn = dc.name or ''
                local lo = cn:lower()
                if whitelist[lo] then
                    local dist = (d.position - self.object.position):length()
                    if dist <= range then
                        table.insert(candidates, { door = d, dist = dist, cellName = cn })
                    end
                end
            end
        end
    end
    return candidates
end

-- cache locals
local _nameTokensCache = nil
local _npcNameLowerCache = nil
local _npcNameTokensCache = nil
local _recordIdLowerCache = nil


-- door search
local function getNameTokens()
    if _nameTokensCache then return _nameTokensCache end
    local recordId = self.object.recordId
    local tokens = {}
    for s in recordId:gmatch('[^_%s]+') do
        local lo = s:lower()
        if not RECORD_ID_STRIP[lo] then
            tokens[#tokens + 1] = lo
        end
    end
    _nameTokensCache = tokens
    return tokens
end

local function getNpcNameLower()
    if _npcNameLowerCache then return _npcNameLowerCache end
    local rec = types.NPC.record(self.object)
    local name = rec and rec.name or ''
    _npcNameLowerCache = name:lower()
    return _npcNameLowerCache
end

-- split display name into parts (first/last/etc), filtered for length and stripped tokens
local function getNpcNameTokens()
    if _npcNameTokensCache then return _npcNameTokensCache end
    local tokens = {}
    local nameLo = getNpcNameLower()
    for s in nameLo:gmatch('(%S+)') do
        if #s >= 3 and not RECORD_ID_STRIP[s] then
            tokens[#tokens + 1] = s
        end
    end
    _npcNameTokensCache = tokens
    return tokens
end

local function getRecordIdLower()
    if _recordIdLowerCache then return _recordIdLowerCache end
    _recordIdLowerCache = self.object.recordId:lower()
    return _recordIdLowerCache
end

-- cell name -> set of whole words
local _cellTokenCache = {}
local function getCellTokens(lo)
    local cached = _cellTokenCache[lo]
    if cached then return cached end
    local set = {}
    for w in lo:gmatch('[^%s,%.%(%)%-]+') do
        w = w:gsub("'s$", ''):gsub("'$", '')
        if #w >= 3 then set[w] = true end
    end
    _cellTokenCache[lo] = set
    return set
end

-- match cell name against NPC on WHOLE WORDS
local function cellMatchesNpc(cellName)
    local tokens = getCellTokens(cellName:lower())

    -- display name parts (first name, last name, etc)
    for _, t in ipairs(getNpcNameTokens()) do
        if tokens[t] then return true end
    end

    -- recordId tokens
    for _, t in ipairs(getNameTokens()) do
        if #t >= 3 and tokens[t] then return true end
    end

    return false
end

-- find personal home door
local function findHomeDoor(range)
    -- forced home: exact cell name, or false to bar a personal home entirely
    local forced = NPC_HOME_CELLS[getRecordIdLower()]
    if forced == false then return nil end
    if not forced and getNpcNameLower() == '' then return nil end

    local best, bestD = nil, range + 1
    for _, d in ipairs(nearby.doors) do
        if d:isValid() and Door.isTeleport(d) then
            local dc = Door.destCell(d)
            if dc and not dc.isExterior then
                local cn = dc.name or ''
                local lo = cn:lower()
                if not BLACKLISTED_INTERIORS[lo] then
                    local matched
                    if forced then
                        matched = (lo == forced)
                    else
                        matched = cellMatchesNpc(cn)
                    end
                    if matched then
                        local dist = (d.position - self.object.position):length()
                        if dist < bestD then best, bestD = d, dist end
                    end
                end
            end
        end
    end

    -- an override is a match rule, not a teleport: the door still has to be in range
    if forced and not best then
        log('Forced home', forced, 'has no door within', range)
    end
    return best
end

-- find safe place door candidates
-- the problem is sometimes places have doors that are unavailable (like doors on the roof)
-- instance id changes, so no way to filter them
-- bcom eight plates is an example
local function findAvailableSafeDoors(range, excludeTried)
    local candidates = {}
    
    for _, d in ipairs(nearby.doors) do
        if d:isValid() and Door.isTeleport(d) and not Lockable.isLocked(d) then
            local dc = Door.destCell(d)
            if dc and not dc.isExterior then
                local cn = dc.name or ''
                local lo = cn:lower()
                
                if not BLACKLISTED_INTERIORS[lo] and isSafeCell(cn) then
                    if excludeTried and triedSafeCells[lo] then
                        goto continue
                    end
                    
                    local dist = (d.position - self.object.position):length()
                    if dist <= range then
                        table.insert(candidates, { door = d, dist = dist, cellName = cn })
                    end
                end
            end
        end
        ::continue::
    end
    
    table.sort(candidates, function(a, b) return a.dist < b.dist end)
    return candidates
end

-- resolve door inside position/rotation from the door object (while NPC is still outside)
local function resolveDoorInside(door)
    if not door or not door:isValid() then return end
    local pos = Door.destPosition(door)
    local rot = Door.destRotation(door)
    if pos then doorInsidePos = pos end
    if rot then doorInsideRot = rot end
    doorExitRot = door.rotation
    if Lockable.isLocked(door) then
        doorLockLevel = Lockable.getLockLevel(door)
    else
        doorLockLevel = nil
    end
end

-- check for door position override
-- forShop=true picks random entry, forShop=false picks nearest to NPC
-- NPC_DOOR_OVERRIDES is checked first, if no per-NPC entry exists, falls back to the cell-wide DOOR_OVERRIDES table
local function getDoorOverride(cellName, forShop)
    if not cellName then return nil end
    local cellKey = cellName:lower()
    local entries
    local npcTbl = NPC_DOOR_OVERRIDES[self.object.recordId:lower()]
    if npcTbl then entries = npcTbl[cellKey] end
    if not entries or #entries == 0 then
        entries = DOOR_OVERRIDES[cellKey]
    end
    if not entries or #entries == 0 then return nil end
    if #entries == 1 then
        local e = entries[1]
        return util.vector3(e.x, e.y, e.z)
    end
    if forShop then
        local e = entries[math.random(#entries)]
        return util.vector3(e.x, e.y, e.z)
    end
    -- nearest to NPC
    local myPos = self.object.position
    local best, bestD = nil, math.huge
    for _, e in ipairs(entries) do
        local v = util.vector3(e.x, e.y, e.z)
        local d = (v - myPos):length()
        if d < bestD then best, bestD = v, d end
    end
    return best
end

-- check for a multi-point path override for this NPC + cell
local function getPathOverride(cellName)
    pathPoints = nil
    pathIndex  = nil
    if not cellName then return nil end
    local npcTbl = NPC_OVERRIDE_PATH_TO_DOORS[self.object.recordId:lower()]
    if not npcTbl then return nil end
    local entries = npcTbl[cellName:lower()]
    if not entries or #entries == 0 then return nil end

    local pts = {}
    for _, e in ipairs(entries) do
        pts[#pts + 1] = util.vector3(e.x, e.y, e.z)
    end
    pathPoints = pts
    pathIndex  = 1
    return pts[#pts]  -- door is the last point
end

local function registerWith(st)
    core.sendGlobalEvent('NPCSch_Register', {
        actor         = self.object,
        startPos      = self.startingPosition,
        startCell     = self.cell and (self.cell.name or '') or '',
        startRot      = self.startingRotation,
        savedWander   = savedWander,
        state         = st,
        isSafe        = isSafe,
        isShop        = isShop,
        isTemple      = isTemple,
        homeCellName  = homeCellName,
        doorExitPos   = targetDoorPos,
        doorExitRot   = doorExitRot,
        doorInsidePos = doorInsidePos,
        doorInsideRot = doorInsideRot,
        doorLockLevel = doorLockLevel,
        doorObj       = targetDoor,
    })
end

-- NPC arrived at door: request disable from global (no teleport into interior)
local function disableAtDoor(animate)
    AI.removePackages('Travel')
    AI.removePackages('Wander')
    setState('disabled')
    core.sendGlobalEvent('NPCSch_DisabledAtDoor', {
        actor   = self.object,
        animate = animate == true,
    })
    if isSafe and reservationCellName then
        core.sendGlobalEvent('NPCSch_ConfirmRegistration', {
            npcId = self.object.id,
            cellName = reservationCellName,
        })
        reservationCellName = nil
    end
    log('Requesting disable at door')
end

local function resetStuck()
    lastPos = self.object.position
    stuckTimer = 0
end

local function onDialogueStart()
    inDialogue = true
end

local function onDialogueEnd()
    inDialogue = false
    resetStuck()
end

local function isStuck(dt)

    if inDialogue then
        resetStuck()
        return false
    end

    if not lastPos then resetStuck() return false end
    if (self.object.position - lastPos):length() > 30 then
        resetStuck()
        return false
    end
    stuckTimer = stuckTimer + dt
    return stuckTimer >= STUCK_TIME
end

local function findEscape()
    local pos = self.object.position
    local fwd = self.object.rotation:apply(util.vector3(0, 1, 0))
    local rgt = self.object.rotation:apply(util.vector3(1, 0, 0))
    for _, dir in ipairs({ fwd, (fwd+rgt):normalize(), (fwd-rgt):normalize(), rgt, -rgt, -fwd }) do
        local cand = pos + dir * 300
        local wall = nearby.castRay(
            pos + util.vector3(0,0,60), cand + util.vector3(0,0,60),
            { collisionType = nearby.COLLISION_TYPE.World, ignore = { self.object } }
        )
        if not wall.hit then
            local ground = nearby.castRay(
                cand + util.vector3(0,0,50), cand - util.vector3(0,0,200),
                { collisionType = nearby.COLLISION_TYPE.World }
            )
            if ground.hit and math.abs(ground.hitPos.z - pos.z) < 120 then
                local ox = (math.random() - 0.5) * 240
                local oy = (math.random() - 0.5) * 240
                return ground.hitPos + util.vector3(ox, oy, 10)
            end
        end
    end
    return nil
end

local function travel(destPos)
    AI.startPackage({ type = 'Travel', destPosition = destPos, isRepeat = false, cancelOther = false })
end

local function startWalkToDoor()
    if not targetDoorPos then return end
    AI.removePackages('Wander')
    -- if a multi-point path is active, walk to the current waypoint instead of straight to the door
    local walkTo = targetDoorPos
    if pathPoints and pathIndex then
        walkTo = pathPoints[pathIndex]
    end
    travel(walkTo)
    setState('walking')
    core.sendGlobalEvent('NPCSch_UpdateState', {
        actorId = self.object.id, state = 'walking',
    })
    resetStuck()
end

local function delayWalk(delay)
    setState('delaying')
    registerWith('delaying')
    local function callback()
        if finishDelay ~= callback then return end
        local pkg = AI.getActivePackage()
        if pkg and pkg.type == 'Wander' then
            startWalkToDoor()
            return
        end

        log('Delay ended but AI package changed, aborting')
        if isSafe and reservationCellName then
            core.sendGlobalEvent('NPCSch_ReleaseReservation', {
                npcId = self.object.id,
                cellName = reservationCellName,
            })
        end
        reservationCellName = nil
        savedWander = nil
        isSafe = false
        targetDoor = nil
        targetDoorPos = nil
        homeCellName = nil
        doorInsidePos = nil
        doorInsideRot = nil
        doorExitRot = nil
        doorLockLevel = nil
        triedSafeCells = {}
        pendingReservation = nil
        pathPoints = nil
        pathIndex = nil
        setState(nil)
        core.sendGlobalEvent('NPCSch_Returned', { actorId = self.object.id })
    end
    finishDelay = callback
    async:newUnsavableSimulationTimer(delay, callback)
end

local escapeAttempted = false


local function tryNextSafePlace(mode, delay, allCandidates, startIndex)
    local index = startIndex or 1
    
    while index <= #allCandidates do
        local candidate = allCandidates[index]
        local cellNameLower = candidate.cellName:lower()
        
        if not triedSafeCells[cellNameLower] then
            log(string.format('Trying safe place: %s. Delay: %.2f sec. (%d of %d)', candidate.cellName, delay, index, #allCandidates))

            reservationRequestId = reservationRequestId + 1
            pendingReservation = {
                door = candidate.door,
                cellName = candidate.cellName,
                mode = mode,
                delay = delay,
                candidates = allCandidates,
                nextIndex = index + 1,
            }
            
            core.sendGlobalEvent('NPCSch_RequestSafeReservation', {
                npcId = self.object.id,
                cellName = candidate.cellName,
                actor = self.object,
                requestId = reservationRequestId,
            })
            return true
        end
        
        index = index + 1
    end
    
    log('All safe doors exhausted, giving up')
    core.sendGlobalEvent('NPCSch_NoDoor', { actorId = self.object.id })
    setState(nil)
    return false
end

local function handleStuck()
    -- when a path override is active, resume toward the current waypoint rather than the final door
    local resumeBase = targetDoorPos
    if pathPoints and pathIndex then
        resumeBase = pathPoints[pathIndex]
    end

    if not escapeAttempted and targetDoor and targetDoor:isValid() then
        local esc = findEscape()
        if esc then
            log('Stuck, escape path found')
            escapeAttempted = true
            AI.removePackages('Travel')
            AI.startPackage({ type = 'Travel', destPosition = esc, isRepeat = false, cancelOther = false })
            resetStuck()
            async:newUnsavableSimulationTimer(3, function()
                if state ~= 'walking' or not escapeAttempted then return end
                AI.removePackages('Travel')
                if resumeBase then
                    local angle = math.random() * math.pi * 2
                    local distance = math.random(100, 200)
                    
                    local deltaX = math.cos(angle) * distance
                    local deltaY = math.sin(angle) * distance

                    local newDestPos = util.vector3(
                        resumeBase.x + deltaX,
                        resumeBase.y + deltaY,
                        resumeBase.z
                    )
                    AI.startPackage({ type = 'Travel', destPosition = newDestPos, isRepeat = false, cancelOther = false })
                    resetStuck()
                    log('Resumed walking after escape')
                end
            end)
            return
        end
    end

    -- shop or temple: raycast escape, then retry another door of the same destination, then LOS teleport
    if isShop or isTemple then
        if targetDoor and targetDoor:isValid() then
            triedDoors[targetDoor.id] = true
        end

        if homeCellName then
            log('Visit stuck, searching for another door to:', homeCellName)
            for _, d in ipairs(nearby.doors) do
                if d:isValid() and Door.isTeleport(d) and not Lockable.isLocked(d) and not triedDoors[d.id] then
                    local dc = Door.destCell(d)
                    if dc and dc.name and dc.name:lower() == homeCellName:lower() then
                        log('Found alternative door to same destination, switching target')
                        targetDoor = d
                        targetDoorPos = d.position
                        resolveDoorInside(d)
                        local ovr = getDoorOverride(homeCellName, true)
                        if ovr then
                            targetDoorPos = ovr
                            log('Door override re-applied for visit:', homeCellName)
                        end
                        escapeAttempted = false
                        AI.removePackages('Travel')
                        AI.startPackage({ type = 'Travel', destPosition = targetDoorPos, isRepeat = false, cancelOther = false })
                        resetStuck()
                        core.sendGlobalEvent('NPCSch_UpdateState', {
                            actorId = self.object.id, state = 'walking',
                            doorInsidePos = doorInsidePos,
                            doorInsideRot = doorInsideRot,
                        })
                        return
                    end
                end
            end
        end

        -- no more doors, then LOS teleport
        log('Visit stuck, requesting LOS for disable')
        escapeAttempted = false
        core.sendGlobalEvent('NPCSch_RequestLOS', {
            actor = self.object, door = targetDoor, safe = false,
        })
        resetStuck()
        return
    end

    -- try another door of the same safe place
    if targetDoor and targetDoor:isValid() then
        triedDoors[targetDoor.id] = true -- mark this specific door instance as failed
    end

    if reservationCellName then
        log('Stuck again, searching for another door to the same safe place:', reservationCellName)
        
        for _, d in ipairs(nearby.doors) do
            if d:isValid() and Door.isTeleport(d) and not triedDoors[d.id] then
                local dc = Door.destCell(d)
                if dc and dc.name:lower() == reservationCellName:lower() then
                    log('Found alternative door to same safe place, switching target')
                    
                    targetDoor = d
                    targetDoorPos = d.position
                    resolveDoorInside(d)
                    local ovr = getDoorOverride(reservationCellName, false)
                    if ovr then
                        targetDoorPos = ovr
                        log('Door override re-applied for safe:', reservationCellName)
                    end
                    escapeAttempted = false
                    
                    AI.removePackages('Travel')
                    AI.startPackage({ type = 'Travel', destPosition = targetDoorPos, isRepeat = false, cancelOther = false })
                    resetStuck()
                    core.sendGlobalEvent('NPCSch_UpdateState', {
                        actorId = self.object.id, state = 'walking',
                        doorInsidePos = doorInsidePos,
                        doorInsideRot = doorInsideRot,
                    })
                    return
                end
            end
        end
    end

    -- request a teleportation
    log('Stuck, no more doors for this safe place. Requesting LOS for disable')
    escapeAttempted = false
    triedDoors = {} -- clear for next time
    
    if isSafe and reservationCellName then
        core.sendGlobalEvent('NPCSch_ReleaseReservation', {
            npcId = self.object.id,
            cellName = reservationCellName,
        })
        reservationCellName = nil
    end

    core.sendGlobalEvent('NPCSch_RequestLOS', {
        actor = self.object, door = targetDoor, safe = isSafe,
    })
    resetStuck()
end


--==============================================================================================
-- Daily Chores: a chore playing inside (sleeping, sweeping) ends at its nearest exit before the morning walk-out takes the actor, CHORE_WAIT seconds at most, then it is taken anyway

local CHORE_WAIT = 30
local onNPCSch_WalkOutAndReturn

local function choreBusy()
    local D = I.PiousNPCs
    return D ~= nil and D.isBusy ~= nil and D.isBusy() == true
end

-- true: the walk-out runs once the chore has let go
local function waitForChore(data)
    if not choreBusy() then return false end
    local D = I.PiousNPCs
    if not (D.letGo and D.letGo()) then return false end
    walkOutWaiting = { data = data, since = core.getSimulationTime(), asked = true }
    syncChecks()
    log('Waiting for the chore to end before walking out')
    return true
end

-- the global moved it on without the walk-out (the player left, a reset): the chore stops on the spot
local function dropWalkOut()
    if not walkOutWaiting then return end
    walkOutWaiting = nil
    syncChecks()
    if choreBusy() then I.PiousNPCs.yield() end
end

local function checkWalkOut()
    local w = walkOutWaiting
    local D = I.PiousNPCs
    local busy = choreBusy()
    -- loaded while waiting: the chore started over and has to be asked again
    if busy and not w.asked then
        w.asked = true
        busy = D.letGo ~= nil and D.letGo() and choreBusy()
    end
    if busy and core.getSimulationTime() - w.since < CHORE_WAIT then return end
    walkOutWaiting = nil
    if choreBusy() then
        log('The chore is taking too long, walking out anyway')
        D.yield()
    end
    onNPCSch_WalkOutAndReturn(w.data)
    syncChecks()
end

checkState = function(elapsed)
    if walkOutWaiting then
        checkWalkOut()
        return
    end

    if state == 'walking' then
        if not targetDoorPos then
            setState(nil)
            return
        end
        if isStuck(elapsed) then handleStuck() return end

        -- multi-point override path: advance waypoint-by-waypoint
        if pathPoints and pathIndex then
            local wp = pathPoints[pathIndex]
            local dist = (self.object.position - wp):length()
            if dist <= arrivalDist then
                if pathIndex >= #pathPoints then
                    -- reached the final point (the door): disable
                    disableAtDoor(true)
                else
                    -- reached an intermediate waypoint: walk to the next
                    pathIndex = pathIndex + 1
                    AI.removePackages('Travel')
                    travel(pathPoints[pathIndex])
                    resetStuck()
                    log('Reached waypoint, advancing to', pathIndex, 'of', #pathPoints)
                end
            end
            return
        end

        local dist = (self.object.position - targetDoorPos):length()
        if dist <= arrivalDist then
            -- arrived at door: disable
            disableAtDoor(true)
        end
        return
    end

    if state == 'returning' then
        if isStuck(elapsed) then
            -- first stuck: try raycast escape once
            if not escapeAttempted then
                local esc = findEscape()
                if esc then
                    log('Returning stuck, escape path found')
                    escapeAttempted = true
                    AI.removePackages('Travel')
                    AI.startPackage({
                        type = 'Travel', destPosition = esc,
                        isRepeat = false, cancelOther = false,
                    })
                    resetStuck()
                    async:newUnsavableSimulationTimer(3, function()
                        if state ~= 'returning' or not escapeAttempted then return end
                        AI.removePackages('Travel')
                        AI.startPackage({
                            type = 'Travel', destPosition = self.startingPosition,
                            isRepeat = false, cancelOther = false,
                        })
                        resetStuck()
                        log('Resumed returning after escape')
                    end)
                    return
                end
            end

            -- second stuck (or no escape found), fall back to LOS teleport
            log('Returning stuck, requesting LOS for snap')
            escapeAttempted = false
            AI.removePackages('Travel')
            setState('waitSnap')
            core.sendGlobalEvent('NPCSch_RequestLOS', {
                actor = self.object, door = nil, safe = false,
            })
            return
        end

        local dist = (self.object.position - self.startingPosition):length()
        if dist <= 40 then
            AI.removePackages('Travel')
            setState('waitSnap')
            escapeAttempted = false
            restoreOriginalWander()
            core.sendGlobalEvent('NPCSch_RequestLOS', {
                actor = self.object, door = nil, safe = false,
            })
        end
        return
    end

    if state == 'walkingOut' then
        if not targetDoorPos then setState(nil) return end
        if isStuck(elapsed) then
            -- stuck walking to door inside, just teleport out
            AI.removePackages('Travel')
            core.sendGlobalEvent('NPCSch_PlayDoorSound', { door = targetDoor })
            core.sendGlobalEvent('NPCSch_Teleport', {
                actor = self.object,
                cell = walkOutStartCell or '',
                pos = walkOutStartPos,
                rotation = walkOutStartRot,
            })
            savedWander = walkOutWander
            restoreOriginalWander()
            core.sendGlobalEvent('NPCSch_Returned', { actorId = self.object.id })
            setState(nil)
            return
        end
        local dist = (self.object.position - targetDoorPos):length()
        if dist <= arrivalDist then
            AI.removePackages('Travel')
            core.sendGlobalEvent('NPCSch_ExitDoorReached', {
                actor       = self.object,
                cell        = walkOutStartCell or '',
                pos         = walkOutStartPos,
                rotation    = walkOutStartRot,
                savedWander = walkOutWander,
                door        = targetDoor
            })
            -- change state to waitSnap so the NPC stands still while the global script handles the animation delay
            setState('waitSnap') 
            targetDoor = nil
            targetDoorPos = nil
            log('Reached interior door, requesting animated exit')
        end
        return
    end

    if state == 'delaying' then
        local currentGameTime = core.getGameTime()
        local skippedTime = lastGameTime and currentGameTime - lastGameTime > 3599
        lastGameTime = currentGameTime
        if skippedTime and finishDelay then
            log('Time skip detected during delay. Ending delay phase.')
            finishDelay()
        end
    end
end

local function onSave()
    if not savedWander and not state and not walkOutWaiting then return end
    local w = walkOutWaiting and walkOutWaiting.data
    return {
        walkOutWaiting = w and {
            startPos = vec3T(w.startPos), startCell = w.startCell,
            startRot = rotT(w.startRot), savedWander = w.savedWander,
        } or nil,
        savedWander = savedWander,
        state = state,
        targetDoorPos = vec3T(targetDoorPos),
        arrivalDist = arrivalDist,
        isSafe = isSafe,
        homeCellName = homeCellName,
        doorInsidePos = vec3T(doorInsidePos),
        doorInsideRot = rotT(doorInsideRot),
        doorExitRot = rotT(doorExitRot),
        doorLockLevel = doorLockLevel,
        walkOutStartPos = vec3T(walkOutStartPos),
        walkOutStartCell = walkOutStartCell,
        walkOutStartRot = rotT(walkOutStartRot),
        walkOutWander = walkOutWander,
        scanRange = scanRange,
        reservationCellName = reservationCellName,
        triedSafeCells = triedSafeCells,
        isShop = isShop,
        shopVisitDone = shopVisitDone,
        isTemple = isTemple,
        templeVisitDone = templeVisitDone,
        pathPoints = pathPoints and (function()
            local t = {}
            for _, p in ipairs(pathPoints) do t[#t + 1] = vec3T(p) end
            return t
        end)() or nil,
        pathIndex = pathIndex,
    }
end

local function onLoad(data)
    if not data then return end
    local w = data.walkOutWaiting
    walkOutWaiting = w and {
        data  = { startPos = tVec3(w.startPos), startCell = w.startCell,
                  startRot = tRot(w.startRot), savedWander = w.savedWander },
        since = core.getSimulationTime(), asked = false,
    } or nil
    savedWander = data.savedWander
    state = data.state
    targetDoorPos = tVec3(data.targetDoorPos)
    arrivalDist = data.arrivalDist or 200
    isSafe = data.isSafe or false
    isShop = data.isShop or false
    homeCellName = data.homeCellName
    doorInsidePos = tVec3(data.doorInsidePos)
    doorInsideRot = tRot(data.doorInsideRot)
    doorExitRot = tRot(data.doorExitRot)
    doorLockLevel = data.doorLockLevel
    walkOutStartPos = tVec3(data.walkOutStartPos)
    walkOutStartCell = data.walkOutStartCell
    walkOutStartRot = tRot(data.walkOutStartRot)
    walkOutWander = data.walkOutWander
    scanRange = data.scanRange or 3000
    reservationCellName = data.reservationCellName
    triedSafeCells = data.triedSafeCells or {}
    shopVisitDone = data.shopVisitDone or false
    isTemple = data.isTemple or false
    templeVisitDone = data.templeVisitDone or false
    if data.pathPoints then
        local pts = {}
        for _, p in ipairs(data.pathPoints) do pts[#pts + 1] = tVec3(p) end
        pathPoints = pts
        pathIndex  = data.pathIndex or 1
    else
        pathPoints = nil
        pathIndex  = nil
    end

    -- restart lost AI packages
    if state == 'walking' and targetDoorPos then
        async:newUnsavableSimulationTimer(0.5, function()
            if state ~= 'walking' then return end
            AI.removePackages('Wander')
            -- resume toward the current waypoint if a path is active
            local dest = targetDoorPos
            if pathPoints and pathIndex then
                dest = pathPoints[pathIndex]
            end
            AI.startPackage({
                type = 'Travel', destPosition = dest,
                isRepeat = false, cancelOther = false,
            })
            resetStuck()
        end)
    elseif state == 'delaying' and targetDoorPos then
        -- delay timer lost, start walking immediately
        async:newUnsavableSimulationTimer(0.5, function()
            if state ~= 'delaying' then return end
            startWalkToDoor()
        end)
    elseif state == 'returning' then
        async:newUnsavableSimulationTimer(0.5, function()
            if state ~= 'returning' then return end
            AI.removePackages('Wander')
            AI.startPackage({
                type = 'Travel', destPosition = self.startingPosition,
                isRepeat = false, cancelOther = false,
            })
            resetStuck()
        end)
    elseif state == 'walkingOut' and targetDoorPos then
        async:newUnsavableSimulationTimer(0.5, function()
            if state ~= 'walkingOut' then return end
            AI.removePackages('Wander')
            AI.startPackage({
                type = 'Travel', destPosition = targetDoorPos,
                isRepeat = false, cancelOther = false,
            })
            resetStuck()
        end)
    end
    syncChecks()
end


-- the player left the interior while it was walking out, or waiting for its chore to end first: the
-- global puts it outside where it stood, as if it had reached the door
local function onInactive()
    checkCallback = nil
    if pendingReservation then
        core.sendGlobalEvent('NPCSch_ReleaseReservation', {
            npcId = self.object.id,
            cellName = pendingReservation.cellName,
        })
        pendingReservation = nil
    end
    local w = walkOutWaiting and walkOutWaiting.data
    if not w and state ~= 'walkingOut' then return end
    local pos = w and w.startPos or walkOutStartPos
    if not pos then return end
    walkOutWaiting = nil
    AI.removePackages('Travel')
    core.sendGlobalEvent('NPCSch_WalkOutNow', {
        actor       = self.object,
        cell        = (w and w.startCell) or walkOutStartCell or '',
        pos         = pos,
        rotation    = (w and w.startRot) or walkOutStartRot,
        savedWander = (w and w.savedWander) or walkOutWander,
    })
    -- stands still until the global's RestoreFull
    setState('waitSnap')
    targetDoor, targetDoorPos = nil, nil
    log('Left behind while walking out, going out now')
end

-- GSB comp
local function bystanderBusy()
    local B = I.Bystanders
    return (B ~= nil and B.isWatching ~= nil and B.isWatching()) == true
end

-- no reposition can replace the Travel to the door
local function releaseBystander()
    local B = I.Bystanders
    if B and B.isWatching and B.isWatching() and B.release then B.release() end
end

-- global tells NPC to go home
local function onNPCSch_InitGoHome(data)
    if not self:isActive() or types.Actor.isDead(self.object) then return end
    if pendingReservation then
        if data.mode == 'instant' then pendingReservation.mode = 'instant' end
        return
    end
    if not state and bystanderBusy() then return end
    -- going home ALWAYS has priority over shop and temple visits
    if state and (isShop or isTemple) then
        log('Go-home interrupting visit, state:', state, 'isShop:', isShop, 'isTemple:', isTemple)
        isShop = false
        isTemple = false
        shopVisitDone = true
        templeVisitDone = true
        -- if walking/delaying to destination, cancel and let go-home take over
        if state == 'walking' or state == 'delaying' then
            AI.removePackages('Travel')
            AI.removePackages('Wander')
            setState(nil)
            -- fall through to normal go-home
        else
            -- disabled/inside/walkingOut/returning — global handles
            return
        end
    end
    if state then return end
    scanRange    = data.scanRange or 3000
    arrivalDist  = data.arrivalDist or 200
    logEnabled   = data.logEnabled or false
    local mode   = data.mode or 'animated'
    local delay  = data.delay or 0
    triedSafeCells = {}
    pendingReservation = nil
    reservationCellName = nil


    local pkg = AI.getActivePackage()
    if pkg and pkg.type ~= 'Wander' then
       return 
     end


    saveWander()

    -- tier 1: personal home
    local door = findHomeDoor(scanRange)
    if door then
        isSafe = false
        targetDoor = door
        targetDoorPos = door.position
        
        local dc2 = Door.destCell(door)
        if dc2 then
            homeCellName = dc2.name or ''
        end
        resolveDoorInside(door)
        
        local ovr = getDoorOverride(homeCellName, false)
        if ovr then
            targetDoorPos = ovr
            log('Door override applied for home:', homeCellName)
        end

        -- multi-point path override takes precedence
        local pathDoor = getPathOverride(homeCellName)
        if pathDoor then
            targetDoorPos = pathDoor
            log('Path override applied for home:', homeCellName, '(', #pathPoints, 'points )')
        end
        
        if mode == 'instant' then
            setState('walking')
            registerWith('walking')
            core.sendGlobalEvent('NPCSch_RequestLOS', {
                actor = self.object, door = door, safe = false,
            })
            return
        end
        
        if delay > 0 then
            delayWalk(delay)
        else
            startWalkToDoor()
            registerWith('walking')
        end
        log('GoHome mode:', mode, 'personal home found')
        return
    end
    
    -- tier 2: safe place with reservation
    log('No personal home, searching safe places')
    local candidates = findAvailableSafeDoors(scanRange, true)
    
    if #candidates == 0 then
        core.sendGlobalEvent('NPCSch_NoDoor', { actorId = self.object.id })
        return
    end
    
    tryNextSafePlace(mode, delay, candidates, 1)
end

local function onNPCSch_SafeReservationResponse(data)
    if not pendingReservation or data.requestId ~= reservationRequestId then return end
    
    local p = pendingReservation
    pendingReservation = nil
    
    if data.accepted then
        log('Reservation ACCEPTED for', data.cellName)
        
        isSafe = true
        targetDoor = p.door
        targetDoorPos = p.door.position
        reservationCellName = data.cellName
        
        local dc = Door.destCell(p.door)
        if dc then
            homeCellName = dc.name or ''
        end
        resolveDoorInside(p.door)
        
        local ovr = getDoorOverride(homeCellName, false)
        if ovr then
            targetDoorPos = ovr
            log('Door override applied for safe:', homeCellName)
        end

        local pathDoor = getPathOverride(homeCellName)
        if pathDoor then
            targetDoorPos = pathDoor
            log('Path override applied for safe:', homeCellName, '(', #pathPoints, 'points )')
        end
        
        if p.mode == 'instant' then
            -- request LOS check: if player not looking, disable immediately
            setState('walking')
            registerWith('walking')
            core.sendGlobalEvent('NPCSch_RequestLOS', {
                actor = self.object, door = p.door, safe = true,
            })
            return
        end
        
        -- animated: walk with optional delay
        if p.delay > 0 then
            delayWalk(p.delay)
        else
            startWalkToDoor()
            registerWith('walking')
        end
        log('GoHome mode:', p.mode, 'safe:', tostring(isSafe))
    else
        log('Reservation REJECTED for', p.cellName, 'trying next')
        triedSafeCells[p.cellName:lower()] = true
        tryNextSafePlace(p.mode, p.delay, p.candidates, p.nextIndex)
    end
end

-- instant disable: player left exterior, can't see NPCs
local function onNPCSch_InstantDisable()
    if state ~= 'walking' and state ~= 'delaying' then return end
    disableAtDoor()
    log('Instant disable')
end

-- Night sweep: NPC still delaying, cancel delay and start walking
local function onNPCSch_ForceViaLOS()
    if state ~= 'delaying' then return end
    startWalkToDoor()
    log('ForceViaLOS: started walking')
end

-- LOS check result
local function onNPCSch_LOSDone(data)
    if state == 'waitSnap' then
        if data.canTeleport then
            core.sendGlobalEvent('NPCSch_Teleport', {
                actor = self.object,
                cell = self.cell and (self.cell.name or '') or '',
                pos = self.startingPosition,
                rotation = self.startingRotation,
            })
            restoreOriginalWander()
            core.sendGlobalEvent('NPCSch_Returned', { actorId = self.object.id })
            setState(nil)
        else
            async:newUnsavableSimulationTimer(1, function()
                if state ~= 'waitSnap' then return end
                core.sendGlobalEvent('NPCSch_RequestLOS', {
                    actor = self.object, door = nil, safe = false,
                })
            end)
        end
        return
    end

    if not data.canTeleport then
        -- player is looking, switch to animated walk to door
        log('LOS: player sees me, walking to door instead')
        startWalkToDoor()
        return
    end
    -- player not looking: disable at door immediately
    disableAtDoor()
end

-- global enables NPC inside safe place: start wander
local function onNPCSch_StartSafeWander()
    setState('inside')
    AI.removePackages('Wander')
    AI.removePackages('Travel')
    AI.startPackage({
        type = 'Wander',
        distance = DEFAULTS.SAFE_WANDER_DIST,
        duration = DEFAULTS.SAFE_WANDER_DURATION,
        idle = DEFAULTS.SAFE_WANDER_IDLE,
        isRepeat = true,
    })
    log('Started safe wander inside')
end

-- global enables NPC inside personal home
local function onNPCSch_StartHomeStand()
    setState('inside')
    AI.removePackages('Wander')
    AI.removePackages('Travel')
    AI.startPackage({ type = 'Wander', distance = 128, duration = 5, isRepeat = true })
    log('Standing in personal home')
end

-- cancel everything and restore
local function onNPCSch_CancelAndRestore()
    dropWalkOut()

    AI.removePackages('Travel')
    AI.removePackages('Wander')
    if isSafe and reservationCellName then
        core.sendGlobalEvent('NPCSch_ReleaseReservation', {
            npcId = self.object.id,
            cellName = reservationCellName,
        })
        reservationCellName = nil
    end
    restoreOriginalWander()
    setState(nil)
    targetDoor = nil
    targetDoorPos = nil
    doorInsidePos = nil
    doorInsideRot = nil
    doorExitRot = nil
    doorLockLevel = nil
    walkOutStartPos = nil
    walkOutStartCell = nil
    walkOutStartRot = nil
    walkOutWander = nil
    triedSafeCells = {}
    pendingReservation = nil
    isShop = false
    shopVisitDone = false
    isTemple = false
    templeVisitDone = false
    log('Cancelled and restored')
end

-- hard reset / full restore
local function onNPCSch_RestoreFull(data)
    dropWalkOut()
    AI.removePackages('Travel')
    AI.removePackages('Wander')
    if isSafe and reservationCellName then
        core.sendGlobalEvent('NPCSch_ReleaseReservation', {
            npcId = self.object.id,
            cellName = reservationCellName,
        })
        reservationCellName = nil
    end
    if data and data.savedWander then
        savedWander = data.savedWander
    end
    restoreOriginalWander()
    setState(nil)
    targetDoor = nil
    targetDoorPos = nil
    doorInsidePos = nil
    doorInsideRot = nil
    doorExitRot = nil
    doorLockLevel = nil
    walkOutStartPos = nil
    walkOutStartCell = nil
    walkOutStartRot = nil
    walkOutWander = nil
    triedSafeCells = {}
    pendingReservation = nil
    isShop = false
    shopVisitDone = false
    isTemple = false
    templeVisitDone = false
    pathPoints = nil
    pathIndex = nil
    log('Full restore')
end

-- morning: walk to starting position
local function onNPCSch_WalkToStart(data)
    AI.removePackages('Wander')
    AI.removePackages('Travel')
    savedWander = data.savedWander
    travel(data.startPos)
    setState('returning')
    resetStuck()
    log('Walking to start pos')
end

-- morning: NPC inside, player inside same cell: walk to door, then teleport to startPos
onNPCSch_WalkOutAndReturn = function(data)
    releaseBystander()
    if waitForChore(data) then return end
    local best, bestD = nil, math.huge
    for _, d in ipairs(nearby.doors) do
        if d:isValid() and Door.isTeleport(d) then
            local dist = (d.position - self.object.position):length()
            if dist < bestD then best = d; bestD = dist end
        end
    end
    if best then
        AI.removePackages('Wander')
        AI.removePackages('Travel')
        targetDoor = best
        targetDoorPos = best.position
        AI.startPackage({
            type = 'Travel', destPosition = best.position,
            isRepeat = false, cancelOther = false,
        })
        setState('walkingOut')
        walkOutStartPos  = data.startPos
        walkOutStartCell = data.startCell
        walkOutStartRot  = data.startRot
        walkOutWander    = data.savedWander
        resetStuck()
        log('Walking to interior door for morning exit')
    else
        -- no door found, teleport directly
        core.sendGlobalEvent('NPCSch_Teleport', {
            actor = self.object,
            cell = data.startCell or '',
            pos = data.startPos,
            rotation = data.startRot,
        })
        savedWander = data.savedWander
        restoreOriginalWander()
        core.sendGlobalEvent('NPCSch_Returned', { actorId = self.object.id })
        setState(nil)
    end
end

local function onNPCSch_SetLog(data)
    logEnabled = data.enabled or false
end

local function onNPCSch_ResetShopFlag()
    shopVisitDone = false
end

local function onNPCSch_ResetTempleFlag()
    templeVisitDone = false
end

-- global enables NPC inside shop: start wander
local function onNPCSch_StartShopWander()
    setState('inside')
    AI.removePackages('Wander')
    AI.removePackages('Travel')
    AI.startPackage({
        type = 'Wander',
        distance = DEFAULTS.SHOP_WANDER_DIST,
        duration = DEFAULTS.SAFE_WANDER_DURATION,
        idle = DEFAULTS.SAFE_WANDER_IDLE,
        isRepeat = true,
    })
    log('Started shop wander inside')
end

-- global tells NPC to try visiting a shop
local function onNPCSch_InitShopVisit(data)
    if state then return end
    if shopVisitDone then return end
    if bystanderBusy() then return end

    scanRange  = data.scanRange or 3000
    arrivalDist = data.arrivalDist or 200
    logEnabled = data.logEnabled or false

    -- must have active Wander (not returning from morning etc.)
    local pkg = AI.getActivePackage()
    if not pkg or pkg.type ~= 'Wander' then
        log('Shop visit denied: no active Wander')
        return
    end

    -- roll the dice, one roll per activation
    shopVisitDone = true
    local chance = data.shopChance or 30
    if math.random(100) > chance then
        log('Shop visit: dice roll failed')
        return
    end

    local candidates = findShopDoors(scanRange)
    if #candidates == 0 then
        log('Shop visit: no shops in range')
        return
    end

    -- pick random shop
    local pick = candidates[math.random(#candidates)]

    saveWander()

    isShop = true
    isSafe = false
    targetDoor = pick.door
    targetDoorPos = pick.door.position

    local dc2 = Door.destCell(pick.door)
    if dc2 then
        homeCellName = dc2.name or ''
    end
    resolveDoorInside(pick.door)

    local ovr = getDoorOverride(homeCellName, true)
    if ovr then
        targetDoorPos = ovr
        log('Door override applied for shop:', homeCellName)
    end

    -- no delay, walk immediately
    startWalkToDoor()
    registerWith('walking')
    log('Shop visit: walking to', homeCellName or '?')
end

-- global tells NPC to try visiting a temple
local function onNPCSch_InitTempleVisit(data)
    if state then return end
    if templeVisitDone then return end
    if bystanderBusy() then return end

    scanRange   = data.scanRange or 3000
    arrivalDist = data.arrivalDist or 200
    logEnabled  = data.logEnabled or false

    -- must have active Wander (not returning from morning etc.)
    local pkg = AI.getActivePackage()
    if not pkg or pkg.type ~= 'Wander' then
        log('Temple visit denied: no active Wander')
        return
    end

    -- roll the dice, one roll per activation
    templeVisitDone = true
    local chance = data.templeChance or 2
    if math.random(100) > chance then
        log('Temple visit: dice roll failed')
        return
    end

    local candidates = findTempleDoors(scanRange, data.cult)
    if #candidates == 0 then
        log('Temple visit: no temples in range for cult', data.cult)
        return
    end

    -- nearest temple is the expected destination
    table.sort(candidates, function(a, b) return a.dist < b.dist end)
    local pick = candidates[1]

    saveWander()

    isTemple = true
    isShop = false
    isSafe = false
    targetDoor = pick.door
    targetDoorPos = pick.door.position

    local dc2 = Door.destCell(pick.door)
    if dc2 then
        homeCellName = dc2.name or ''
    end
    resolveDoorInside(pick.door)

    local ovr = getDoorOverride(homeCellName, true)
    if ovr then
        targetDoorPos = ovr
        log('Door override applied for temple:', homeCellName)
    end

    -- no delay, walk immediately
    startWalkToDoor()
    registerWith('walking')
    log('Temple visit (', data.cult, '): walking to', homeCellName or '?')
end

--==============================================================================================
-- public interface as I.NPCSchedule

local INTERFACE_VERSION = 2

-- true while npcschedule owns this actor (any non-nil state)
local function ifaceIsBusy()
    return state ~= nil
end

-- raw state string, or nil when idle
-- 'delaying' | 'walking' | 'disabled' | 'inside' | 'walkingOut' | 'returning' | 'waitSnap'
local function ifaceGetBusyState()
    return state
end

-- another mod handing back the Wander it borrowed before we took this actor
local function ifaceAdoptWander(w)
    if savedWander or not w then return end
    savedWander = w
    log('Adopted wander from another mod')
end

return {
    engineHandlers = {
        onSave     = onSave,
        onLoad     = onLoad,
        onInit     = onLoad,
        onActive   = syncChecks,
        onInactive = onInactive,
    },
    eventHandlers = {
        NPCSch_InitGoHome = onNPCSch_InitGoHome,
        NPCSch_SafeReservationResponse = onNPCSch_SafeReservationResponse,
        NPCSch_InstantDisable = onNPCSch_InstantDisable,
        NPCSch_ForceViaLOS = onNPCSch_ForceViaLOS,
        NPCSch_LOSDone = onNPCSch_LOSDone,
        NPCSch_StartSafeWander = onNPCSch_StartSafeWander,
        NPCSch_StartHomeStand = onNPCSch_StartHomeStand,
        NPCSch_CancelAndRestore = onNPCSch_CancelAndRestore,
        NPCSch_RestoreFull = onNPCSch_RestoreFull,
        NPCSch_WalkToStart = onNPCSch_WalkToStart,
        NPCSch_WalkOutAndReturn = onNPCSch_WalkOutAndReturn,
        NPCSch_SetLog = onNPCSch_SetLog,
        NPCSch_ResetShopFlag = onNPCSch_ResetShopFlag,
        NPCSch_ResetTempleFlag = onNPCSch_ResetTempleFlag,
        NPCSch_StartShopWander = onNPCSch_StartShopWander,
        NPCSch_InitShopVisit = onNPCSch_InitShopVisit,
        NPCSch_InitTempleVisit = onNPCSch_InitTempleVisit,
        NPCSch_DialogueStart = onDialogueStart,
        NPCSch_DialogueEnd   = onDialogueEnd,
    },
    interfaceName = 'NPCSchedule',
    interface = {
        version      = INTERFACE_VERSION,
        isBusy       = ifaceIsBusy,
        getBusyState = ifaceGetBusyState,
        adoptWander  = ifaceAdoptWander,
    },
}
