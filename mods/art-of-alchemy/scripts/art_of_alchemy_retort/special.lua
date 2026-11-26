local special = {}

local attributes = {
    'strength', 'endurance', 'agility', 'speed', 'intelligence', 'willpower', 'personality', 'luck',
}
local magnitudes = {}
for _, id in ipairs(attributes) do magnitudes[id] = id == 'luck' and 20 or 50 end

function special.apply(product)
    if #product.effects ~= #attributes then return false end
    local seen = {}
    for _, effect in ipairs(product.effects) do
        local id = effect.affectedAttribute
        if effect.id ~= 'fortifyattribute' or not magnitudes[id] or seen[id] then
            return false
        end
        seen[id] = true
    end

    local effects = {}
    for i, id in ipairs(attributes) do
        local magnitude = magnitudes[id]
        effects[i] = {
            id = 'fortifyattribute', affectedAttribute = id,
            duration = 150, magnitudeMin = magnitude, magnitudeMax = magnitude,
        }
    end
    product.name, product.effects = "Jack Of All Trades' Potion", effects
    product.fixedName, product.bottle, product.value, product.weight = true, 'exclusive', 2500, 2
    return true
end

return special
