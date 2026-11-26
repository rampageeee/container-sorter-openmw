local settings = {}
settings.section = 'SettingsArtOfAlchemy'
settings.defaults = {
    brewMinutes = 60, experience = 1, discovery = true,
    naming = true, preventVanilla = true, apparatusBalance = false, tutorial = true,
}

function settings.value(key, value)
    if value == nil then return settings.defaults[key] end
    if key == 'brewMinutes' then return math.max(10, math.min(120, tonumber(value) or 60)) end
    if key == 'experience' then return math.max(0, math.min(3, tonumber(value) or 1)) end
    return value == true
end

function settings.read(section, key)
    return settings.value(key, section:get(key))
end

function settings.experienceScale(section)
    return settings.read(section, 'experience') * settings.read(section, 'brewMinutes') / 60
end

function settings.register(interface)
    interface.registerPage({
        key = 'ArtOfAlchemy', l10n = 'ArtOfAlchemy', name = 'title',
        description = 'description',
    })
    local options = {}
    for _, key in ipairs({
        'brewMinutes', 'experience', 'discovery', 'naming', 'preventVanilla', 'apparatusBalance', 'tutorial',
    }) do
        local value = settings.defaults[key]
        local option = {
            key = key, name = key, description = key .. 'Description', default = value,
            renderer = type(value) == 'boolean' and 'checkbox' or 'number',
        }
        if key == 'brewMinutes' then option.argument = { min = 10, max = 120, integer = true } end
        if key == 'experience' then option.argument = { min = 0, max = 3 } end
        options[#options + 1] = option
    end
    interface.registerGroup({
        key = settings.section, page = 'ArtOfAlchemy', l10n = 'ArtOfAlchemy',
        name = 'title', permanentStorage = true, settings = options,
    })
end

return settings
