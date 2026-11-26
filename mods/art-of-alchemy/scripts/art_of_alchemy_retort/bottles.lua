local types = require('openmw.types')

local bottles = {}
local bottleIds = {
    misc_com_bottle_01 = true, misc_com_bottle_02 = true, misc_com_bottle_04 = true,
    misc_com_bottle_05 = true, misc_com_bottle_06 = true, misc_com_bottle_08 = true,
    misc_com_bottle_09 = true, misc_com_bottle_10 = true, misc_com_bottle_11 = true,
    misc_com_bottle_13 = true, misc_com_bottle_14 = true, misc_com_bottle_15 = true,
}

function bottles.plan(inventory, limit)
    local count, stacks = 0, {}
    for _, stack in ipairs(inventory:getAll(types.Miscellaneous)) do
        if bottleIds[stack.recordId] and stack.count > 0 then
            local amount = limit and math.min(limit - count, stack.count) or stack.count
            count = count + amount
            if limit then
                stacks[#stacks + 1] = { stack = stack, count = amount }
                if count == limit then break end
            end
        end
    end
    return count, stacks
end

return bottles
