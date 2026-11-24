local types = require('openmw.types')

local order = {
    'Weapons', 'Armor', 'Clothing', 'Potions', 'Ingredients',
    'Scrolls', 'Books', 'Keys', 'Tools', 'Miscellaneous',
}

local byType = {
    [types.Weapon] = 'Weapons',
    [types.Armor] = 'Armor',
    [types.Clothing] = 'Clothing',
    [types.Potion] = 'Potions',
    [types.Ingredient] = 'Ingredients',
    [types.Lockpick] = 'Tools',
    [types.Probe] = 'Tools',
    [types.Light] = 'Tools',
    [types.Apparatus] = 'Tools',
    [types.Repair] = 'Tools',
}

local function classify(itemType, record)
    if itemType == types.Book then
        -- Inventory Extender 1.1 uses enchantment to distinguish scrolls from books.
        return record.enchant and 'Scrolls' or 'Books'
    end
    if itemType == types.Miscellaneous then
        return record.isKey and 'Keys' or 'Miscellaneous'
    end
    return byType[itemType]
end

return { order = order, classify = classify }
