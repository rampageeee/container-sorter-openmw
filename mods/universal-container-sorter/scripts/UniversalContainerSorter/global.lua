local core = require('openmw.core')
local types = require('openmw.types')
local I = require('openmw.interfaces')
local Inventory = require('scripts.UniversalContainerSorter.inventory')
local Plan = require('scripts.UniversalContainerSorter.plan')

local activation
local session

local function sameRequest(state, data)
    return state and state.token == data.token and state.player == data.player
end

local function sameTarget(state, data)
    return state and state.player == data.player and state.target == data.target
end

local function debugLog(data, message)
    if data.debug == true then
        print('[Universal Container Sorter] ' .. message)
    end
end

I.Activation.addHandlerForType(types.Container, function(target, actor)
    if not types.Player.objectIsInstance(actor) then
        return
    end
    -- Record the state BEFORE the standard action may unlock or disarm it.
    -- This handler never interrupts the native activation chain.
    activation = {
        player = actor,
        target = target,
        blocked = types.Lockable.isLocked(target) or types.Lockable.getTrapSpell(target) ~= nil,
    }
end)

local function reply(request, data)
    data.token = request.token
    request.player:sendEvent('UCS_Response', data)
end

local function inspect(request, options)
    local ok, snapshot, reason, sources = pcall(Inventory.inspectTarget, request.target, request.player, options)
    if not ok then
        print('[Universal Container Sorter] Inventory inspection failed: ' .. tostring(snapshot))
        return nil, 'inspectionFailed'
    end
    return snapshot, reason, sources
end

return {
    engineHandlers = {
        onLoad = function()
            activation, session = nil, nil
        end,
    },
    eventHandlers = {
        UCS_DiscardActivation = function(data)
            if sameTarget(activation, data) then
                activation = nil
            end
        end,
        UCS_Close = function(data)
            if sameRequest(session, data) then
                session = nil
            end
        end,
        UCS_Preview = function(data)
            if not data.player or not data.player:isValid()
                or not types.Player.objectIsInstance(data.player) then
                return
            end
            local matched = sameTarget(activation, data)
            local blocked = matched and activation.blocked
            activation = nil
            session = nil
            local request = { token = data.token, player = data.player, target = data.target }
            if not matched then
                debugLog(data, 'Preview rejected: no matching native activation')
                reply(request, { reason = 'activationUnverified' })
                return
            end
            if blocked then
                debugLog(data, 'Preview rejected: container was locked or trapped at activation')
                reply(request, { reason = 'lockedOrTrapped' })
                return
            end
            debugLog(data, 'Inspecting ' .. request.target.recordId)
            local snapshot, reason = inspect(request, data.options)
            if not snapshot then
                debugLog(data, 'Preview rejected: ' .. tostring(reason))
                reply(request, { reason = reason })
                return
            end
            debugLog(data, 'Preview ready: ' .. #snapshot.stacks .. ' eligible stacks')
            session = request
            reply(request, { snapshot = snapshot })
        end,
        UCS_Confirm = function(data)
            if not sameRequest(session, data) then
                debugLog(data, 'Confirmation ignored: no matching session')
                return
            end
            local request = session
            session = nil
            local snapshot, reason, sources = inspect(request, data.options)
            if not snapshot then
                reply(request, { reason = reason })
                return
            end

            local plan = Plan.selectStacks(snapshot, data.quickStack, data.categories)
            if not Plan.sameStacks(plan.stacks, data.stacks) then
                session = request
                reply(request, { snapshot = snapshot, changed = true })
                return
            end

            local queued = 0
            for _, stack in ipairs(plan.stacks) do
                local item = sources[stack.id]
                local ok, errorMessage = pcall(item.moveInto, item, request.target)
                if not ok then
                    print('[Universal Container Sorter] Transfer stopped: ' .. tostring(errorMessage))
                    reply(request, { moved = queued, partial = true })
                    return
                end
                queued = queued + stack.count
            end
            reply(request, { moved = queued })
        end,
    },
}
