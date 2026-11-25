local settings = require('openmw.interfaces').Settings

settings.registerPage {
    key = 'UniversalContainerSorter',
    l10n = 'UniversalContainerSorter',
    name = 'title',
    description = 'settingsDescription',
}

settings.registerGroup {
    key = 'Settings/UniversalContainerSorter',
    page = 'UniversalContainerSorter',
    l10n = 'UniversalContainerSorter',
    name = 'settingsGroup',
    permanentStorage = true,
    settings = {
        {
            key = 'modifier',
            name = 'modifier',
            description = 'modifierDescription',
            renderer = 'textLine',
            default = 'T',
        },
        {
            key = 'debug',
            name = 'debug',
            description = 'debugDescription',
            renderer = 'checkbox',
            default = false,
        },
        {
            key = 'allowKeys',
            name = 'allowKeys',
            description = 'allowKeysDescription',
            renderer = 'checkbox',
            default = false,
        },
        {
            key = 'blacklist',
            name = 'blacklist',
            description = 'blacklistDescription',
            renderer = 'textLine',
            default = '',
        },
    },
}
