local core = require('openmw.core')
local types = require('openmw.types')
local vfs = require('openmw.vfs')

-- OpenMW 0.51 uses these exact miscellaneous record IDs for currency.
local gold = { gold_001 = true, gold_005 = true, gold_010 = true, gold_025 = true, gold_100 = true }

-- Inventory Extender 1.1's type-wide scripts manage its UI and do not make
-- every item or container a quest/scripted reference.
local inventoryExtenderScripts = {
    ['scripts/inventoryextender/item.lua'] = true,
    ['scripts/inventoryextender/container.lua'] = true,
}

local itemTags = {
    ARMOR = true, BOOK = true, CLOTHING = true, INGREDIENT = true, LIGHT = true,
    MISC_ITEM = true, POTION = true, WEAPON = true, APPARATUS = true,
    LOCKPICK = true, PROBE = true, REPAIR = true,
}

local function luaScripts()
    local itemPaths, containerPaths = {}, {}
    for _, file in ipairs(core.contentFiles.list) do
        if file:lower():match('%.omwscripts$') then
            local handle = vfs.open(file)
            if handle then
                for line in handle:lines() do
                    local tags, path = line:match('^%s*([^#:%s][^:]*):%s*(.-)%s*$')
                    if path and path:lower():match('%.lua$') then
                        path = path:lower():gsub('\\', '/')
                        if not inventoryExtenderScripts[path] then
                            for tag in tags:gmatch('[A-Z_]+') do
                                if tag == 'CUSTOM' or itemTags[tag] then
                                    itemPaths[path] = true
                                end
                                if tag == 'CUSTOM' or tag == 'CONTAINER' then
                                    containerPaths[path] = true
                                end
                            end
                        end
                    end
                end
                handle:close()
            end
        end
    end
    return itemPaths, containerPaths
end

local function isScripted(object, record, paths)
    if record.mwscript and record.mwscript ~= '' then
        return true
    end
    for path in pairs(paths) do
        if object:hasScript(path) then
            return true
        end
    end
    return false
end

local function blacklistIds(setting)
    local ids = {}
    for id in setting:lower():gmatch('[^,\r\n]+') do
        id = id:match('^%s*(.-)%s*$')
        if id ~= '' then
            ids[id] = true
        end
    end
    return ids
end

local function belongsToSomeoneElse(object, player)
    local owner = object.owner
    return owner.factionId ~= nil or (owner.recordId ~= nil and owner.recordId ~= player.recordId)
end

local function targetError(target, player, record, blacklist, paths)
    if types.Lockable.isLocked(target) or types.Lockable.getTrapSpell(target) then
        return 'lockedOrTrapped'
    end
    if belongsToSomeoneElse(target, player) then
        return 'owned'
    end
    if record.isOrganic then
        return 'organic'
    end
    if record.isRespawning then
        return 'respawning'
    end
    if blacklist[target.recordId] or isScripted(target, record, paths) then
        return 'protectedContainer'
    end
    if types.Container.getCapacity(target) <= 0 then
        return 'noCapacity'
    end
end

return {
    gold = gold,
    luaScripts = luaScripts,
    isScripted = isScripted,
    blacklistIds = blacklistIds,
    belongsToSomeoneElse = belongsToSomeoneElse,
    targetError = targetError,
}
