local ui = require('openmw.ui')
local util = require('openmw.util')
local async = require('openmw.async')
local core = require('openmw.core')
local I = require('openmw.interfaces')

local element
local target
local vec = util.vector2
local function clear()
    if element then element:destroy(); element = nil end
    target = nil
end

local function choose(sort)
    if not target then return end
    local chest = target
    clear()
    -- Global scripts own inventory changes. The response opens the container.
    core.sendGlobalEvent('MIUniversalSorterChoice', {chest = chest, sort = sort})
end

local function button(label, x, sort)
    return {
        template = I.MWUI.templates.boxSolid,
        props = {position = vec(x, 57), size = vec(96, 34)},
        content = ui.content{{
            template = I.MWUI.templates.textNormal,
            props = {text = label, relativePosition = vec(0.5, 0.5), anchor = vec(0.5, 0.5)},
        }},
        events = {mouseClick = async:callback(function() choose(sort) end)},
    }
end

local function prompt(data)
    if target or I.UI.getMode() ~= nil then return end
    target = data.chest
    -- Native Interface mode enables the cursor; hide its ordinary windows.
    I.UI.setMode('Interface', {windows = {}})
    element = ui.create{
        layer = 'Windows',
        template = I.MWUI.templates.boxSolid,
        props = {size = vec(260, 112), relativePosition = vec(0.5, 0.5), anchor = vec(0.5, 0.5)},
        content = ui.content{
            {template = I.MWUI.templates.textNormal,
             props = {text = 'Sort ingredients?', relativePosition = vec(0.5, 0),
                      position = vec(0, 24), anchor = vec(0.5, 0.5)}},
            button('Yes', 24, true),
            button('No', 140, false),
        },
    }
end

local function openChest(data)
    clear()
    if data.chest and data.chest:isValid() then
        I.UI.setMode('Container', {target = data.chest})
        if data.skipped > 0 then ui.showMessage(tostring(data.skipped) .. ' protected ingredient(s) kept in inventory.') end
        if data.failed > 0 then ui.showMessage('Some ingredients could not be transferred; see openmw.log.') end
    else
        I.UI.setMode()
    end
end

return {
    engineHandlers = {onLoad = clear},
    eventHandlers = {
        MIUniversalSorterPrompt = prompt,
        MIUniversalSorterOpen = openChest,
        MIUniversalSorterUnavailable = function()
            clear()
            I.UI.setMode()
            ui.showMessage('Ingredient chest unavailable.')
        end,
        UiModeChanged = function(data)
            if target and data.newMode ~= 'Interface' then clear() end
        end,
    },
}
