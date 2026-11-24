local async = require('openmw.async')
local core = require('openmw.core')
local I = require('openmw.interfaces')
local input = require('openmw.input')
local self = require('openmw.self')
local storage = require('openmw.storage')
local ui = require('openmw.ui')
local Plan = require('scripts.UniversalContainerSorter.plan')
local Window = require('scripts.UniversalContainerSorter.window')

local l10n = core.l10n('UniversalContainerSorter')
local settings = storage.playerSection('Settings/UniversalContainerSorter')
local player = self.object
local containerMode = I.UI.MODE.Container

local token = 0
local held = false
local modifier = input.KEY.T
local candidate
local active
local element

local function readModifier()
    local name = settings:get('modifier') or 'T'
    name = name:match('^%s*(.-)%s*$')
    if #name == 1 then
        name = name:upper()
    end
    local ok, code = pcall(function() return input.KEY[name] end)
    modifier = ok and code or input.KEY.T
    held = false
end

settings:subscribe(async:callback(function(_, key)
    if key == nil or key == 'modifier' then
        readModifier()
    end
end))
readModifier()

local function send(event, request, data)
    data = data or {}
    data.player = player
    data.token = request.token
    core.sendGlobalEvent(event, data)
end

local function options()
    local favorites = {}
    local extender = I.InventoryExtender
    if extender and extender.VERSION == 1 and extender.getContext then
        -- Make a request-local copy of Inventory Extender's live instance-ID map.
        local context = extender.getContext()
        for id, favorite in pairs(context.favoriteItems) do
            if favorite == true then
                favorites[id] = true
            end
        end
    end
    return {
        favorites = favorites,
        allowKeys = settings:get('allowKeys') == true,
        blacklist = settings:get('blacklist') or '',
    }
end

local function clearCandidate()
    if candidate then
        send('UCS_Close', candidate)
        candidate = nil
    end
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
    if held and not input.isKeyPressed(modifier) then
        held = false
    end
    if I.UI.getMode() ~= containerMode or data.newMode ~= containerMode then
        close()
        clearCandidate()
        return
    end
    if active and data.arg ~= active.target then
        close()
    end
    if candidate and data.arg == candidate.target and not active then
        active = { token = candidate.token, target = candidate.target, categories = {}, quickStack = false }
        candidate = nil
        refresh()
        send('UCS_Preview', active, { target = active.target, options = options() })
    else
        clearCandidate()
    end
end

return {
    engineHandlers = {
        onKeyPress = function(key)
            if key.code == modifier then
                held = true
            end
        end,
        onKeyRelease = function(key)
            if key.code == modifier then
                held = false
            end
        end,
        onInputAction = function(action)
            if action ~= input.ACTION.Activate or not held or I.UI.getMode() ~= nil then
                return
            end
            -- Key callbacks can be missed when the console or a modal owns input.
            -- Check the physical key only on Activate before sending the intent.
            held = input.isKeyPressed(modifier)
            if held then
                token = token + 1
                send('UCS_Intent', { token = token })
            end
        end,
        onLoad = function()
            close()
            clearCandidate()
            readModifier()
        end,
        onInactive = function()
            close()
            clearCandidate()
            held = false
        end,
        onTeleported = function()
            close()
            clearCandidate()
            held = false
        end,
    },
    eventHandlers = {
        UCS_Candidate = function(data)
            clearCandidate()
            if not active then
                candidate = data
            else
                send('UCS_Close', data)
            end
        end,
        UCS_ExpireCandidate = function(data)
            if candidate and candidate.token == data.token then
                clearCandidate()
            end
        end,
        UiModeChanged = onUiModeChanged,
        UCS_Response = function(data)
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
                ui.showMessage(l10n(data.reason))
            else
                I.UI.removeMode(containerMode)
                ui.showMessage(l10n(data.partial and 'partial' or 'transferred', { count = data.moved }))
            end
        end,
    },
}
