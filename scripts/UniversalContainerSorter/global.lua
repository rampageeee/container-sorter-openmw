local core = require('openmw.core')
local types = require('openmw.types')
local I = require('openmw.interfaces')
local Inventory = require('scripts.UniversalContainerSorter.inventory')
local Plan = require('scripts.UniversalContainerSorter.plan')

local intent
local candidate
local session

local function sameRequest(state, data)
    return state and state.token == data.token and state.player == data.player
end

I.Activation.addHandlerForType(types.Container, function(target, actor)
    if not intent or intent.player ~= actor then
        return
    end
    local token = intent.token
    intent = nil

    -- Leave locks and traps entirely to native activation, even if the player has the key.
    if types.Lockable.isLocked(target) or types.Lockable.getTrapSpell(target) then
        return
    end

    candidate = { token = token, player = actor, target = target }
    actor:sendEvent('UCS_Candidate', { token = token, target = target })
    core.sendGlobalEvent('UCS_ExpireCandidate', { token = token, player = actor })
    -- Continue the normal activation chain. The player only opens the sorter if
    -- the engine subsequently enters Container mode for this reference.
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
            intent, candidate, session = nil, nil, nil
        end,
    },
    eventHandlers = {
        UCS_Intent = function(data)
            if data.player:isValid() and types.Player.objectIsInstance(data.player) then
                intent = { player = data.player, token = data.token }
                -- Events sent from a handler enter the next batch. Current-batch
                -- activation still has access to the intent.
                core.sendGlobalEvent('UCS_ExpireIntent', data)
            end
        end,
        UCS_ExpireIntent = function(data)
            if sameRequest(intent, data) then
                intent = nil
            end
        end,
        UCS_ExpireCandidate = function(data)
            if sameRequest(candidate, data) then
                candidate.player:sendEvent('UCS_ExpireCandidate', { token = data.token })
            end
        end,
        UCS_Close = function(data)
            if sameRequest(candidate, data) then
                candidate = nil
            end
            if sameRequest(session, data) then
                session = nil
            end
        end,
        UCS_Preview = function(data)
            if not sameRequest(candidate, data) or candidate.target ~= data.target then
                return
            end
            local request = candidate
            candidate = nil
            local snapshot, reason = inspect(request, data.options)
            if not snapshot then
                reply(request, { reason = reason })
                return
            end
            session = request
            reply(request, { snapshot = snapshot })
        end,
        UCS_Confirm = function(data)
            if not sameRequest(session, data) then
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
