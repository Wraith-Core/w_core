WConfig = {}

WConfig.MaxPlayers = GetConvarInt('sv_maxclients', 48) -- Gets max players from config file, default 48
WConfig.DefaultSpawn = vector4(-1035.71, -2731.87, 12.86, 0.0)
WConfig.UpdateInterval = 5 -- How often to update player data in minutes
WConfig.StatusInterval = 5 -- How often to check hunger/thirst status in seconds
WConfig.ShowDoMeTryLength = 7 -- How long to show /me, /do, /try text (Set in Seconds)

WConfig.Money = {}
WConfig.Money.MoneyTypes = { cash = 0, bank = 0, bloodmoney = 0, gold = 0 } -- type = startamount - Add or remove money types for your server (for ex. blackmoney = 0), remember once added it will not be removed from the database!
WConfig.Money.DontAllowMinus = { 'cash', 'bank', 'bloodmoney', 'gold' } -- Money that is not allowed going in minus
WConfig.Money.PayCheckTimeOut = 10 -- The time in minutes that it will give the paycheck
WConfig.Money.PayCheckSociety = false -- If true paycheck will come from the society account that the player is employed at, requires w_management

WConfig.Player = {}
WConfig.Player.RevealMap = true
WConfig.Player.EnableEagleEye = true
WConfig.Player.HungerRate = 4.2 -- Rate at which hunger goes down.
WConfig.Player.ThirstRate = 3.8 -- Rate at which thirst goes down.
WConfig.Player.Bloodtypes = {
    "A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-",
}

WConfig.Server = {} -- General server config
WConfig.Server.Closed = false -- Set server closed (no one can join except people with ace permission 'wraithadmin.join')
WConfig.Server.ClosedReason = 'info.server_closed_default' -- Reason shown to people who can't join: a dictionary key (locales/*.json) or plain text
WConfig.Server.Uptime = 0 -- Time the server has been up.
WConfig.Server.Whitelist = false -- Enable or disable whitelist on the server
WConfig.Server.WhitelistPermission = 'admin' -- Permission that's able to enter the server when the whitelist is on
WConfig.Server.Discord = "" -- Discord invite link
WConfig.Server.CheckDuplicateLicense = true -- Check for duplicate rockstar license on join
WConfig.Server.Permissions = { 'god', 'admin', 'mod' } -- Add as many groups as you want here after creating them in your server.cfg

WConfig.NotifyPosition = false -- false: the player's own choice in /w_lib | 'top' | 'top-right' | 'top-left' | 'bottom' | 'bottom-right' | 'bottom-left'

WConfig.StarterItems = {
    ['bread'] 			= { amount = 10, item = 'bread' },
    ['water_bottle'] 	= { amount = 10, item = 'water_bottle' },
}