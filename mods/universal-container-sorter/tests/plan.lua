local Plan = require('scripts.UniversalContainerSorter.plan')

local snapshot = {
    weight = 10,
    capacity = 15,
    stacks = {
        { id = 'a', count = 4, weight = 8, category = 'Ingredients', matches = true },
        { id = 'b', count = 2, weight = 2, category = 'Ingredients', matches = true },
        { id = 'c', count = 3, weight = 3, category = 'Tools', matches = false },
        { id = 'd', count = 1, weight = 0, category = 'Books', matches = true },
    },
}

local categoryPlan = Plan.selectStacks(snapshot, false, { Ingredients = true, Tools = true })
assert(categoryPlan.eligible == 9)
assert(categoryPlan.quantity == 5)
assert(Plan.sameStacks(categoryPlan.stacks, { { id = 'b', count = 2 }, { id = 'c', count = 3 } }))

local quickPlan = Plan.selectStacks(snapshot, true, { Tools = true })
assert(quickPlan.eligible == 7)
assert(quickPlan.quantity == 3)
assert(Plan.sameStacks(quickPlan.stacks, { { id = 'b', count = 2 }, { id = 'd', count = 1 } }))
assert(not Plan.sameStacks(quickPlan.stacks, categoryPlan.stacks))
assert(not Plan.sameStacks(quickPlan.stacks, { { id = 'b', count = 3 }, { id = 'd', count = 1 } }))
assert(not Plan.sameStacks(quickPlan.stacks, { { id = 'b', count = 2 } }))

local empty = Plan.selectStacks(snapshot, false, {})
assert(empty.eligible == 0 and empty.quantity == 0 and #empty.stacks == 0)

snapshot.weight = snapshot.capacity
local full = Plan.selectStacks(snapshot, true, {})
assert(full.eligible == 7 and full.quantity == 1 and full.stacks[1].id == 'd')
print('Transfer plan tests passed.')
