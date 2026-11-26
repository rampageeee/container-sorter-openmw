local interfaces = require('openmw.interfaces')
local ui = require('openmw.ui')

return {
    eventHandlers = {
        PayTaxesTimerMessage = function(message)
            if message.modal then
                interfaces.UI.showInteractiveMessage(message.text)
            else
                ui.showMessage(message.text)
            end
        end,
    },
}
