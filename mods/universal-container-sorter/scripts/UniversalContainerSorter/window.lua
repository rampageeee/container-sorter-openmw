local async = require('openmw.async')
local core = require('openmw.core')
local I = require('openmw.interfaces')
local ui = require('openmw.ui')
local util = require('openmw.util')
local Categories = require('scripts.UniversalContainerSorter.categories')

local l10n = core.l10n('UniversalContainerSorter')
local v2 = util.vector2
local templates = I.MWUI.templates
local dim = util.color.rgb(0.57, 0.52, 0.43)
local selectedColor = util.color.rgb(0.95, 0.88, 0.64)
local columnGap = 6
local cellSize = v2(192, 26)
local rowSize = v2(cellSize.x * 2 + columnGap, cellSize.y)

local function text(value, template, color, size)
    return {
        type = ui.TYPE.Text,
        template = template or templates.textNormal,
        props = {
            text = value,
            textColor = color,
            autoSize = size == nil,
            size = size,
            textAlignV = size and ui.ALIGNMENT.Center or nil,
        },
    }
end

local function button(label, action, selected, size)
    size = size or cellSize
    local events
    if action then
        events = { mouseClick = async:callback(action) }
    end
    local color = selected and selectedColor or not action and dim or nil
    if selected ~= nil then
        label = (selected and '[x]  ' or '[ ]  ') .. label
    end
    local caption = text(label, nil, color, size - v2(14, 4))
    caption.props.position = v2(5, 0)
    return {
        template = templates.borders,
        props = { size = size },
        events = events,
        content = ui.content { caption },
    }
end

local function spacer(width, height)
    return { props = { size = v2(width, height) } }
end

local function flex(children, horizontal)
    local content = {}
    for index, child in ipairs(children) do
        if index > 1 then
            content[#content + 1] = horizontal and spacer(columnGap, 0) or spacer(0, 4)
        end
        content[#content + 1] = child
    end
    return {
        type = ui.TYPE.Flex,
        external = { stretch = 1 },
        props = { horizontal = horizontal },
        content = ui.content(content),
    }
end

local function center(children)
    return {
        layer = 'Windows',
        type = ui.TYPE.Widget,
        props = { relativeSize = v2(1, 1) },
        content = ui.content {
            {
                template = templates.boxSolidThick,
                props = { relativePosition = v2(0.5, 0.5), anchor = v2(0.5, 0.5) },
                content = ui.content {
                    {
                        template = templates.padding,
                        content = ui.content { flex(children, false) },
                    },
                },
            },
        },
    }
end

local function layout(state, actions)
    local children = { text(l10n('title'), templates.textHeader) }
    local snapshot = state.snapshot
    if snapshot then
        children[#children + 1] = text(l10n('container', { name = snapshot.name }))
        children[#children + 1] = text(l10n('capacity', {
            weight = string.format('%.2f', snapshot.weight),
            capacity = string.format('%.2f', snapshot.capacity),
        }))
        children[#children + 1] = button(l10n('quickStack', { count = snapshot.quickCount }),
            not state.pending and snapshot.quickCount > 0 and actions.quickStack or nil, state.quickStack, rowSize)
        children[#children + 1] = flex({
            text(l10n('categories'), nil, nil, cellSize),
            button(l10n(state.allSelected and 'clearAll' or 'selectAll'),
                not state.pending and next(snapshot.counts) ~= nil and actions.selectAll or nil),
        }, true)
        for index = 1, #Categories.order, 2 do
            local row = {}
            for column = index, index + 1 do
                local category = Categories.order[column]
                local count = snapshot.counts[category] or 0
                local action
                if not state.pending and count > 0 then
                    action = function() actions.category(category) end
                end
                row[#row + 1] = button(l10n('categoryCount', { category = l10n(category), count = count }),
                    action, not state.quickStack and state.categories[category] == true)
            end
            children[#children + 1] = flex(row, true)
        end

        if state.changed then
            children[#children + 1] = text(l10n('changed'), templates.textHeader)
        end
        local skipped = state.plan.eligible - state.plan.quantity
        if skipped > 0 then
            children[#children + 1] = text(l10n('noRoomFor', { count = skipped }))
        end
        local label = state.pending and l10n('transferring') or l10n('deposit', { count = state.plan.quantity })
        local canConfirm = not state.pending and state.plan.quantity > 0
        children[#children + 1] = flex({
            button(label, canConfirm and actions.confirm or nil),
            button(l10n('cancel'), not state.pending and actions.cancel or nil),
        }, true)
    else
        children[#children + 1] = text(l10n('reading'))
        children[#children + 1] = button(l10n('cancel'), actions.cancel, nil, rowSize)
    end

    return center(children)
end

local function render(element, state, actions)
    local newLayout = layout(state, actions)
    if not element then
        return ui.create(newLayout)
    end
    element.layout = newLayout
    element:update()
    return element
end

return { render = render }
