local types = require('openmw.types')
local Categories = require('scripts.UniversalContainerSorter.categories')
local Protection = require('scripts.UniversalContainerSorter.protection')

local function inspectTarget(target, player, options)
    if not target:isValid() or not target.enabled or not target.cell or target.parentContainer then
        return nil, 'unavailable'
    end

    local record = types.Container.record(target)
    local blacklist = Protection.blacklistIds(options.blacklist)
    local itemPaths, containerPaths = Protection.luaScripts()
    local reason = Protection.targetError(target, player, record, blacklist, containerPaths)
    if reason then
        return nil, reason
    end

    local contents = types.Container.inventory(target)
    local matches = {}
    for _, item in ipairs(contents:getAll()) do
        matches[item.recordId] = true
    end

    local equipped = {}
    for _, item in pairs(types.Actor.getEquipment(player)) do
        equipped[item.id] = true
    end

    local snapshot = {
        name = record.name,
        weight = types.Container.getEncumbrance(target),
        capacity = types.Container.getCapacity(target),
        stacks = {},
        counts = {},
        quickCount = 0,
    }
    local sources = {}
    local inventory = types.Actor.inventory(player)
    for _, item in ipairs(inventory:getAll()) do
        local id, recordId = item.id, item.recordId
        if item.count > 0 and not equipped[id] and not options.favorites[id]
            and not Protection.gold[recordId] and not blacklist[recordId]
            and not types.Item.isRestocking(item) and types.Item.isCarriable(item)
        then
            local itemType = item.type
            local itemRecord = itemType.record and itemType.record(item)
            local category = itemRecord and Categories.classify(itemType, itemRecord)
            if category and (category ~= 'Keys' or options.allowKeys)
                and not Protection.isScripted(item, itemRecord, itemPaths)
                and not Protection.belongsToSomeoneElse(item, player)
            then
                local count = item.count
                local weight = itemRecord.weight
                if type(weight) == 'number' and weight == weight and weight < math.huge then
                    local stack = {
                        id = id,
                        count = count,
                        weight = math.max(0, weight) * count,
                        category = category,
                        matches = matches[recordId] == true,
                    }
                    snapshot.stacks[#snapshot.stacks + 1] = stack
                    snapshot.counts[category] = (snapshot.counts[category] or 0) + count
                    if stack.matches then
                        snapshot.quickCount = snapshot.quickCount + count
                    end
                    sources[id] = item
                end
            end
        end
    end
    return snapshot, nil, sources
end

return { inspectTarget = inspectTarget }
