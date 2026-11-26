local core = require('openmw.core')
local I = require('openmw.interfaces')
local input = require('openmw.input')
local self = require('openmw.self')
local storage = require('openmw.storage')
local types = require('openmw.types')
local ui = require('openmw.ui')
local Plan = require('scripts.UniversalContainerSorter.plan')
local Window = require('scripts.UniversalContainerSorter.window')

local l10n = core.l10n('UniversalContainerSorter')
local settings = storage.playerSection('Settings/UniversalContainerSorter')
local player = self.object
local containerMode = I.UI.MODE.Container

local token = 0
local active
local element

local function debugLog(message)
    if settings:get('debug') == true then
        print('[Universal Container Sorter] ' .. message)
    end
end

local function readModifier()
    local name = settings:get('modifier') or 'T'
    name = name:match('^%s*(.-)%s*$')
    if #name == 1 then
        name = name:upper()
    end
    local ok, code = pcall(function() return input.KEY[name] end)
    if not ok or code == nil then
        debugLog('Unknown modifier ' .. name .. '; falling back to T')
        return input.KEY.T
    end
    return code
end

local function send(event, request, data)
    data = data or {}
    data.player = player
    data.token = request.token
    data.debug = settings:get('debug') == true
    core.sendGlobalEvent(event, data)
end

local function options()
    local favorites = {}
    local extender = I.InventoryExtender
    if extender and extender.VERSION == 1 and extender.getContext then
        -- Make a request-local copy of Inventory Extender's live instance-ID map.
        local context = extender.getContext()
        for id, favorite in pairs(context and context.favoriteItems or {}) do
            if favorite == true then
                favorites[id] = true
            end
        end
    end
    return {
        favorites = favorites,
        debug = settings:get('debug') == true,
        allowKeys = settings:get('allowKeys') == true,
        protectMWContainers = settings:get('protectMWContainers') ~= false,
        protectLuaContainers = settings:get('protectLuaContainers') == true,
        protectLuaItems = settings:get('protectLuaItems') == true,
        blacklist = settings:get('blacklist') or '',
    }
end

local function close()
    if element then
        element:destroy()
        element = nil
    end
    if active then
        send('UCS_Close', active)
        active = nil
    end
end

local actions = {}
local function refresh()
    if active.snapshot then
        active.plan = Plan.selectStacks(active.snapshot, active.quickStack, active.categories)
        active.allSelected = not active.quickStack and next(active.snapshot.counts) ~= nil
        for category in pairs(active.snapshot.counts) do
            if not active.categories[category] then
                active.allSelected = false
                break
            end
        end
    end
    element = Window.render(element, active, actions)
end

function actions.category(category)
    if not active or active.pending then
        return
    end
    active.quickStack = false
    active.categories[category] = not active.categories[category]
    refresh()
end

function actions.selectAll()
    if not active or active.pending then
        return
    end
    local selected = not active.allSelected
    active.quickStack = false
    for category in pairs(active.snapshot.counts) do
        active.categories[category] = selected
    end
    refresh()
end

function actions.quickStack()
    if not active or active.pending then
        return
    end
    active.quickStack = not active.quickStack
    refresh()
end

function actions.confirm()
    if not active or active.pending or active.plan.quantity == 0 or I.UI.getMode() ~= containerMode then
        return
    end
    active.pending = true
    send('UCS_Confirm', active, {
        options = options(),
        categories = active.categories,
        quickStack = active.quickStack,
        stacks = active.plan.stacks,
    })
    refresh()
end

function actions.cancel()
    if active and not active.pending then
        close()
    end
end

local function onUiModeChanged(data)
    if data.newMode ~= containerMode or I.UI.getMode() ~= containerMode then
        close()
        return
    end

    local target = data.arg
    if active and target == active.target then
        return
    end
    close()

    if not target or not types.Container.objectIsInstance(target) then
        debugLog('Container UI opened without a supported container reference')
        return
    end

    -- The native UI supplies the target after activation. Sample the physical
    -- modifier only here; no key callbacks, polling or cross-script intent.
    local held = input.isKeyPressed(readModifier())
    debugLog('Container UI opened: ' .. target.recordId .. '; modifier held=' .. tostring(held))
    if not held then
        core.sendGlobalEvent('UCS_DiscardActivation', { player = player, target = target })
        return
    end

    token = token + 1
    active = { token = token, target = target, categories = {}, quickStack = false }
    debugLog('Requesting preview: ' .. target.recordId .. '; token=' .. token)
    refresh()
    send('UCS_Preview', active, { target = target, options = options() })
end

return {
    engineHandlers = {
        onLoad = function()
            close()
            debugLog('Player script loaded')
        end,
        onInactive = close,
        onTeleported = close,
    },
    eventHandlers = {
        UiModeChanged = onUiModeChanged,
        UCS_Response = function(data)
            debugLog('Response: token=' .. tostring(data.token) .. '; result=' .. (data.reason or (data.snapshot and 'snapshot' or 'transfer')))
            if not active or active.token ~= data.token then
                return
            end
            if I.UI.getMode() ~= containerMode then
                close()
                return
            end
            if data.snapshot then
                active.snapshot = data.snapshot
                active.pending = false
                active.changed = data.changed
                refresh()
                return
            end
            close()
            if data.reason then
                local message = l10n(data.reason)
                if message == data.reason then
                    local fallback = {
                        mwscriptContainer = 'Container has MWScript. See script settings and openmw.log.',
                        luaScriptContainer = 'Container has a CUSTOM Lua script. See script settings and openmw.log.',
                        blacklistedContainer = 'Container is on the protected record ID blacklist.',
                    }
                    message = fallback[data.reason] or message
                end
                ui.showMessage(message)
            else
                I.UI.removeMode(containerMode)
                ui.showMessage(l10n(data.partial and 'partial' or 'transferred', { count = data.moved }))
            end
        end,
    },
}
