fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

description 'w_core - Wraith Core RedM'

-- Dependency names for the public contracts implemented by w_lib/core/compat.
-- See w_lib/COMPATIBILITY.md for supported APIs and import limits.
provide 'rsg-core'
provide 'qbr-core'
provide 'vorp_core'
provide 'vorp_menu'
provide 'vorp_inputs'
provide 'vorp_progressbar'
-- Import name required by encrypted Lua resources; implementation and UI remain in w_lib.
provide 'ox_lib'

-- w_lib first: it defines w / lib / cache / require before any script of this resource runs
shared_scripts {
    '@w_lib/init.lua',
    'config.lua',
    'shared/lang.lua',
    'shared/keybinds.lua',
    'shared/items.lua',
    'shared/jobs.lua',
    'shared/gangs.lua',
    'shared/horse.lua',
    'shared/vehicles.lua',
    'shared/weapons.lua',
    'shared/locations.lua',
    'shared/main.lua'
}

client_scripts {
    'client/main.lua',
    'client/functions.lua',
    'client/loops.lua',
    'client/events.lua',
    'client/nativenotify.js',
    'client/drawtext.lua',
    'client/prompts.lua',
    'client/zones.lua',
    'compat/rsg_shared.lua',
    'compat/rsg_client.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/functions.lua',
    'server/identifiers.lua',
    'server/economy.lua',
    'server/player.lua',
    'server/citizen.lua',     -- the sequential citizen id, blocks, reassign, the migration
    'server/events.lua',
    'server/commands.lua',
    'server/exports.lua',
    'server/loops.lua',
    'server/debug.lua',
    'compat/rsg_shared.lua',
    'compat/rsg_server.lua'
}

files {
    'init.lua',
    'locales/*.json',
    'shared/locale.lua',
    'client/dataview.lua',
    'client/ref/dataview.lua'
}

-- library modules preloaded on both sides (the dictionary loads at start)
w_lib {
    'locale',
    'callback'
}

dependencies { 'oxmysql', 'w_lib' }
lua54 'yes'
