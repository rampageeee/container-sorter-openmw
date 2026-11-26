local async = require('openmw.async')
local core = require('openmw.core')
local types = require('openmw.types')
local world = require('openmw.world')

local secondsPerDay = 24 * 60 * 60
local messageEvent = 'PayTaxesTimerMessage'
local reminders = {
    [8] = 'within three days',
    [9] = 'within two days',
    [10] = 'before the day ends',
}
local timerGeneration = 0

local function showMessage(player, message, modal)
    player:sendEvent(messageEvent, { text = message, modal = modal })
end

local function updateTaxes(player)
    local globals = world.mwscript.getGlobalVariables()
    local day = globals.day
    if globals.w_taxes_timer_active ~= 1 or globals.w_taxes_timer_day == day then
        return
    end

    local level = types.Actor.stats.level(player).current
    local rate = globals.wm_eleccion_provisional
    if globals.wm_progressivetaxes == 1 then
        rate = math.min(250, 20 + level * 5)
    end

    local tax = level * rate
    local deposit = globals.w_impuestos_reserva
    local elapsed = globals.w_transcurso_dias + 1
    globals.w_impuestos_exigidos = tax
    globals.w_taxes_timer_day = day
    globals.w_transcurso_dias = elapsed

    local deadline = reminders[elapsed]
    if deadline then
        showMessage(player, ('You have to pay your taxes %s. You need to pay %d septims, and you have %d left in your deposit.'):format(deadline, tax, deposit), tax > deposit)
    end
    if elapsed ~= 11 then
        return
    end

    -- The old script normally counted the settlement date as day one of the next cycle.
    globals.w_transcurso_dias = 1
    if deposit < tax then
        local fine = tax + math.floor(tax / 4)
        types.Player.setCrimeLevel(player, types.Player.getCrimeLevel(player) + fine)
        if day == 1 then
            globals.w_transcurso_dias = 0
        end
        showMessage(player, "You haven't paid your taxes. Now you're a wanted criminal.")
    else
        local balance = deposit - tax
        globals.w_impuestos_reserva = balance
        showMessage(player, ('You have paid your taxes. The amount has been deducted from the money you had deposited at the Seyda Neen Census and Excise Office. In your tax reserve, there are %d septims.'):format(balance))
    end
end

local function scheduleMidnight(player, generation)
    -- Run just after midnight so the engine's Day global has already turned over.
    local delay = secondsPerDay - core.getGameTime() % secondsPerDay + 1
    async:newUnsavableGameTimer(delay, function()
        if generation ~= timerGeneration then
            return
        end
        scheduleMidnight(player, generation)
        updateTaxes(player)
    end)
end

return {
    engineHandlers = {
        onPlayerAdded = function(player)
            timerGeneration = timerGeneration + 1
            local generation = timerGeneration
            scheduleMidnight(player, generation)

            -- A save may have been made after the date changed but before
            -- the midnight callback ran. Wait for the world to resume.
            async:newUnsavableSimulationTimer(0.25, function()
                if generation == timerGeneration then
                    updateTaxes(player)
                end
            end)
        end,
    },
}
