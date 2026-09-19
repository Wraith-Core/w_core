-- Plain on-screen text (WCore DrawText / ChangeText / HideText / KeyPressed) over the library's
-- text UI. This is for messages only: a "press [key]" hint is never drawn here; anything that
-- asks the player for a key is a library prompt (w.prompt.at / w.prompt.atEntity /
-- w.prompt.createGroup, or the createPrompt export of client/prompts.lua for third-party scripts).

local positions = {
    left = 'left-center',
    right = 'right-center',
    top = 'top-center'
}

local function hideText()
    w.hideTextUI()
end

-- The text may be a dictionary key (a server caller sends keys): translated here, in the
-- player's language.
local function drawText(text, position)
    position = positions[position] or position
    w.showTextUI(locale(tostring(text)), {
        position = position
    })
end

local function changeText(text, position)
    position = positions[position] or position
    w.hideTextUI()
    w.showTextUI(locale(tostring(text)), {
        position = position
    })
end

-- Part of the RSG-Core contract: the text goes away half a second after the caller's action.
local function keyPressed()
    SetTimeout(500, hideText)
end

RegisterNetEvent('w_core:client:DrawText', function(text, position)
    drawText(text, position)
end)

RegisterNetEvent('w_core:client:ChangeText', function(text, position)
    changeText(text, position)
end)

RegisterNetEvent('w_core:client:HideText', function()
    hideText()
end)

RegisterNetEvent('w_core:client:KeyPressed', function()
    keyPressed()
end)

exports('DrawText', drawText)
exports('ChangeText', changeText)
exports('HideText', hideText)
exports('KeyPressed', keyPressed)