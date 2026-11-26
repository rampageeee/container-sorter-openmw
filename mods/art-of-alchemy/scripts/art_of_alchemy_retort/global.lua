local async = require('openmw.async')
local core = require('openmw.core')
local interfaces = require('openmw.interfaces')
local types = require('openmw.types')
local world = require('openmw.world')

local appearance = require('scripts.art_of_alchemy_retort.appearance')
local apparatus = require('scripts.art_of_alchemy_retort.apparatus')
local bottleInventory = require('scripts.art_of_alchemy_retort.bottles')
local brewing = require('scripts.art_of_alchemy_retort.brewing')
local feedback = require('scripts.art_of_alchemy_retort.feedback')
local grinding = require('scripts.art_of_alchemy_retort.grinding')
local rules = require('scripts.art_of_alchemy_retort.rules')
local settings = require('scripts.art_of_alchemy_retort.settings')
local special = require('scripts.art_of_alchemy_retort.special')
local preferences = settings.defaults
local brewDuration = 60 * 60 -- In-game seconds, independent of batch size.

local jobs = {}
local jobsByRetort = {}
local generatedPotions = {}
local nextJob = 0
local session, namingJob

local function notify(actor, message)
    actor:sendEvent('ShowMessage', { message = message })
end

local function getApparatusRecord(retort)
    if not retort:isValid() or retort.type ~= types.Apparatus or retort.parentContainer
        or not retort.cell or not retort.enabled or retort.count < 1 then
        return nil
    end
    local record = types.Apparatus.record(retort)
    local kind = apparatus.kind(record)
    if kind and not record.mwscript then
        return record, kind
    end
end

local function canUse(retort, actor)
    local owner = retort.owner
    if owner.recordId and owner.recordId ~= actor.recordId then return false end
    if not owner.factionId then return true end
    local faction = owner.factionId
    if not core.factions.records[faction] or types.NPC.isExpelled(actor, faction) then return false end
    return types.NPC.getFactionRank(actor, faction) >= (owner.factionRank or 1)
end

local function canTake(retort, record)
    return not retort.owner.factionId and not record.id:match('_static$')
end

local function finishBatch(job)
    if job.complete then
        return
    end
    job.complete = true
    local ok, err = pcall(feedback.finish, job)
    if not ok then
        print('[Art of Alchemy Retort] Completion feedback: ' .. tostring(err))
    end
end

local function removeJob(job)
    jobs[job.id] = nil
    jobsByRetort[job.retort.id] = nil
end

local function getPotionRecordId(product)
    if product.standardId and types.Potion.records[product.standardId] then
        return product.standardId
    end

    local keyParts = { product.name, product.bottle, product.value, product.weight }
    for _, effect in ipairs(product.effects) do
        keyParts[#keyParts + 1] = brewing.effectKey(effect)
        keyParts[#keyParts + 1] = effect.duration
        keyParts[#keyParts + 1] = effect.magnitudeMin
        keyParts[#keyParts + 1] = effect.magnitudeMax
    end
    local key = table.concat(keyParts, '|')
    local id = generatedPotions[key]
    if id and types.Potion.records[id] then
        return id
    end

    local model, icon = appearance.paths(product.bottle)
    local record = world.createRecord(types.Potion.createRecordDraft({
        name = product.name,
        model = model,
        icon = icon,
        value = product.value,
        weight = product.weight,
        effects = product.effects,
        isAutocalc = false,
    }))
    generatedPotions[key] = record.id
    return record.id
end

local function needsBottles(job)
    -- 0.4.0 saved the ingredient IDs only for retort batches.
    return job.product and job.ingredientIds ~= nil
end

local function missingBottles(job, actor)
    notify(actor, string.format('%d potion(s) ready. Bring an empty Bottle for each potion you want to collect.',
        job.count))
end

local function collect(job, actor, customName, limit)
    local isGrinding = job.powderId ~= nil
    if not job.product and (not isGrinding or job.count == 0) then
        removeJob(job)
        notify(actor, isGrinding and 'Grinding yielded no usable powder.' or 'The batch spoiled.')
        return
    end

    local inventory = types.Actor.inventory(actor)
    local count, bottles = job.count, {}
    if needsBottles(job) then
        count, bottles = bottleInventory.plan(inventory, math.min(count, limit or count))
        if count == 0 then
            missingBottles(job, actor)
            return
        end
    end

    local ok, name, resultId = pcall(function()
        local product = job.product
        if product and customName and customName ~= product.name then
            local copy = {}
            for key, value in pairs(product) do copy[key] = value end
            copy.name = customName
            product = copy
        end
        local recordId = job.powderId or getPotionRecordId(product)
        local records = isGrinding and types.Ingredient.records or types.Potion.records
        local record = records[recordId]
        local result = world.createObject(recordId, count)
        result:moveInto(inventory)
        return record.name, record.id
    end)
    if not ok then
        print('[Art of Alchemy] Could not collect batch: ' .. tostring(name))
        notify(actor, 'Could not collect this batch. It is still in the apparatus.')
        return
    end
    -- The output is queued successfully and the bottle stacks were validated in this handler.
    for _, bottle in ipairs(bottles) do bottle.stack:remove(bottle.count) end
    job.count = job.count - count
    local verb = isGrinding and 'Ground' or 'Collected'
    local message = string.format('%s %d × %s.', verb, count, name)
    if job.count == 0 then
        removeJob(job)
    else
        job.bottled = true
        if customName then job.product.name = customName end
        message = message .. string.format(' %d still in the retort.', job.count)
    end
    notify(actor, message)
    actor:sendEvent('ArtOfAlchemyRetort_Experience', {
        count = count, ground = isGrinding, resultId = resultId, inputIds = job.ingredientIds,
    })
    feedback.playSound(isGrinding and 'item ingredient up' or 'item potion up', actor, 0.8)
end

local completion = async:registerTimerCallback('CompleteRetortBatch', function(id)
    local job = jobs[id]
    if not job then return end
    finishBatch(job)
    if job.powderId and world.players[1] then
        collect(job, world.players[1])
    end
end)

local function chooseCollection(job, actor)
    local product = job.product
    if preferences.naming and product and not product.standardId and not product.fixedName and not job.bottled then
        if namingJob then return end
        local count = needsBottles(job) and bottleInventory.plan(types.Actor.inventory(actor), job.count) or job.count
        if count == 0 then
            missingBottles(job, actor)
            return
        end
        namingJob = { id = job.id, count = count }
        actor:sendEvent('ArtOfAlchemyRetort_Name', {
            id = job.id, name = product.name, count = count, total = job.count, effects = product.effects,
            icon = appearance.icon(product.bottle),
        })
    else
        collect(job, actor)
    end
end

local function activate(retort, actor)
    if actor.type ~= types.Player then
        return
    end
    local record, kind = getApparatusRecord(retort)
    if not record then
        return
    end
    local jobId = jobsByRetort[retort.id]
    if jobId then
        local job = jobs[jobId]
        local remaining = job.readyAt - world.getGameTime()
        if job.complete or remaining <= 0 then
            finishBatch(job)
            chooseCollection(job, actor)
        else
            local ratio = 1 - remaining / (job.duration or brewDuration)
            actor:sendEvent('ArtOfAlchemyRetort_Progress', {
                activity = apparatus[kind].activity, ratio = math.max(0, math.min(1, ratio)),
            })
        end
        return false
    end
    if not canUse(retort, actor) then
        return
    end
    session = { retort = retort, actor = actor }
    actor:sendEvent('ArtOfAlchemyRetort_Open', {
        retort = retort, name = record.name, icon = record.icon,
        kind = kind, canPickUp = canTake(retort, record),
    })
    return false
end

interfaces.Activation.addHandlerForType(types.Apparatus, activate)

interfaces.ItemUsage.addHandlerForType(types.Apparatus, function(item, actor)
    if not preferences.preventVanilla or actor.type ~= types.Player then return end
    local record = types.Apparatus.record(item)
    if apparatus.kind(record) and not record.mwscript and not record.id:match('^apparatus_a_spipe_') then
        notify(actor, 'Place the apparatus in the world to use it.')
        return false
    end
end)

interfaces.ItemUsage.addHandlerForType(types.Ingredient, function(item, actor)
    if preferences.preventVanilla and actor.type == types.Player and rules.insoluble[item.recordId:lower()] then
        notify(actor, 'Grind this ingredient before consuming it.')
        return false
    end
end)

local function getSession(data)
    if not session or data.retort ~= session.retort or data.actor ~= session.actor then
        return nil
    end
    local retort, actor = session.retort, session.actor
    session = nil
    local record, kind = getApparatusRecord(retort)
    if record and not jobsByRetort[retort.id] and canUse(retort, actor) then
        return record, retort, actor, kind
    end
end

local function planInputs(inventory, definition, ids, count)
    local records, removals, requirements, used = {}, {}, {}, {}
    for _, id in ipairs(ids) do
        if type(id) ~= 'string' then
            return nil
        end
        local record = definition.input.records[id]
        if not record then return nil end
        local key = definition.recipeKey and definition.recipeKey(record) or record.id
        if used[key] and not definition.allowRepeated then return nil, nil, 'Choose different ingredients.' end
        used[key] = true
        records[#records + 1] = record
        requirements[record.id] = (requirements[record.id] or 0) + count
    end

    for id, required in pairs(requirements) do
        local remaining = required
        for _, stack in ipairs(inventory:findAll(id)) do
            local amount = math.min(stack.count, remaining)
            if amount > 0 then
                removals[#removals + 1] = { stack = stack, count = amount }
                remaining = remaining - amount
            end
            if remaining == 0 then
                break
            end
        end
        if remaining > 0 then
            return nil
        end
    end
    return records, removals
end

local function planProduct(kind, records, stats, quality, mode)
    if kind == 'retort' then
        local shared, uncommon = brewing.match(records)
        if #shared == 0 then return nil, 'The ingredients have no brewable effect in common.' end
        return brewing.roll(shared, uncommon, stats, quality, math.random)
    end

    local definition = apparatus[kind]
    local inputs = {}
    for i, record in ipairs(records) do inputs[i] = definition.effects(record) end
    local product, invalidRecipe = apparatus.refine(kind, inputs, stats, quality, mode)
    if not product then return nil, invalidRecipe end
    if #product.effects == 0 or math.random(1, 100) > brewing.chance(stats) then
        return nil
    end
    return product
end

local function nameProduct(product, actor, standard)
    local first = product.effects[1]
    local magic = core.magic.effects.records[first.id]
    local isSpecial = special.apply(product)
    if not isSpecial then product.name = magic.name .. ' Potion' end
    if standard and not isSpecial and #product.effects == 1 then
        product.standardId = brewing.standardPotion(types.Potion.records, first, magic)
        if not product.standardId then
            notify(actor, 'No standard potion of this strength matches. Creating a custom potion.')
        end
    elseif standard and not isSpecial then
        notify(actor, 'Standard potions require a single effect. Creating a custom potion.')
    end
    for _, effect in ipairs(product.effects) do
        effect.range = core.magic.RANGE.Self
    end
end

local function startBatch(data)
    local record, retort, actor, kind = getSession(data)
    if not record then
        return
    end
    local definition = apparatus[kind]
    local ids, count = data.ids, data.count
    if type(ids) ~= 'table' or #ids < definition.minimum or #ids > definition.slots
        or type(count) ~= 'number' or count < 1 or count % 1 ~= 0
        or (definition.maxBatch and count > definition.maxBatch) then
        return
    end
    local inventory = types.Actor.inventory(actor)
    local records, removals, inputError = planInputs(inventory, definition, ids, count)
    if not records then
        notify(actor, inputError or 'The required items are no longer available.')
        return
    end

    local stats = apparatus.stats(actor)
    local quality = apparatus.quality(record, preferences.apparatusBalance)
    local duration = preferences.brewMinutes * 60
    local job = { retort = retort, duration = duration, count = count }
    if kind == 'retort' then job.ingredientIds = ids end
    if kind == 'mortar' then
        local plan, message = grinding.plan(records[1], count, quality, stats, math.random)
        if not plan then
            notify(actor, message)
            return
        end
        job.powderId, job.count, job.duration = plan.powderId, plan.amount, plan.duration * duration / brewDuration
    else
        local product, message = planProduct(kind, records, stats, quality, data.mode)
        if message then
            notify(actor, message)
            return
        end
        if product then
            nameProduct(product, actor, data.standard)
            if kind == 'retort' and not product.standardId and not product.fixedName then
                product.name = brewing.customName(data.recipeName) or product.name
                if data.bottle then
                    product.bottle = appearance.choose(data.bottle, math.random) or product.bottle
                end
            end
        end
        job.product = product
    end

    nextJob = nextJob + 1
    job.id = nextJob
    job.readyAt = world.getGameTime() + job.duration
    for _, removal in ipairs(removals) do
        removal.stack:remove(removal.count)
    end
    jobs[job.id] = job
    jobsByRetort[retort.id] = job.id
    async:newGameTimer(job.duration, completion, job.id)
    if job.powderId then
        notify(actor, string.format('Grinding %d. Ready in %d game minutes.', count, math.ceil(job.duration / 60)))
        feedback.playSound('item ingredient down', retort, 0.7)
        return
    end
    notify(actor, string.format('%s %d. Ready in %d game minutes.', definition.activity, count, math.ceil(duration / 60)))
    local ok, fire = pcall(feedback.light, retort, kind)
    if ok then
        job.fire = fire
    else
        print('[Art of Alchemy] Apparatus fire: ' .. tostring(fire))
    end
end

return {
    eventHandlers = {
        ArtOfAlchemyRetort_Start = startBatch,
        ArtOfAlchemyRetort_Settings = function(data)
            local values = {}
            for key in pairs(settings.defaults) do values[key] = settings.value(key, data[key]) end
            preferences = values
        end,
        ArtOfAlchemyRetort_Collect = function(data)
            local job = jobs[data.id]
            if not job or not namingJob or data.id ~= namingJob.id or not job.complete or not job.product
                or not data.actor or data.actor.type ~= types.Player then return end
            local limit = namingJob.count
            namingJob = nil
            if data.cancelled then return end
            local name
            if not job.product.standardId and not job.product.fixedName then
                name = brewing.customName(data.name)
            end
            collect(job, data.actor, name, limit)
        end,
        ArtOfAlchemyRetort_PickUp = function(data)
            local record, retort, actor = getSession(data)
            if record and canTake(retort, record) then
                retort:moveInto(types.Actor.inventory(actor))
            end
        end,
        ArtOfAlchemyRetort_Close = function(data)
            getSession(data)
        end,
    },
    engineHandlers = {
        onSave = function()
            return { jobs = jobs, generatedPotions = generatedPotions, nextJob = nextJob }
        end,
        onLoad = function(state)
            state = state or {}
            jobs = state.jobs or {}
            generatedPotions = state.generatedPotions or {}
            nextJob = state.nextJob or 0
            jobsByRetort = {}
            session, namingJob = nil, nil
            for id, job in pairs(jobs) do
                jobsByRetort[job.retort.id] = id
            end
        end,
    },
}
