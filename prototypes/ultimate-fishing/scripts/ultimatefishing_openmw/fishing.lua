-- An OpenMW adaptation of Ultimate Fishing by Merlord, Greatness7 and Melchior Dahrk.
local fishing = {
    rodId = 'mer_fishing_pole_01',
    lureId = 'ufomw_lure_visual',
    eventPrefix = 'UltimateFishingOpenMW:',
}

-- A small selection of upstream catches for the first engine test.
local catches = {
    { id = 'mer_fish_slaughter_sm', name = 'Small slaughterfish', difficulty = 25, weight = 5 },
    { id = 'mer_fish_slaughter_l', name = 'Slaughterfish', difficulty = 50, weight = 2, minDepth = 100 },
    { id = 'mer_fish_mudcrab', name = 'Juvenile mudcrab', difficulty = 15, weight = 4, maxDepth = 300 },
    { id = 'mer_fish_goby', name = 'Goby', difficulty = 20, weight = 5, exterior = true, start = 6, stop = 19 },
    { id = 'mer_fish_salmon', name = 'Salmon', difficulty = 40, weight = 3, exterior = true,
        start = 6, stop = 19, minDepth = 100 },
}

fishing.catches = {}
for _, fish in ipairs(catches) do
    fishing.catches[fish.id] = fish
end

function fishing.chooseCatch(depth, hour, exterior)
    local pool, total = {}, 0
    for _, fish in ipairs(catches) do
        if depth >= (fish.minDepth or 0) and depth <= (fish.maxDepth or math.huge)
            and (exterior or not fish.exterior)
            and (not fish.start or (hour >= fish.start and hour < fish.stop)) then
            total = total + fish.weight
            pool[#pool + 1] = { limit = total, fish = fish }
        end
    end
    local roll = math.random(total)
    for _, entry in ipairs(pool) do
        if roll <= entry.limit then
            return entry.fish
        end
    end
end

function fishing.startFight(fish)
    return { tension = 0.5, progress = 0, elapsed = 0, strength = fish.difficulty / 100 }
end

function fishing.stepFight(fight, dt, reeling)
    fight.elapsed = fight.elapsed + dt
    local pull = 0.5 + 0.5 * math.sin(fight.elapsed * (2.3 + fight.strength))
    if reeling then
        fight.tension = fight.tension + (0.16 + pull * (0.14 + fight.strength * 0.14)) * dt
        fight.progress = fight.progress + (0.30 - fight.strength * 0.17) * (1 - pull * 0.42) * dt
    else
        fight.tension = fight.tension - (0.31 - pull * 0.15) * dt
        fight.progress = math.max(0, fight.progress - pull * 0.035 * dt)
    end

    if fight.tension >= 1 then return 'snapped' end
    if fight.tension <= 0 then return 'escaped' end
    if fight.progress >= 1 then return 'caught' end
end

return fishing
