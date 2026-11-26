local vfs = require('openmw.vfs')

local appearance = {}
local styles = { 'bargain', 'cheap', 'standard', 'fresh', 'quality', 'exclusive' }
local available

function appearance.paths(style)
    return 'meshes/m/misc_potion_' .. style .. '_01.nif', 'm/tx_potion_' .. style .. '_01.tga'
end

function appearance.icon(style)
    local _, icon = appearance.paths(style)
    local path = 'icons/' .. icon
    local dds = path:gsub('%.tga$', '.dds')
    return vfs.fileExists(dds) and dds or path
end

function appearance.options()
    if available then return available end
    available = {}
    for _, style in ipairs(styles) do
        local model = appearance.paths(style)
        local icon = appearance.icon(style)
        if vfs.fileExists(model) and vfs.fileExists(icon) then
            available[#available + 1] = { style = style, icon = icon }
        end
    end
    return available
end

function appearance.choose(style, random)
    local options = appearance.options()
    for _, option in ipairs(options) do
        if option.style == style then return style end
    end
    if #options > 0 then return options[random(1, #options)].style end
end

return appearance
