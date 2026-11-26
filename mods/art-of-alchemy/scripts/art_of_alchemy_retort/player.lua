local ambient = require('openmw.ambient')
local async = require('openmw.async')
local core = require('openmw.core')
local input = require('openmw.input')
local interfaces = require('openmw.interfaces')
local self = require('openmw.self')
local storage = require('openmw.storage')
local types = require('openmw.types')
local ui = require('openmw.ui')
local util = require('openmw.util')
local vfs = require('openmw.vfs')

local appearance = require('scripts.art_of_alchemy_retort.appearance')
local apparatus = require('scripts.art_of_alchemy_retort.apparatus')
local bottleInventory = require('scripts.art_of_alchemy_retort.bottles')
local special = require('scripts.art_of_alchemy_retort.special')
local brewing = require('scripts.art_of_alchemy_retort.brewing')
local discovery = require('scripts.art_of_alchemy_retort.discovery')
local grinding = require('scripts.art_of_alchemy_retort.grinding')
local rules = require('scripts.art_of_alchemy_retort.rules')
local settings = require('scripts.art_of_alchemy_retort.settings')
local settingSection = storage.playerSection(settings.section)
local recipeSection = storage.playerSection('ArtOfAlchemyRecipes')
local l10n = core.l10n('ArtOfAlchemy')
settings.register(interfaces.Settings)

local function preferences()
    local values = {}
    for key in pairs(settings.defaults) do values[key] = settings.read(settingSection, key) end
    core.sendGlobalEvent('ArtOfAlchemyRetort_Settings', values)
end

settingSection:subscribe(async:callback(preferences))

local vec = util.vector2
local muted = util.color.rgb(0.62, 0.53, 0.39)
local accent = util.color.rgb(0.98, 0.88, 0.69)
local harmful = util.color.rgb(0.91, 0.54, 0.44)
local matching = util.color.rgb(0.64, 0.81, 0.61)
local trackColor = util.color.rgb(0.22, 0.18, 0.13)
local mode = 'Interface'
local menu, element, naming, workspacePanel
local progress
local white
local known, favorites = {}, {}

local function destroy()
    if menu and menu.recipeField then menu.recipeField:destroy() end
    if menu and menu.searchField then menu.searchField:destroy() end
    if menu and menu.searchPanel then menu.searchPanel:destroy() end
    if workspacePanel then workspacePanel:destroy() end
    if element then element:destroy() end
    element, menu, naming, workspacePanel = nil, nil, nil, nil
end

local function sendAction(action, data, removeMode)
    data = data or {}
    data.retort, data.actor = menu.retort, self
    destroy()
    if removeMode then interfaces.UI.removeMode(mode) end
    core.sendGlobalEvent('ArtOfAlchemyRetort_' .. action, data)
end

local function label(text, x, y, width, options)
    options = options or {}
    local templates = interfaces.MWUI.templates
    return {
        type = ui.TYPE.Text,
        template = options.header and templates.textHeader or templates.textNormal,
        props = {
            text = tostring(text),
            position = vec(x, y),
            size = vec(width, options.height or 22),
            autoSize = false,
            textSize = menu and menu.textSize,
            textColor = options.color,
            textAlignH = options.center and ui.ALIGNMENT.Center or ui.ALIGNMENT.Start,
            textAlignV = ui.ALIGNMENT.Center,
            multiline = options.wrap or false,
            wordWrap = options.wrap or false,
        },
    }
end

local function hideProgress()
    if progress then progress:destroy() end
    progress = nil
end

local function showProgress(data)
    if menu or interfaces.UI.getMode() then return end
    hideProgress()
    local width = 200
    white = white or ui.texture { path = 'white' }
    local bar = ui.create({
        type = ui.TYPE.Container,
        layer = 'Notification',
        template = interfaces.MWUI.templates.boxSolid,
        props = { relativePosition = vec(0.5, 0.61), anchor = vec(0.5, 0) },
        content = ui.content({
            { props = { size = vec(220, 41) }, content = ui.content({
                label(string.format('%s… %d%%', data.activity, math.floor(data.ratio * 100)),
                    10, 1, width, { center = true }),
                { type = ui.TYPE.Image, props = {
                    resource = white, position = vec(10, 28), size = vec(width, 5),
                    color = util.color.rgb(0.28, 0.22, 0.15),
                } },
                { type = ui.TYPE.Image, props = {
                    resource = white, position = vec(10, 28), size = vec(width * data.ratio, 5), color = accent,
                } },
            }) },
        }),
    })
    progress = bar
    async:newUnsavableSimulationTimer(2.5, function()
        if progress == bar then hideProgress() end
    end)
end

local function icon(path, x, y, size)
    if not path or path == '' then return nil end
    local texture = menu.textures[path]
    if texture == nil then
        local candidate = path
        if not vfs.fileExists(candidate) then candidate = path:gsub('%.[^.]+$', '.dds') end
        texture = vfs.fileExists(candidate) and ui.texture { path = candidate } or false
        menu.textures[path] = texture
    end
    if texture then
        return {
            type = ui.TYPE.Image,
            props = { position = vec(x, y), size = vec(size, size), resource = texture },
        }
    end
end

local function click(action)
    return async:callback(function()
        if core.sound.records['menu click'] then
            ambient.playSound('menu click', { volume = 0.7 })
        end
        action()
    end)
end

local function button(text, x, y, width, action, selected, height)
    height = height or 26
    return {
        type = ui.TYPE.Widget,
        template = interfaces.MWUI.templates.borders,
        props = { position = vec(x, y), size = vec(width, height) },
        content = ui.content({
            label(text, 2, 0, width - 8, {
                center = true, color = selected and accent or not action and muted or nil,
                height = height - 4, wrap = height > 26,
            }),
        }),
        events = action and { mouseClick = click(action) } or nil,
    }
end

local targetVerbs = {
    absorb = 'sAbsorb', damage = 'sDamage', drain = 'sDrain',
    fortify = 'sFortify', restore = 'sRestore',
}

local function effectName(effect, magic)
    magic = magic or effect.effect
    local target = effect.affectedAttribute or effect.affectedSkill
    if target then
        local records = effect.affectedAttribute and core.stats.Attribute.records or core.stats.Skill.records
        local record = records[target]
        local suffix = effect.affectedAttribute and 'attribute' or 'skill'
        local verb = targetVerbs[effect.id:match('^(.*)' .. suffix .. '$')]
        local prefix = verb and core.getGMST(verb)
        local name = record and record.name or target
        return prefix and (prefix .. ' ' .. name) or (magic.name .. ' (' .. name .. ')')
    end
    return magic.name
end

local function learnGround(record, threshold)
    if not record.id:match('g%s*$') then return end
    local changed = false
    local groundEffects = record.effects
    for _, raw in ipairs(grinding.rawInputs(record.id)) do
        local originalEffects = raw.effects
        for slot, effect in pairs(groundEffects) do
            local original = originalEffects[slot]
            if original and discovery.visible(known, record, effect, threshold) then
                if discovery.learn(known, raw, original) then changed = true end
            end
        end
    end
    return changed
end

local function showLearning()
    ui.showMessage('You learned a new ingredient effect.')
    local scale = 0.5 * settings.experienceScale(settingSection)
    if scale > 0 then
        local skill = interfaces.SkillProgression
        skill.skillUsed('alchemy', { useType = skill.SKILL_USE_TYPES.Alchemy_UseIngredient, scale = scale })
    end
end

local function learnBrew(data, threshold)
    local result = data.resultId and types.Potion.records[data.resultId]
    if not result or not data.inputIds then return end
    local learned = false
    local resultKeys = {}
    for _, effect in ipairs(result.effects) do resultKeys[brewing.effectKey(effect)] = true end
    for _, ingredientId in ipairs(data.inputIds) do
        local ingredient = types.Ingredient.records[ingredientId]
        if ingredient then
            for _, effect in pairs(ingredient.effects) do
                if resultKeys[brewing.effectKey(effect)] then
                    local wasVisible = discovery.visible(known, ingredient, effect, threshold)
                    if discovery.learn(known, ingredient, effect) and not wasVisible then learned = true end
                end
            end
            learnGround(ingredient, threshold)
        end
    end
    if learned then showLearning() end
end

local function taste(item)
    if item.type ~= types.Ingredient or not settings.read(settingSection, 'discovery') then return end
    local record = types.Ingredient.records[item.recordId]
    if not record or rules.insoluble[record.id:lower()] then return end
    local first = record.effects[1]
    if not first or not first.effect then return end
    local threshold = discovery.threshold(self)
    local wasVisible = discovery.visible(known, record, first, threshold)
    if discovery.learn(known, record, first) and not wasVisible then showLearning() end
    learnGround(record, threshold)
end

local function effectDetails(effect, magic)
    local parts = {}
    if magic.hasMagnitude then
        local min, max = effect.magnitudeMin, effect.magnitudeMax
        parts[#parts + 1] = (min == max and tostring(min) or min .. '–' .. max) .. ' pts'
    end
    if magic.hasDuration then parts[#parts + 1] = effect.duration .. ' s' end
    return table.concat(parts, ' · ')
end

local function describeEffects(product, before, visible)
    local rows, previous = {}, {}
    for _, effect in ipairs(before or {}) do previous[brewing.effectKey(effect)] = effect end
    for _, effect in ipairs(product.effects) do
        local key = brewing.effectKey(effect)
        local magic = core.magic.effects.records[effect.id]
        if magic then
            local details = effectDetails(effect, magic)
            local old = previous[key]
            if old then
                local oldDetails = effectDetails(old, magic)
                if oldDetails ~= details then details = oldDetails .. ' → ' .. details end
            end
            local knownEffect = not visible or visible[key]
            rows[#rows + 1] = {
                name = knownEffect and effectName(effect, magic) or '?',
                details = knownEffect and details or '',
                icon = knownEffect and magic.icon or nil,
                harmful = knownEffect and magic.harmful,
            }
        end
        previous[key] = nil
    end
    for _, effect in ipairs(before or {}) do
        if previous[brewing.effectKey(effect)] then
            rows[#rows + 1] = { name = effectName(effect), details = 'Removed', icon = effect.effect.icon, removed = true }
        end
    end
    return rows
end

local function updateRecipe()
    local count, used, visible = #menu.selected, {}, {}
    menu.maxCount = count == 0 and 0 or menu.definition.maxBatch or math.huge
    for _, choice in ipairs(menu.selected) do
        used[choice.recipeKey] = (used[choice.recipeKey] or 0) + 1
        menu.maxCount = math.min(menu.maxCount, math.floor(choice.count / used[choice.recipeKey]))
        for key in pairs(choice.visibleKeys) do visible[key] = true end
    end
    menu.used, menu.visible = used, visible
    menu.count = math.max(1, math.min(menu.count, menu.maxCount))
    menu.canCreate, menu.previewRows, menu.scroll.preview = false, {}, 0
    if count < menu.definition.minimum then
        menu.preview = menu.kind == 'retort' and 'Choose two or three ingredients that share an effect.'
            or menu.kind == 'mortar' and 'Choose an ingredient to grind.' or 'Choose a potion.'
        return
    end

    if menu.kind == 'mortar' then
        menu.canCreate = true
        menu.preview = 'Result: ' .. menu.selected[1].output.name
        return
    end

    local product, before, sideEffect
    if menu.kind == 'retort' then
        local records = {}
        for i, choice in ipairs(menu.selected) do records[i] = choice.record end
        local shared, uncommon = brewing.match(records)
        if #shared == 0 then
            menu.preview = 'These ingredients share no brewable effects.'
            return
        end
        product = brewing.retortProduct(shared, menu.stats, menu.quality)
        local chance = brewing.chance(menu.stats)
        sideEffect = chance >= 1 and chance < 100 and #brewing.sideEffects(shared, uncommon) > 0
    else
        local inputs = {}
        for i, choice in ipairs(menu.selected) do inputs[i] = choice.effects end
        product, menu.preview = apparatus.refine(menu.kind, inputs, menu.stats, menu.quality, menu.operation)
        if not product then return end
        before = inputs[1]
    end

    menu.canCreate = true
    local title = #product.effects > 0 and 'Expected on success' or 'All effects removed'
    if #product.effects > 0 and not special.apply(product) and menu.standard and #product.effects == 1 then
        local effect = product.effects[1]
        local magic = core.magic.effects.records[effect.id]
        local recordId = magic and brewing.standardPotion(types.Potion.records, effect, magic)
        if recordId then
            product = types.Potion.records[recordId]
            if not menu.discover or visible[brewing.effectKey(effect)] then title = product.name end
        else
            title = 'No standard match · custom result'
        end
    elseif menu.standard and #product.effects > 1 and not product.fixedName then
        title = 'Multiple effects · custom result'
    end
    menu.preview = sideEffect and (title .. ' · Side effect possible') or title
    menu.previewRows = describeEffects(product, before, menu.discover and visible or nil)
end

local function createPanel(widgets, width, height)
    local current = menu
    local window = {
        type = ui.TYPE.Container,
        template = interfaces.MWUI.templates.boxSolidThick,
        props = { relativePosition = vec(0.5, 0.5), anchor = vec(0.5, 0.5) },
        content = ui.content({
            { props = { size = vec(width, height) }, content = ui.content(widgets) },
        }),
    }
    return ui.create({
        layer = 'Windows',
        props = { relativeSize = vec(1, 1) },
        content = ui.content({ window }),
        -- OpenMW 0.51 reports the wheel through the player handler, without a cursor position.
        events = { mouseMove = async:callback(function()
            if menu == current then menu.hoveredList = nil end
        end) },
    })
end

local draw

local function scrollTo(key, offset)
    offset = math.max(0, math.min(offset, menu.scrollLimits[key]))
    if menu.scroll[key] ~= offset then
        menu.scroll[key] = offset
        menu.redraw()
    end
end

local function scrollList(widgets, key, x, y, width, height, rows, rowHeight, makeRow)
    local current = menu
    local visible = math.max(1, math.floor(height / rowHeight))
    local limit = math.max(0, #rows - visible)
    local offset = math.min(menu.scroll[key], limit)
    menu.scroll[key], menu.scrollLimits[key] = offset, limit
    local rowWidth = limit > 0 and width - 14 or width
    local contents = {}
    for i = offset + 1, math.min(#rows, offset + visible) do
        contents[#contents + 1] = makeRow(rows[i], (i - offset - 1) * rowHeight, rowWidth)
    end
    if limit > 0 then
        white = white or ui.texture { path = 'white' }
        local thumbHeight = math.max(15, math.floor(height * visible / #rows))
        local travel = height - thumbHeight
        local thumbY = math.floor(travel * offset / limit)
        local function move(yPosition)
            scrollTo(key, math.floor((yPosition - menu.scrollGrab) / travel * limit + 0.5))
        end
        contents[#contents + 1] = {
            type = ui.TYPE.Image,
            props = { resource = white, position = vec(width - 10, 0), size = vec(10, height), color = trackColor },
            content = ui.content({
                { type = ui.TYPE.Image, props = {
                    resource = white, position = vec(1, thumbY), size = vec(8, thumbHeight), color = muted,
                } },
            }),
            events = {
                mousePress = async:callback(function(event)
                    if menu ~= current or event.button ~= 1 then return end
                    local yPosition = event.offset.y
                    if yPosition >= thumbY and yPosition < thumbY + thumbHeight then
                        menu.scrollGrab = yPosition - thumbY
                    else
                        menu.scrollGrab = thumbHeight / 2
                        move(yPosition)
                    end
                end),
                mouseMove = async:callback(function(event)
                    if menu == current and event.button == 1 and menu.scrollGrab then move(event.offset.y) end
                    return true
                end),
                mouseRelease = async:callback(function()
                    if menu == current then menu.scrollGrab = nil end
                end),
            },
        }
    end
    widgets[#widgets + 1] = {
        props = { position = vec(x, y), size = vec(width, height) },
        content = ui.content(contents),
        events = {
            mouseMove = async:callback(function()
                if menu == current then menu.hoveredList = key end
            end),
        },
    }
end

local function addImage(widgets, path, x, y, size)
    local image = icon(path, x, y, size)
    if image then widgets[#widgets + 1] = image end
    return image
end

local function firstMatch(choice, keys)
    for _, effect in ipairs(choice.effects) do
        local key = brewing.effectKey(effect)
        if choice.visibleKeys[key] and keys[key] then return effect end
    end
end

local function indexChoices(choices, discover, threshold)
    local byKey, effects = {}, {}
    for _, choice in ipairs(choices) do
        local search = { choice.record.name:lower() }
        choice.visibleKeys = {}
        for _, effect in ipairs(choice.effects) do
            local key = brewing.effectKey(effect)
            if not choice.visibleKeys[key] and (not discover or discovery.visible(known, choice.record, effect, threshold)) then
                choice.visibleKeys[key] = true
                local name = effectName(effect)
                search[#search + 1] = name:lower()
                local entry = byKey[key]
                if not entry then
                    entry = { key = key, name = name, icon = effect.effect.icon, sources = {}, count = 0 }
                    byKey[key], effects[#effects + 1] = entry, entry
                end
                if not entry.sources[choice.recipeKey] then
                    entry.sources[choice.recipeKey] = true
                    entry.count = entry.count + 1
                end
            end
        end
        choice.search = table.concat(search, '\n')
    end
    table.sort(effects, function(a, b)
        if a.name == b.name then return a.key < b.key end
        return a.name < b.name
    end)
    return effects
end

local function buildChoices(definition)
    local choices, byId = {}, {}
    for _, stack in ipairs(types.Actor.inventory(self):getAll(definition.input)) do
        local id = stack.recordId
        local choice = byId[id]
        if choice == nil then
            local record = definition.input.record(stack)
            local output = definition.output and definition.output(record)
            local effects = definition.effects(record)
            choice = false
            if output or (not definition.output and #effects > 0) then
                choice = {
                    record = record, output = output, effects = effects, count = 0,
                    sortName = record.name:lower(),
                    recipeKey = definition.recipeKey and definition.recipeKey(record) or id,
                }
                choices[#choices + 1] = choice
            end
            byId[id] = choice
        end
        if choice then choice.count = choice.count + stack.count end
    end
    table.sort(choices, function(a, b)
        if a.sortName == b.sortName then return a.record.id < b.record.id end
        return a.sortName < b.sortName
    end)
    return choices, byId
end

local function matchesSearch(choice)
    for _, term in ipairs(menu.queryTerms) do
        if not choice.search:find(term, 1, true) then return false end
    end
    return true
end

local function availableChoices()
    local results = {}
    for _, choice in ipairs(menu.choices) do
        if (not menu.filter or choice.visibleKeys[menu.filter])
            and matchesSearch(choice)
            and (not menu.matchOnly or #menu.selected == 0 or menu.used[choice.recipeKey]
                or firstMatch(choice, menu.visible)) then
            results[#results + 1] = choice
        end
    end
    return results
end

local function changeSelection()
    menu.help, menu.recipeName = false, nil
    updateRecipe()
    draw()
end

local function selectChoice(choice)
    local definition = menu.definition
    if definition.slots == 1 then
        menu.selected[1] = menu.selected[1] ~= choice and choice or nil
    elseif definition.allowRepeated then
        if #menu.selected == definition.slots or (menu.used[choice.recipeKey] or 0) >= choice.count then return end
        menu.selected[#menu.selected + 1] = choice
    else
        for i, selected in ipairs(menu.selected) do
            if selected == choice then
                table.remove(menu.selected, i)
                changeSelection()
                return
            end
        end
        if #menu.selected == definition.slots or menu.used[choice.recipeKey] then return end
        menu.selected[#menu.selected + 1] = choice
    end
    if menu.discover and learnGround(choice.record, menu.threshold) then
        menu.effects = indexChoices(menu.choices, menu.discover, menu.threshold)
    end
    changeSelection()
end

local function inputRow(choice, y, width)
    local selected = false
    for _, current in ipairs(menu.selected) do
        if current == choice then selected = true; break end
    end
    local used = menu.used[choice.recipeKey] or 0
    local definition = menu.definition
    local active = definition.slots == 1
        or (definition.allowRepeated and #menu.selected < definition.slots and used < choice.count)
        or (not definition.allowRepeated and (selected or (#menu.selected < definition.slots and used == 0)))
    local count = '×' .. choice.count
    local height = menu.layout.itemRowHeight
    local contents = {
        label(choice.record.name, 33, 1, width - 40, {
            height = height - 25, wrap = true, color = selected and accent or not active and muted or nil,
        }),
        label(count, width - 52, height - 27, 45, { center = true, color = muted }),
    }
    addImage(contents, choice.record.icon, 4, 13, 23)
    local shown = {}
    local xEffect = 8
    for _, effect in ipairs(choice.effects) do
        if xEffect + 15 > width - 52 then break end
        local key = brewing.effectKey(effect)
        if not shown[key] then
            shown[key] = true
            local visible = choice.visibleKeys[key]
            local matches = visible and menu.visible[key] and not selected
            local image = visible and addImage(contents, effect.effect.icon, xEffect, height - 23, 15)
            if image then
                image.props.alpha = (#menu.selected == 0 or selected or matches) and 1 or 0.5
            else
                contents[#contents + 1] = label(visible and '•' or '?', xEffect, height - 27, 16, {
                    color = matches and matching or muted, center = true,
                })
            end
            xEffect = xEffect + 19
        end
    end
    return {
        type = ui.TYPE.Widget, template = interfaces.MWUI.templates.borders,
        props = { position = vec(0, y), size = vec(width, height - 3) }, content = ui.content(contents),
        events = active and { mouseClick = click(function() selectChoice(choice) end) } or nil,
    }
end

local function recipeColumn(widgets, width)
    local function add(widget) widgets[#widgets + 1] = widget end
    local x = 12
    if menu.help then
        add(label(l10n(menu.kind .. 'Help'), x, 45, width, { height = menu.layout.height - 95, wrap = true }))
        return
    end
    add(label('Selected', x, 45, width - 70, { header = true }))
    add(button('Clear', x + width - 63, 44, 63, #menu.selected > 0 and function()
        menu.selected = {}
        changeSelection()
    end))
    local slotHeight = menu.layout.slotHeight
    for i = 1, menu.definition.slots do
        local choice = menu.selected[i]
        local name = choice and (choice.record.name .. '  ×') or 'Choose from the list'
        add(button(name, x, 73 + (i - 1) * slotHeight, width, choice and function()
            table.remove(menu.selected, i)
            changeSelection()
        end, choice ~= nil, slotHeight - 2))
    end

    local controlY = 76 + slotHeight * menu.definition.slots
    if menu.definition.modes then
        add(button(menu.definition.modes[menu.operation], x, controlY, width, function()
            menu.operation = 3 - menu.operation
            changeSelection()
        end))
    elseif menu.kind == 'retort' then
        local text = string.format('Bottles  %d / %d', menu.bottles, menu.count)
        add(label(text, x, controlY + 1, width, { color = menu.bottles < menu.count and harmful or muted }))
    end

    local batchY = controlY + (menu.kind == 'mortar' and 0 or 28)
    add(label('Batch', x, batchY + 1, 43))
    add(button('−', x + 45, batchY, 25, menu.count > 1 and function() menu.count = menu.count - 1; draw() end))
    add(label(menu.count, x + 72, batchY + 1, width - 156, { center = true }))
    add(button('+', x + width - 81, batchY, 25, menu.count < menu.maxCount and function()
        menu.count = menu.count + 1; draw()
    end))
    add(button('Max', x + width - 51, batchY, 51, menu.count < menu.maxCount and function()
        menu.count = menu.maxCount; draw()
    end))

    local previewY = batchY + 29
    local previewHeight = menu.layout.height - 43 - previewY
    local preview = { { title = menu.preview } }
    for _, row in ipairs(menu.previewRows) do preview[#preview + 1] = row end
    scrollList(widgets, 'preview', x, previewY, width, previewHeight, preview, 62,
        function(row, y, rowWidth)
            if row.title then
                return label(row.title, 0, y, rowWidth, { height = 60, wrap = true, color = accent })
            end
            local color = row.removed and muted or row.harmful and harmful or nil
            local text = row.details ~= '' and row.name .. '\n' .. row.details or row.name
            local contents = { label(text, 23, 0, rowWidth - 23, { height = 60, wrap = true, color = color }) }
            addImage(contents, row.icon, 0, 20, 18)
            return { props = { position = vec(0, y), size = vec(rowWidth, 60) }, content = ui.content(contents) }
        end)
end

local function drawLists(widgets)
    local layout = menu.layout
    local function add(widget) widgets[#widgets + 1] = widget end
    local bottom = layout.height - 44
    local x, width = layout.inputX, layout.inputWidth
    local matchingWidth = math.min(94, math.floor(width * 0.48))
    add(label(menu.definition.inputLabel, x, 79, width - matchingWidth))
    if menu.definition.slots > 1 then
        add(button('Matches', x + width - matchingWidth, 76, matchingWidth, function()
            menu.matchOnly, menu.scroll.items = not menu.matchOnly, 0
            draw()
        end, menu.matchOnly))
    end
    local choices = availableChoices()
    scrollList(widgets, 'items', x, 109, width, bottom - 109, choices, layout.itemRowHeight, inputRow)
    if #choices == 0 then
        local message = menu.kind == 'mortar' and not types.Ingredient.records['ingred_diamond_g']
            and 'Enable The Art of Alchemy.ESP for ground ingredients.' or 'No matching items.'
        add(label(message, x, 109, width, { height = 60, wrap = true, color = muted }))
    end
    x, width = layout.effectsX, layout.effectsWidth
    add(label('Effects', x, 45, width - 46, { header = true }))
    add(button('All', x + width - 43, 44, 43, function()
        menu.filter, menu.scroll.items = nil, 0
        draw()
    end, not menu.filter))
    local filters = {}
    for _, entry in ipairs(menu.effects) do
        if favorites[entry.key] then filters[#filters + 1] = entry end
    end
    for _, entry in ipairs(menu.effects) do
        if not favorites[entry.key] then filters[#filters + 1] = entry end
    end
    scrollList(widgets, 'effects', x, 76, width, bottom - 76, filters, 61,
        function(entry, y, rowWidth)
            local filterWidth = rowWidth - 43
            local contents = {
                label(entry.name, 25, 0, filterWidth - 31, { height = 54, wrap = true,
                    color = menu.filter == entry.key and accent or nil }),
                label(entry.count, 1, 27, 23, { color = muted, center = true }),
            }
            addImage(contents, entry.icon, 4, 10, 16)
            local filter = {
                type = ui.TYPE.Widget, template = interfaces.MWUI.templates.borders,
                props = { size = vec(filterWidth, 58) }, content = ui.content(contents),
                events = { mouseClick = click(function()
                    menu.filter = menu.filter ~= entry.key and entry.key or nil
                    menu.scroll.items = 0
                    draw()
                end) },
            }
            local pin = button('Pin', rowWidth - 40, 16, 40, function()
                favorites[entry.key] = not favorites[entry.key] or nil
                if favorites[entry.key] then menu.scroll.effects = 0 end
                draw()
            end, favorites[entry.key])
            return {
                props = { position = vec(0, y), size = vec(rowWidth, 58) },
                content = ui.content({ filter, pin }),
            }
        end)
    if #filters == 0 then
        add(label(menu.discover and 'No known effects' or 'No usable effects', x, 77, width, { color = muted }))
    end
end

local function selectedIds()
    local ids = {}
    for i, choice in ipairs(menu.selected) do ids[i] = choice.record.id end
    return ids
end

local function setSubmenu(submenu)
    if menu.recipeField then
        menu.recipeField:destroy()
        menu.recipeField = nil
    end
    menu.submenu, menu.hoveredList, menu.scrollGrab = submenu, nil, nil
    menu.searchPanel.layout.props.visible = submenu == nil
    menu.searchPanel:update()
    if submenu == 'recipes' then
        menu.recipes = recipeSection:getCopy('recipes') or {}
        menu.scroll.recipes, menu.recipeMessage, menu.deleteRecipe = 0, nil, nil
        if menu.canCreate then
            menu.recipeField = ui.create({
                template = interfaces.MWUI.templates.textEditLine,
                props = { position = vec(122, 0), size = vec(menu.layout.width - 259, 26),
                    text = menu.recipeName or '', textSize = menu.textSize, textAlignV = ui.ALIGNMENT.Center,
                    autoSize = false },
                events = { textChanged = async:callback(function(value)
                    if menu and menu.recipeField then menu.recipeField.layout.props.text = value end
                end) },
            })
        end
    end
    draw()
end

local function saveRecipe()
    local name = brewing.customName(menu.recipeField.layout.props.text)
    if not name then
        menu.recipeMessage = 'Enter a recipe name. Shorten it if it is too long.'
        draw()
        return
    end
    for _, recipe in ipairs(menu.recipes) do
        if recipe.name:lower() == name:lower() then
            menu.recipeMessage = 'A recipe with that name already exists.'
            draw()
            return
        end
    end
    menu.recipes[#menu.recipes + 1] = {
        name = name, ids = selectedIds(), bottle = menu.bottle, standard = menu.standard,
    }
    table.sort(menu.recipes, function(a, b) return a.name:lower() < b.name:lower() end)
    recipeSection:set('recipes', menu.recipes)
    menu.recipeName = name
    setSubmenu(nil)
end

local function loadRecipe(recipe)
    local selected, records, used = {}, {}, {}
    for i, id in ipairs(recipe.ids) do
        local choice = menu.choicesById[id]
        if not choice then
            local record = types.Ingredient.records[id]
            menu.recipeMessage = 'Missing or unavailable ingredient: ' .. (record and record.name or id)
            draw()
            return
        end
        if used[choice.recipeKey] then
            menu.recipeMessage = 'This recipe needs different ingredients with the current load order.'
            draw()
            return
        end
        selected[i], records[i], used[choice.recipeKey] = choice, choice.record, true
    end
    if #brewing.match(records) == 0 then
        menu.recipeMessage = 'These ingredients no longer share a brewable effect.'
        draw()
        return
    end

    menu.selected, menu.count, menu.standard = selected, 1, recipe.standard
    menu.recipeName, menu.bottle, menu.help = recipe.name, 'random', false
    for _, option in ipairs(appearance.options()) do
        if option.style == recipe.bottle then menu.bottle = recipe.bottle end
    end
    if menu.discover then
        local changed = false
        for _, choice in ipairs(selected) do
            if learnGround(choice.record, menu.threshold) then changed = true end
        end
        if changed then menu.effects = indexChoices(menu.choices, menu.discover, menu.threshold) end
    end
    updateRecipe()
    setSubmenu(nil)
end

local function drawRecipes(widgets, width, footerY)
    widgets[#widgets + 1] = label('Saved recipes', 12, 10, width - 24, { header = true })
    if menu.recipeField then
        widgets[#widgets + 1] = {
            template = interfaces.MWUI.templates.borders,
            props = { position = vec(12, 44), size = vec(width - 24, 30) },
            content = ui.content({
                label('Recipe name', 8, 0, 109, { color = muted, height = 26 }),
                menu.recipeField,
                button('Save mixture', width - 141, 0, 114, saveRecipe),
            }),
        }
    end
    if #menu.recipes == 0 then
        widgets[#widgets + 1] = label('No saved recipes.', 12, 85, width - 24, { color = muted })
    end
    scrollList(widgets, 'recipes', 12, 85, width - 24, footerY - 121, menu.recipes, 59,
        function(recipe, y, rowWidth)
            local names = {}
            for i, id in ipairs(recipe.ids) do
                local record = types.Ingredient.records[id]
                names[i] = record and record.name or id
            end
            local confirm = menu.deleteRecipe == recipe
            local contents = {
                button(recipe.name .. '\n' .. table.concat(names, ' + '), 0, 0, rowWidth - 86,
                    function() loadRecipe(recipe) end, false, 55),
                button(confirm and 'Confirm' or 'Delete', rowWidth - 79, 13, 79, function()
                    if confirm then
                        for i, saved in ipairs(menu.recipes) do
                            if saved == recipe then table.remove(menu.recipes, i); break end
                        end
                        recipeSection:set('recipes', menu.recipes)
                        menu.deleteRecipe = nil
                    else
                        menu.deleteRecipe = recipe
                    end
                    menu.recipeMessage = nil
                    draw()
                end, confirm),
            }
            return { props = { position = vec(0, y), size = vec(rowWidth, 55) }, content = ui.content(contents) }
        end)
    if menu.recipeMessage then
        widgets[#widgets + 1] = label(menu.recipeMessage, 12, footerY - 32, width - 24,
            { height = 29, wrap = true, color = harmful })
    end
end

local function drawBottles(widgets, width)
    widgets[#widgets + 1] = label('Potion bottle', 12, 10, width - 24, { header = true })
    widgets[#widgets + 1] = label('Appearance for custom retort potions', 12, 46, width - 24, { color = muted })
    widgets[#widgets + 1] = button('Random', 12, 82, 83, function()
        menu.bottle = 'random'
        setSubmenu(nil)
    end, menu.bottle == 'random', 50)
    for i, option in ipairs(appearance.options()) do
        local x = 106 + (i - 1) * 61
        local choice = button('', x, 82, 50, function()
            menu.bottle = option.style
            setSubmenu(nil)
        end, false, 50)
        choice.content = ui.content({ icon(option.icon, 9, 9, 32) })
        widgets[#widgets + 1] = choice
        widgets[#widgets + 1] = label(option.style:sub(1, 1):upper() .. option.style:sub(2), x - 5, 135, 60,
            { center = true, color = menu.bottle == option.style and accent or muted })
    end
end

draw = function()
    local width = menu.layout.width
    local footerY = menu.layout.height - 38
    local widgets = { label(menu.title, 52, 10, width - 144, { header = true }) }
    local function add(widget) widgets[#widgets + 1] = widget end
    if menu.submenu then
        widgets = { button('Back', 12, footerY, 78, function() setSubmenu(nil) end) }
        if menu.submenu == 'recipes' then drawRecipes(widgets, width, footerY) else drawBottles(widgets, width) end
        workspacePanel.layout.content = ui.content(widgets)
        workspacePanel:update()
        return
    end
    addImage(widgets, menu.icon, 12, 7, 32)
    if settings.read(settingSection, 'tutorial') then
        add(button('Help', width - 73, 9, 61, function()
            menu.help = not menu.help
            if menu.help then menu.scrollLimits.preview = 0 end
            draw()
        end, menu.help))
    end
    recipeColumn(widgets, menu.layout.recipeWidth)
    drawLists(widgets)

    if menu.canPickUp then add(button('Take', 12, footerY, 58, function() sendAction('PickUp', nil, true) end)) end
    if menu.kind ~= 'mortar' then
        add(button(menu.standard and 'Standard' or 'Custom', 78, footerY, 90, function()
            menu.standard = not menu.standard
            menu.help = false
            updateRecipe()
            draw()
        end, menu.standard))
    end
    if menu.kind == 'retort' then
        add(button('Recipes', 174, footerY, 63, function() setSubmenu('recipes') end, menu.recipeName ~= nil))
        if #appearance.options() > 0 then
            add(button('Bottle', 243, footerY, 51, function() setSubmenu('bottles') end, menu.bottle ~= 'random'))
        end
    end
    add(button('Close', width - 185, footerY, 78, function() sendAction('Close', nil, true) end))
    add(button(menu.definition.action, width - 100, footerY, 88, menu.canCreate and function()
        sendAction('Start', {
            ids = selectedIds(), count = menu.count, mode = menu.operation,
            standard = menu.standard or input.isCtrlPressed(),
            bottle = menu.bottle, recipeName = menu.recipeName,
        }, true)
    end, menu.canCreate))
    workspacePanel.layout.content = ui.content(widgets)
    workspacePanel:update()
end

local function setSearch(value)
    if not menu or naming then return end
    menu.queryTerms = {}
    for term in value:lower():gmatch('%S+') do menu.queryTerms[#menu.queryTerms + 1] = term end
    menu.scroll.items = 0
    draw()
end

local function openApparatus(data)
    if menu or interfaces.UI.getMode() then return end
    local kind = data.kind or 'retort'
    local definition = apparatus[kind]
    if not definition then return end
    hideProgress()
    local discover = definition.input == types.Ingredient and settings.read(settingSection, 'discovery')
    local threshold = discover and discovery.threshold(self) or 4
    local layer = ui.layers[ui.layers.indexOf('Windows')]
    local width = math.min(800, math.max(484, layer.size.x - 22))
    local height = math.min(490, math.max(382, layer.size.y - 18))
    local textSize = math.min(interfaces.MWUI.templates.textNormal.props.textSize, math.floor(width / 33))
    local recipeWidth = math.floor(width * 0.31)
    local effectsWidth = math.floor(width * 0.29)
    local inputX, effectsX = recipeWidth + 24, width - effectsWidth - 12
    menu = {
        discover = discover, threshold = threshold,
        title = data.name, icon = data.icon, retort = data.retort, canPickUp = data.canPickUp,
        kind = kind, definition = definition, operation = 1, textures = {},
        stats = apparatus.stats(self),
        quality = apparatus.quality(types.Apparatus.record(data.retort), settings.read(settingSection, 'apparatusBalance')),
        bottles = kind == 'retort' and bottleInventory.plan(types.Actor.inventory(self)) or nil,
        selected = {}, count = 1, queryTerms = {}, standard = false, textSize = textSize,
        bottle = kind == 'retort' and 'random' or nil,
        scroll = { items = 0, effects = 0, preview = 0 }, scrollLimits = {},
        redraw = draw,
        layout = { width = width, height = height, recipeWidth = recipeWidth, inputX = inputX,
            inputWidth = effectsX - inputX - 13, effectsX = effectsX, effectsWidth = effectsWidth,
            itemRowHeight = width < 715 and 86 or 66, slotHeight = width < 715 and height >= 430 and 62 or 42 },
    }
    menu.choices, menu.choicesById = buildChoices(definition)
    menu.effects = indexChoices(menu.choices, discover, threshold)
    updateRecipe()
    workspacePanel = ui.create({ props = { size = vec(width, height) }, content = ui.content({}) })
    local searchWidth = menu.layout.inputWidth
    menu.searchField = ui.create({
        template = interfaces.MWUI.templates.textEditLine,
        props = {
            position = vec(66, 0), size = vec(searchWidth - 102, 26), text = '',
            textSize = textSize, textAlignV = ui.ALIGNMENT.Center, autoSize = false,
        },
        events = { textChanged = async:callback(function(value)
            if not menu or naming then return end
            menu.searchField.layout.props.text = value
            setSearch(value)
        end) },
    })
    menu.searchPanel = ui.create({
        template = interfaces.MWUI.templates.borders,
        props = { position = vec(inputX, 42), size = vec(searchWidth, 30) },
        content = ui.content({
            label('Search', 5, 0, 50, { color = muted, height = 26 }),
            menu.searchField,
            button('×', searchWidth - 31, 0, 27, function()
                menu.searchField.layout.props.text = ''
                menu.searchField:update()
                setSearch('')
            end),
        }),
    })
    element = createPanel({ workspacePanel, menu.searchPanel }, width, height)
    draw()
    interfaces.UI.addMode(mode, { windows = {} })
end

local function finishNaming(name, removeMode, cancelled)
    local id = naming.id
    destroy()
    if removeMode then interfaces.UI.removeMode(mode) end
    core.sendGlobalEvent('ArtOfAlchemyRetort_Collect', {
        id = id, actor = self, name = name, cancelled = cancelled,
    })
end

local function openNaming(data)
    if naming then return end
    if menu or interfaces.UI.getMode() then
        core.sendGlobalEvent('ArtOfAlchemyRetort_Collect', { id = data.id, actor = self, cancelled = true })
        return
    end
    hideProgress()
    naming = { id = data.id, name = data.name }
    menu = { textures = {}, scroll = { naming = 0 }, scrollLimits = {} }
    local templates = interfaces.MWUI.templates
    local layer = ui.layers[ui.layers.indexOf('Windows')]
    local width = math.min(472, layer.size.x - 22)
    local amount = '×' .. data.count
    if data.count < data.total then amount = amount .. ' of ' .. data.total end
    local widgets = {
        label('Name potion', 50, 15, width - 165, { header = true }),
        label(amount, width - 134, 15, 118, { color = accent, center = true }),
        {
            template = templates.borders,
            props = { position = vec(16, 48), size = vec(width - 32, 32) },
            content = ui.content({
                {
                    template = templates.textEditLine,
                    props = {
                        position = vec(5, 0), size = vec(width - 46, 28), text = data.name,
                        textAlignV = ui.ALIGNMENT.Center, autoSize = false,
                    },
                    events = {
                        textChanged = async:callback(function(text) if naming then naming.name = text end end),
                    },
                },
            }),
        },
    }
    local image = icon(data.icon, 16, 10, 28)
    if image then widgets[#widgets + 1] = image end
    local rows = describeEffects({ effects = data.effects })
    local rowHeight = 51
    local visibleRows = math.max(1, math.floor((layer.size.y - 156) / rowHeight))
    local listHeight = math.min(#rows, visibleRows) * rowHeight
    local listWidth = width - 32
    workspacePanel = ui.create({
        props = { position = vec(16, 86), size = vec(listWidth, listHeight) },
        content = ui.content({}),
    })
    widgets[#widgets + 1] = workspacePanel
    menu.redraw = function()
        local list = {}
        if #rows > 0 then
            scrollList(list, 'naming', 0, 0, listWidth, listHeight, rows, rowHeight,
                function(row, y, rowWidth)
                    local text = row.details ~= '' and row.name .. '\n' .. row.details or row.name
                    local contents = { label(text, 27, 0, rowWidth - 27, {
                        height = 49, wrap = true, color = row.harmful and harmful or nil,
                    }) }
                    addImage(contents, row.icon, 1, 14, 21)
                    return { props = { position = vec(0, y), size = vec(rowWidth, 49) },
                        content = ui.content(contents) }
                end)
        end
        workspacePanel.layout.content = ui.content(list)
        workspacePanel:update()
    end

    local buttonY = 94 + listHeight
    widgets[#widgets + 1] = button('Use default', 16, buttonY, 114, function() finishNaming(nil, true) end)
    widgets[#widgets + 1] = button('Cancel', math.floor((width - 81) / 2), buttonY, 81,
        function() finishNaming(nil, true, true) end)
    widgets[#widgets + 1] = button('Collect', width - 130, buttonY, 114, function() finishNaming(naming.name, true) end)
    element = createPanel(widgets, width, buttonY + 40)
    menu.redraw()
    interfaces.UI.addMode(mode, { windows = {} })
end

return {
    eventHandlers = {
        ArtOfAlchemyRetort_Open = openApparatus,
        ArtOfAlchemyRetort_Name = openNaming,
        ArtOfAlchemyRetort_Progress = showProgress,
        ArtOfAlchemyRetort_Experience = function(data)
            local skill = interfaces.SkillProgression
            local useType = data.ground and skill.SKILL_USE_TYPES.Alchemy_UseIngredient
                or skill.SKILL_USE_TYPES.Alchemy_CreatePotion
            local gain = data.count * settings.experienceScale(settingSection)
            if gain > 0 then skill.skillUsed('alchemy', { useType = useType, scale = gain }) end
            if settings.read(settingSection, 'discovery') then
                local threshold = discovery.threshold(self)
                if data.ground then
                    local record = types.Ingredient.records[data.resultId]
                    if record then learnGround(record, threshold) end
                else
                    learnBrew(data, threshold)
                end
            end
        end,
        UiModeChanged = function(data)
            if data.newMode then hideProgress() end
            if not menu or data.oldMode ~= mode or data.newMode == mode then return end
            if naming then finishNaming(nil, false, true) else sendAction('Close') end
        end,
    },
    engineHandlers = {
        onInit = preferences,
        onLoad = function(state)
            destroy()
            hideProgress()
            known = state and state.known or {}
            favorites = state and state.favorites or {}
            preferences()
        end,
        onSave = function() return { known = known, favorites = favorites } end,
        onConsume = taste,
        onMouseWheel = function(vertical)
            if not menu or not menu.hoveredList or vertical == 0 then return end
            local key = menu.hoveredList
            scrollTo(key, menu.scroll[key] - vertical)
        end,
    },
}
