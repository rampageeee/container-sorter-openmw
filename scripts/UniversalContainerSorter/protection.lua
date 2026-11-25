local core = require('openmw.core')
local types = require('openmw.types')
local vfs = require('openmw.vfs')

-- OpenMW 0.51 uses these exact miscellaneous record IDs for currency.
local gold = { gold_001 = true, gold_005 = true, gold_010 = true, gold_025 = true, gold_100 = true }

-- A type-wide autostart script is not evidence that a particular item or
-- container is special. Only check CUSTOM scripts on types to which that
-- script is not automatically attached. MWScript remains protected.
local typeTags = {
    [types.Armor] = 'ARMOR',
    [types.Book] = 'BOOK',
    [types.Clothing] = 'CLOTHING',
    [types.Container] = 'CONTAINER',
    [types.Ingredient] = 'INGREDIENT',
    [types.Light] = 'LIGHT',
    [types.Miscellaneous] = 'MISC_ITEM',
    [types.Potion] = 'POTION',
    [types.Weapon] = 'WEAPON',
    [types.Apparatus] = 'APPARATUS',
    [types.Lockpick] = 'LOCKPICK',
    [types.Probe] = 'PROBE',
    [types.Repair] = 'REPAIR',
}

local function luaScripts()
    local declarations = {}
    for _, file in ipairs(core.contentFiles.list) do
        if file:lower():match('%.omwscripts$') then
            local handle = vfs.open(file)
            if handle then
                for line in handle:lines() do
                    local tags, path = line:match('^%s*([^#:%s][^:]*):%s*(.-)%s*$')
                    if path and path:lower():match('%.lua$') then
                        path = path:lower():gsub('\\', '/')
                        local flags = {}
                        for tag in tags:gmatch('[A-Z_]+') do
                            flags[tag] = true
                        end
                        -- As in the engine, the last text declaration wins.
                        declarations[path] = flags.CUSTOM and flags or nil
                    end
                end
                handle:close()
            end
        end
    end
    return declarations
end

local function isScripted(object, record, paths)
    if record.mwscript and record.mwscript ~= '' then
        return 'MWScript: ' .. tostring(record.mwscript)
    end
    local tag = typeTags[object.type]
    for path, flags in pairs(paths) do
        if not flags[tag] and object:hasScript(path) then
            return 'CUSTOM Lua: ' .. path
        end
    end
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
    if blacklist[target.recordId] then
        return 'blacklistedContainer', 'Record ID: ' .. target.recordId
    end
    local script = isScripted(target, record, paths)
    if script then
        return 'scriptedContainer', script
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
