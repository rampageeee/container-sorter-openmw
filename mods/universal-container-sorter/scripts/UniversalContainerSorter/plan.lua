local function selectStacks(snapshot, quickStack, categories)
    local plan = { stacks = {}, eligible = 0, quantity = 0 }
    local weight = snapshot.weight
    for _, stack in ipairs(snapshot.stacks) do
        local selected = quickStack and stack.matches or not quickStack and categories[stack.category]
        if selected then
            plan.eligible = plan.eligible + stack.count
            local total = weight + stack.weight
            if total <= snapshot.capacity then
                plan.stacks[#plan.stacks + 1] = { id = stack.id, count = stack.count }
                plan.quantity = plan.quantity + stack.count
                weight = total
            end
        end
    end
    return plan
end

local function sameStacks(current, confirmed)
    if #current ~= #confirmed then
        return false
    end
    for index, stack in ipairs(current) do
        local previous = confirmed[index]
        if stack.id ~= previous.id or stack.count ~= previous.count then
            return false
        end
    end
    return true
end

return { selectStacks = selectStacks, sameStacks = sameStacks }
