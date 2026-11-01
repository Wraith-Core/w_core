WCore.Players = {}
WCore.Player = {}

-- On player login get their data or set defaults
-- Don't touch any of this unless you know what you are doing
-- Will cause major issues!

function WCore.Player.Login(source, citizenid, newData)
	if source and source ~= "" then
		local valid, reason = WCore.Functions.ValidatePlayerIdentifiers(source)
		if not valid then
			DropPlayer(source, reason)
			return false
		end
		if citizenid then
			-- a character being deleted (or moved to another number) right now is not played
			-- meanwhile: its row still exists until the purge's last step (server/citizen.lua)
			if WCore.Citizen and WCore.Citizen.IsBusy and WCore.Citizen.IsBusy(citizenid) then return false, 'busy' end
			local license = WCore.Functions.GetIdentifier(source, "license")
			local PlayerData = MySQL.prepare.await("SELECT * FROM players where citizenid = ?", { citizenid })
			if PlayerData and license == PlayerData.license then
				-- a character staff blocked is not played (the account's other characters are)
				local block = WCore.Citizen and WCore.Citizen.GetBlock(citizenid)
				if block then
					-- through the notify w_core's client already handles (nothing listens to a
					-- dedicated event), as a key: translated in the player's own language
					TriggerClientEvent('WCore:Notify', source, { key = 'info.character_blocked',
						subs = { reason = (block.reason and block.reason ~= '') and block.reason or '-' } }, 'error', 7000)
					return false, 'blocked'
				end
				PlayerData.money = json.decode(PlayerData.money)
				PlayerData.job = json.decode(PlayerData.job)
				PlayerData.position = json.decode(PlayerData.position)
				PlayerData.metadata = json.decode(PlayerData.metadata)
				PlayerData.charinfo = json.decode(PlayerData.charinfo)
				if PlayerData.gang then
					PlayerData.gang = json.decode(PlayerData.gang)
				else
					PlayerData.gang = {}
				end
				-- asked again after the awaits above: a deletion that started meanwhile found no one
				-- to kick (CreatePlayer asks once more, right before the character is put in play)
				if WCore.Citizen and WCore.Citizen.IsBusy(citizenid) then return false, 'busy' end
				return WCore.Player.CheckPlayerData(source, PlayerData) ~= nil
			else
				DropPlayer(source, Lang:t("info.exploit_dropped"))
				TriggerEvent(
					"w_log:server:CreateLog",
					"anticheat",
					"Anti-Cheat",
					"white",
					GetPlayerName(source) .. " Has Been Dropped For Character Joining Exploit",
					false
				)
				return false
			end
		else
			return WCore.Player.CheckPlayerData(source, newData) ~= nil
		end
	else
		WCore.ShowError(GetCurrentResourceName(), "ERROR WCORE.PLAYER.LOGIN - NO SOURCE GIVEN!")
		return false
	end
end

function WCore.Player.GetOfflinePlayer(citizenid)
	if citizenid then
		local PlayerData = MySQL.Sync.prepare("SELECT * FROM players where citizenid = ?", { citizenid })
		if PlayerData then
			PlayerData.money = json.decode(PlayerData.money)
			PlayerData.job = json.decode(PlayerData.job)
			PlayerData.position = json.decode(PlayerData.position)
			PlayerData.metadata = json.decode(PlayerData.metadata)
			PlayerData.charinfo = json.decode(PlayerData.charinfo)
			if PlayerData.gang then
				PlayerData.gang = json.decode(PlayerData.gang)
			else
				PlayerData.gang = {}
			end

			return WCore.Player.CheckPlayerData(nil, PlayerData)
		end
	end
	return nil
end

function WCore.Player.CheckPlayerData(source, PlayerData)
	PlayerData = PlayerData or {}
	local Offline = true
	if source then
		local valid, reason, identifiers = WCore.Functions.ValidatePlayerIdentifiers(source)
		if not valid then
			DropPlayer(source, reason)
			return nil
		end
		PlayerData.source = source
		PlayerData.license = identifiers.license
		PlayerData.identifiers = identifiers
		PlayerData.name = GetPlayerName(source)
		Offline = false
	end

    local isNew = not PlayerData.citizenid
    PlayerData.citizenid = PlayerData.citizenid or WCore.Player.CreateCitizenId()
    PlayerData.cid = PlayerData.cid or 1
    PlayerData.optin = PlayerData.optin or true
    if not WCore.Economy.hydrate(PlayerData,isNew) then
        if source then DropPlayer(source,'البنك المركزي غير جاهز. يرجى الانتظار حتى تفعيل الاقتصاد بواسطة الإدارة.') end
        return nil
    end

	-- Charinfo
	PlayerData.charinfo = PlayerData.charinfo or {}
	PlayerData.charinfo.firstname = PlayerData.charinfo.firstname or "Firstname"
	PlayerData.charinfo.lastname = PlayerData.charinfo.lastname or "Lastname"
	PlayerData.charinfo.birthdate = PlayerData.charinfo.birthdate or "00-00-0000"
	PlayerData.charinfo.gender = PlayerData.charinfo.gender or 0
	PlayerData.charinfo.backstory = PlayerData.charinfo.backstory or "placeholder backstory"
	PlayerData.charinfo.nationality = PlayerData.charinfo.nationality or "USA"
	PlayerData.charinfo.account = PlayerData.charinfo.account or WCore.Functions.CreateAccountNumber()
	-- Metadata
	PlayerData.metadata = PlayerData.metadata or {}
	PlayerData.metadata.hunger = PlayerData.metadata.hunger or 100
	PlayerData.metadata.thirst = PlayerData.metadata.thirst or 100
	PlayerData.metadata.stress = PlayerData.metadata.stress or 0
	PlayerData.metadata.isdead = PlayerData.metadata.isdead or false
	PlayerData.metadata.inlaststand = PlayerData.metadata.inlaststand or false
	PlayerData.metadata.ishandcuffed = PlayerData.metadata.ishandcuffed or false
	PlayerData.metadata.injail = PlayerData.metadata.injail or 0
	PlayerData.metadata.jailitems = PlayerData.metadata.jailitems or {}
	PlayerData.metadata.status = PlayerData.metadata.status or {}
	PlayerData.metadata.commandbinds = PlayerData.metadata.commandbinds or {}
	PlayerData.metadata.bloodtype = PlayerData.metadata.bloodtype or WCore.Config.Player.Bloodtypes[math.random(1, #WCore.Config.Player.Bloodtypes)]
	PlayerData.metadata.craftingrep = PlayerData.metadata.craftingrep or 0
	PlayerData.metadata.jobrep = PlayerData.metadata.jobrep or {}
	PlayerData.metadata.callsign = PlayerData.metadata.callsign or "NO CALLSIGN"
	PlayerData.metadata.fingerprint = PlayerData.metadata.fingerprint or WCore.Player.CreateFingerId()
	PlayerData.metadata.walletid = PlayerData.metadata.walletid or WCore.Player.CreateWalletId()
	PlayerData.metadata.criminalrecord = PlayerData.metadata.criminalrecord or {
		hasRecord = false,
		date = nil,
	}

    PlayerData.metadata.xp = PlayerData.metadata.xp or {
		main = 0,
		herbalism = 0,
		mining = 0,
        cooking = 0,
        crafting = 0,
	}

    PlayerData.metadata.levels = PlayerData.metadata.levels or {
		main = 0,
		herbalism = 0,
		mining = 0,
        cooking = 0,
        crafting = 0,
	}

    PlayerData.metadata.licences = PlayerData.metadata.licences or {
        weapon = false
    }

	-- Job
	if PlayerData.job and PlayerData.job.name and not WJobs[PlayerData.job.name] then PlayerData.job = nil end
	PlayerData.job = PlayerData.job or {}
	PlayerData.job.name = PlayerData.job.name or "unemployed"
	PlayerData.job.label = PlayerData.job.label or "Civilian"
	-- Arabic name from the catalogue (rows saved before label_ar existed have none)
	PlayerData.job.label_ar = PlayerData.job.label_ar or WJobs[PlayerData.job.name].label_ar or "مدني"
	PlayerData.job.payment = PlayerData.job.payment or 10
	PlayerData.job.type = PlayerData.job.type or "none"
	if WCore.Shared.ForceJobDefaultDutyAtLogin or PlayerData.job.onduty == nil then PlayerData.job.onduty = WJobs[PlayerData.job.name].defaultDuty end
	PlayerData.job.isboss = PlayerData.job.isboss or false
	PlayerData.job.grade = PlayerData.job.grade or {}
	PlayerData.job.grade.name = PlayerData.job.grade.name or "Freelancer"
	PlayerData.job.grade.level = PlayerData.job.grade.level or 0
	local jobGradeDef = WJobs[PlayerData.job.name].grades[PlayerData.job.grade.level]
	PlayerData.job.grade.name_ar = PlayerData.job.grade.name_ar or (jobGradeDef and jobGradeDef.name_ar) or "عامل حر"

	-- Gang
	if PlayerData.gang and PlayerData.gang.name and not WGangs[PlayerData.gang.name] then PlayerData.gang = nil end
	PlayerData.gang = PlayerData.gang or {}
	PlayerData.gang.name = PlayerData.gang.name or "none"
	PlayerData.gang.label = PlayerData.gang.label or "No Gang Affiliaton"
	PlayerData.gang.label_ar = PlayerData.gang.label_ar or WGangs[PlayerData.gang.name].label_ar or "بدون عصابة"
	PlayerData.gang.isboss = PlayerData.gang.isboss or false
	PlayerData.gang.grade = PlayerData.gang.grade or {}
	PlayerData.gang.grade.name = PlayerData.gang.grade.name or "none"
	PlayerData.gang.grade.level = PlayerData.gang.grade.level or 0
	local gangGradeDef = WGangs[PlayerData.gang.name].grades[PlayerData.gang.grade.level]
	PlayerData.gang.grade.name_ar = PlayerData.gang.grade.name_ar or (gangGradeDef and gangGradeDef.name_ar) or "غير منتسب"

	-- Other
	PlayerData.position = PlayerData.position or WConfig.DefaultSpawn
	-- w_inventory registers the core-facing inventory API under the rsg-inventory name it provides
	PlayerData.items = GetResourceState("w_inventory") ~= "missing" and exports["rsg-inventory"]:LoadInventory(PlayerData.source, PlayerData.citizenid) or {}

	return WCore.Player.CreatePlayer(PlayerData, Offline)
end

-- On player logout

function WCore.Player.Logout(source)
	TriggerClientEvent("WCore:Client:OnPlayerUnload", source)
	TriggerEvent("WCore:Server:OnPlayerUnload", source)
	TriggerClientEvent("WCore:Player:UpdatePlayerData", source)
	Wait(200)
	WCore.Players[source] = nil
end

-- Create a new character
-- Don't touch any of this unless you know what you are doing
-- Will cause major issues!

function WCore.Player.CreatePlayer(PlayerData, Offline)
	local self = {}
	self.Functions = {}
	self.PlayerData = PlayerData
	self.Offline = Offline

	function self.Functions.UpdatePlayerData()
		if self.Offline then return end -- Unsupported for Offline Players
		TriggerEvent("WCore:Player:SetPlayerData", self.PlayerData)
		TriggerClientEvent("WCore:Player:SetPlayerData", self.PlayerData.source, self.PlayerData)
		-- sent under the RSG name as a NET event too: w_inventory's client handler drops local
		-- re-triggers (source == ''), so the client-side mirror cannot carry this one
		TriggerClientEvent("RSGCore:Player:SetPlayerData", self.PlayerData.source, self.PlayerData)
	end

	function self.Functions.SetJob(job, grade)
		job = job:lower()
		grade = tonumber(grade) or 0
		if not WJobs[job] then
			return false
		end
		self.PlayerData.job.name = job
		self.PlayerData.job.label = WJobs[job].label
		self.PlayerData.job.label_ar = WJobs[job].label_ar or WJobs[job].label
		self.PlayerData.job.onduty = WJobs[job].defaultDuty
		self.PlayerData.job.type = WJobs[job].type or "none"
		if WJobs[job].grades[grade] then
			local jobgrade = WJobs[job].grades[grade]
			self.PlayerData.job.grade = {}
			self.PlayerData.job.grade.name = jobgrade.name
			self.PlayerData.job.grade.name_ar = jobgrade.name_ar or jobgrade.name
			self.PlayerData.job.grade.level = tonumber(grade)
			self.PlayerData.job.payment = jobgrade.payment or 30
			self.PlayerData.job.isboss = jobgrade.isboss or false
		else
			self.PlayerData.job.grade = {}
			self.PlayerData.job.grade.name = "No Grades"
			self.PlayerData.job.grade.name_ar = "بدون رتبة"
			self.PlayerData.job.grade.level = 0
			self.PlayerData.job.payment = 30
			self.PlayerData.job.isboss = false
		end

		if not self.Offline then
			self.Functions.UpdatePlayerData()
			TriggerEvent("WCore:Server:OnJobUpdate", self.PlayerData.source, self.PlayerData.job)
			TriggerClientEvent("WCore:Client:OnJobUpdate", self.PlayerData.source, self.PlayerData.job)
		end

		return true
	end

	function self.Functions.SetGang(gang, grade)
		gang = gang:lower()
		grade = tonumber(grade) or 0
		if not WGangs[gang] then
			return false
		end
		self.PlayerData.gang.name = gang
		self.PlayerData.gang.label = WGangs[gang].label
		self.PlayerData.gang.label_ar = WGangs[gang].label_ar or WGangs[gang].label
		if WGangs[gang].grades[grade] then
			local ganggrade = WGangs[gang].grades[grade]
			self.PlayerData.gang.grade = {}
			self.PlayerData.gang.grade.name = ganggrade.name
			self.PlayerData.gang.grade.name_ar = ganggrade.name_ar or ganggrade.name
			self.PlayerData.gang.grade.level = tonumber(grade)
			self.PlayerData.gang.isboss = ganggrade.isboss or false
		else
			self.PlayerData.gang.grade = {}
			self.PlayerData.gang.grade.name = "No Grades"
			self.PlayerData.gang.grade.name_ar = "بدون رتبة"
			self.PlayerData.gang.grade.level = 0
			self.PlayerData.gang.isboss = false
		end

		if not self.Offline then
			self.Functions.UpdatePlayerData()
			TriggerEvent("WCore:Server:OnGangUpdate", self.PlayerData.source, self.PlayerData.gang)
			TriggerClientEvent("WCore:Client:OnGangUpdate", self.PlayerData.source, self.PlayerData.gang)
		end

		return true
	end

	function self.Functions.SetJobDuty(onDuty)
		self.PlayerData.job.onduty = not not onDuty -- Make sure the value is a boolean if nil is sent
		self.Functions.UpdatePlayerData()
	end

	function self.Functions.SetPlayerData(key, val)
		if not key or type(key) ~= "string" then
			return
		end
		if key == 'money' or key == 'citizenid' then return false end
		self.PlayerData[key] = val
		self.Functions.UpdatePlayerData()
	end

	function self.Functions.SetMetaData(meta, val)
		if not meta or type(meta) ~= "string" then
			return
		end
		if meta == "hunger" or meta == "thirst" then
			val = val > 100 and 100 or val
		end
		self.PlayerData.metadata[meta] = val
		self.Functions.UpdatePlayerData()
	end

	function self.Functions.GetMetaData(meta)
		if not meta or type(meta) ~= "string" then
			return
		end
		return self.PlayerData.metadata[meta]
	end

	function self.Functions.AddJobReputation(amount)
		if not amount then
			return
		end
		amount = tonumber(amount)
		self.PlayerData.metadata["jobrep"][self.PlayerData.job.name] = self.PlayerData.metadata["jobrep"][self.PlayerData.job.name]
			+ amount
		self.Functions.UpdatePlayerData()
	end

	-- Who, for the levels log. An offline player (a staff command on a citizen id) has neither a
	-- server id nor a connection name: concatenating nil raised after the metadata had changed.
	local function logWho()
		local src = self.PlayerData.source
		return tostring(src and GetPlayerName(src) or self.PlayerData.name or '?'), src and tostring(src) or 'offline'
	end

    self.Functions.AddXp = function(skill, amount)
		local skill = skill:lower()
		local amount = tonumber(amount)
		if self.PlayerData.metadata.xp[skill] and amount > 0 then
			self.PlayerData.metadata.xp[skill] = self.PlayerData.metadata.xp[skill] + amount
			self.Functions.UpdateLevelData(skill)
			self.Functions.UpdatePlayerData()
			local name, id = logWho()
			TriggerEvent('w_log:server:CreateLog', 'levels', 'AddXp', 'lightgreen', '**'..name .. ' (citizenid: '..self.PlayerData.citizenid..' | id: '..id..')** has received: '..amount..'xp in the skill: '..skill..'. Their current xp amount is: '..self.PlayerData.metadata['xp'][skill])
			return true
		end
		return false
	end

	self.Functions.RemoveXp = function(skill, amount)
		local skill = skill:lower()
		local amount = tonumber(amount)
		if self.PlayerData.metadata.xp[skill] and amount > 0 then
			self.PlayerData.metadata.xp[skill] = self.PlayerData.metadata.xp[skill] - amount
			self.Functions.UpdateLevelData(skill)
			self.Functions.UpdatePlayerData()
			local name, id = logWho()
			TriggerEvent('w_log:server:CreateLog', 'levels', 'RemoveXp', 'lightgreen', '**'..name .. ' (citizenid: '..self.PlayerData.citizenid..' | id: '..id..')** was stripped of: '..amount..'xp in the skill: '..skill..'. Their current xp amount is: '..self.PlayerData.metadata['xp'][skill])
			return true
		end
		return false
	end

    self.Functions.AddLevel = function(level, amount)
		local level = level:lower()
		local amount = tonumber(amount)
		if self.PlayerData.metadata.levels[level] and amount > 0 then
			self.PlayerData.metadata.levels[level] = self.PlayerData.metadata.levels[level] + amount
			self.Functions.UpdateLevelData(level)
			self.Functions.UpdatePlayerData()
			local name, id = logWho()
			TriggerEvent('w_log:server:CreateLog', 'levels', 'AddXp', 'lightgreen', '**'..name .. ' [CitizenID: '..self.PlayerData.citizenid..' | id: '..id..']** got '..level..' levels '..amount..' [current level: '..self.PlayerData.metadata.levels[level])
			return true
		end
		return false
	end

	self.Functions.RemoveLevel = function(level, amount)
		local level = level:lower()
		local amount = tonumber(amount)
		if self.PlayerData.metadata.levels[level] and amount > 0 then
			self.PlayerData.metadata.levels[level] = self.PlayerData.metadata.levels[level] - amount
			self.Functions.UpdateLevelData(level)
			self.Functions.UpdatePlayerData()
			local name, id = logWho()
			TriggerEvent('w_log:server:CreateLog', 'levels', 'RemoveXp', 'lightgreen', '**'..name .. ' [CitizenID: '..self.PlayerData.citizenid..' | id: '..id..']** lost '..level..' levels '..amount..' current level: '..self.PlayerData.metadata.levels[level])
			return true
		end
		return false
	end

    self.Functions.UpdateLevelData = function(skill, vall)
        local skill = skill:lower()
        if vall ~= nil then
            self.PlayerData.metadata[skill] = vall
            self.Functions.UpdatePlayerData()
        end
    end



	function self.Functions.AddMoney(kind, amount, reason)
        return WCore.Economy.change(self,kind,amount,'add',reason)
    end
    function self.Functions.RemoveMoney(kind, amount, reason)
        return WCore.Economy.change(self,kind,amount,'remove',reason)
    end
    function self.Functions.SetMoney(kind, amount, reason)
        return WCore.Economy.change(self,kind,amount,'set',reason)
    end
    function self.Functions.GetMoney(kind)
        if not WCore.Economy.ready() or type(kind)~='string' then return 0 end
        if kind=='bloodmoney' then kind='gold' end
        return exports.w_centralbank:GetBalance('player:'..self.PlayerData.citizenid..':'..kind) or 0
    end

	function self.Functions.Save()
		if self.Offline then
			WCore.Player.SaveOffline(self.PlayerData)
		else
			WCore.Player.Save(self.PlayerData.source)
		end
	end

	function self.Functions.Logout()
		if self.Offline then return end -- Unsupported for Offline Players
		WCore.Player.Logout(self.PlayerData.source)
	end

	function self.Functions.AddMethod(methodName, handler)
		self.Functions[methodName] = handler
	end

	function self.Functions.AddField(fieldName, data)
		self[fieldName] = data
	end

	-- Item methods (RSG signatures). The original core carried none: w_inventory installs its own
	-- through AddPlayerMethod on PlayerLoaded; until then, and if it is absent, these delegate to
	-- the rsg-inventory API it provides.
	local function invReady() return GetResourceState('w_inventory') == 'started' end
	function self.Functions.AddItem(item, amount, slot, info)
		return invReady() and exports['rsg-inventory']:AddItem(self.PlayerData.source, item, amount, slot, info) or false
	end
	function self.Functions.RemoveItem(item, amount, slot)
		return invReady() and exports['rsg-inventory']:RemoveItem(self.PlayerData.source, item, amount, slot) or false
	end
	function self.Functions.GetItemBySlot(slot)
		return invReady() and exports['rsg-inventory']:GetItemBySlot(self.PlayerData.source, slot) or nil
	end
	function self.Functions.GetItemByName(item)
		return invReady() and exports['rsg-inventory']:GetItemByName(self.PlayerData.source, item) or nil
	end
	function self.Functions.GetItemsByName(item)
		return invReady() and exports['rsg-inventory']:GetItemsByName(self.PlayerData.source, item) or {}
	end
	function self.Functions.ClearInventory(filterItems)
		return invReady() and exports['rsg-inventory']:ClearInventory(self.PlayerData.source, filterItems) or false
	end
	function self.Functions.SetInventory(items)
		return invReady() and exports['rsg-inventory']:SetInventory(self.PlayerData.source, items) or false
	end

	if self.Offline then
		return self
	else
		-- the last check before the character is in play, with no await between it and the entry
		-- below: a purge (or a reassign) that started while this login awaited the database kicked
		-- no one, and a row a purge deleted meanwhile (read just before) is gone for good
		local Citizen = WCore.Citizen
		-- (nor a row a reassign or a transfer moved to another number meanwhile: this copy still
		-- carries the old one)
		if Citizen and (Citizen.IsBusy(self.PlayerData.citizenid) or (Citizen.RowPurged and Citizen.RowPurged(self.PlayerData.id))
			or (Citizen.RowMoved and Citizen.RowMoved(self.PlayerData.id, self.PlayerData.citizenid))) then
			return nil
		end
        -- No yield before publishing the player: concurrent logins cannot share a character.
        for otherSource, other in pairs(WCore.Players) do
            if otherSource ~= self.PlayerData.source and other.PlayerData then
                local sameCharacter = other.PlayerData.citizenid == self.PlayerData.citizenid
                local sameLicense = WCore.Config.Server.CheckDuplicateLicense and other.PlayerData.license == self.PlayerData.license
                if sameCharacter or sameLicense then
                    DropPlayer(self.PlayerData.source, Lang:t('error.duplicate_license'))
                    return nil
                end
            end
        end
		WCore.Players[self.PlayerData.source] = self
		WCore.Player.Save(self.PlayerData.source)

		-- At this point we are safe to emit new instance to third party resource for load handling
		TriggerEvent("WCore:Server:PlayerLoaded", self)
		self.Functions.UpdatePlayerData()
	end
	return self
end

-- Add a new function to the Functions table of the player class
-- Use-case:
--[[
    AddEventHandler('WCore:Server:PlayerLoaded', function(Player)
        WCore.Functions.AddPlayerMethod(Player.PlayerData.source, "functionName", function(oneArg, orMore)
            -- do something here
        end)
    end)
]]

function WCore.Functions.AddPlayerMethod(ids, methodName, handler)
	local idType = type(ids)
	if idType == "number" then
		if ids == -1 then
			for _, v in pairs(WCore.Players) do
				v.Functions.AddMethod(methodName, handler)
			end
		else
			if not WCore.Players[ids] then return end

			WCore.Players[ids].Functions.AddMethod(methodName, handler)
		end
	elseif idType == "table" and table.type(ids) == "array" then
		for i = 1, #ids do
			WCore.Functions.AddPlayerMethod(ids[i], methodName, handler)
		end
	end
end

-- Add a new field table of the player class
-- Use-case:
--[[
    AddEventHandler('WCore:Server:PlayerLoaded', function(Player)
        WCore.Functions.AddPlayerField(Player.PlayerData.source, "fieldName", "fieldData")
    end)
]]

function WCore.Functions.AddPlayerField(ids, fieldName, data)
	local idType = type(ids)
	if idType == "number" then
		if ids == -1 then
			for _, v in pairs(WCore.Players) do
				v.Functions.AddField(fieldName, data)
			end
		else
			if not WCore.Players[ids] then return end

			WCore.Players[ids].Functions.AddField(fieldName, data)
		end
	elseif idType == "table" and table.type(ids) == "array" then
		for i = 1, #ids do
			WCore.Functions.AddPlayerField(ids[i], fieldName, data)
		end
	end
end

-- Save player info to database (make sure citizenid is the primary key in your database)

-- players-row writes in flight, by citizen id ({ n, at }). Deleting a character waits for its
-- logout save (server/citizen.lua Purge): landing after the DELETE, that INSERT ... ON DUPLICATE
-- KEY UPDATE would bring the deleted row back.
local savesInFlight = {}
-- a write whose callback never came (a failed query) is not waited for forever
local SAVE_TRACK_MS = 15000

local function saveStarted(citizenid)
	local s = savesInFlight[citizenid]
	if s then
		s.n, s.at = s.n + 1, GetGameTimer()
	else
		savesInFlight[citizenid] = { n = 1, at = GetGameTimer() }
	end
end

local function saveDone(citizenid)
	local s = savesInFlight[citizenid]
	if not s then return end
	s.n = s.n - 1
	if s.n <= 0 then savesInFlight[citizenid] = nil end
end

function WCore.Player.SaveInFlight(citizenid)
	local s = savesInFlight[citizenid]
	if not s then return false end
	if GetGameTimer() - s.at > SAVE_TRACK_MS then
		savesInFlight[citizenid] = nil
		return false
	end
	return true
end

-- a character just purged: a save still arriving for it (an offline Player object another
-- resource holds, a late logout save) must not re-create its row -- by its number while the purge
-- guard holds, and for good by the players row it was loaded from (PlayerData.id): once staff
-- gives the number to someone else, that save would overwrite the new holder's row. The same for
-- a character moved to another number (reassign, transfer): a copy loaded before the move still
-- carries the old number, and its save would write a ghost row under it or over its next holder.
local function saveBlocked(PlayerData)
	local Citizen = WCore.Citizen
	if Citizen == nil then return false end
	return (Citizen.SaveBlocked ~= nil and Citizen.SaveBlocked(PlayerData.citizenid))
		or (Citizen.RowPurged ~= nil and Citizen.RowPurged(PlayerData.id))
		or (Citizen.RowMoved ~= nil and Citizen.RowMoved(PlayerData.id, PlayerData.citizenid))
end

function WCore.Player.Save(source)
	local ped = GetPlayerPed(source)
	local pcoords = GetEntityCoords(ped)
	local player = WCore.Players[source]
	local PlayerData = player.PlayerData
	if PlayerData then
		local citizenid = PlayerData.citizenid
		if saveBlocked(PlayerData) then return end
		-- only a loaded row carries its players.id (Login's SELECT): a character created this
		-- session has none until its first save lands, and every resource that checks the row
		-- (w_creators, w_crafting, w_gunsmith, the purge/move guards above) needs it
		local needsRowId = PlayerData.id == nil
		saveStarted(citizenid)
		MySQL.insert(
			"INSERT INTO players (citizenid, cid, license, name, money, charinfo, job, gang, position, metadata) VALUES (:citizenid, :cid, :license, :name, :money, :charinfo, :job, :gang, :position, :metadata) ON DUPLICATE KEY UPDATE cid = :cid, name = :name, charinfo = :charinfo, job = :job, gang = :gang, position = :position, metadata = :metadata",
			{
				citizenid = PlayerData.citizenid,
				cid = tonumber(PlayerData.cid),
				license = PlayerData.license,
				name = PlayerData.name,
				money = json.encode(PlayerData.money),
				charinfo = json.encode(PlayerData.charinfo),
				job = json.encode(PlayerData.job),
				gang = json.encode(PlayerData.gang),
				position = json.encode(pcoords),
				metadata = json.encode(PlayerData.metadata),
			},
			function()
				saveDone(citizenid)
				if not needsRowId then return end
				-- read by its number, never this ON DUPLICATE KEY UPDATE's insertId (not the row's
				-- id when it updated one); set only while the same character is still in play
				MySQL.scalar('SELECT id FROM players WHERE citizenid = ? LIMIT 1', { citizenid }, function(rowId)
					rowId = tonumber(rowId)
					if rowId and WCore.Players[source] == player and player.PlayerData == PlayerData
						and PlayerData.citizenid == citizenid and PlayerData.id == nil then
						player.Functions.SetPlayerData('id', rowId)
					end
				end)
			end
		)
		if GetResourceState("w_inventory") ~= "missing" then
			exports["rsg-inventory"]:SaveInventory(source)
		end
		if WCore.Config.Debug then
			WCore.ShowSuccess(GetCurrentResourceName(), PlayerData.name .. " PLAYER SAVED!")
		end
	else
		WCore.ShowError(GetCurrentResourceName(), "ERROR WCORE.PLAYER.SAVE - PLAYERDATA IS EMPTY!")
	end
end

function WCore.Player.SaveOffline(PlayerData)
	if PlayerData then
		local citizenid = PlayerData.citizenid
		if saveBlocked(PlayerData) then return end
		saveStarted(citizenid)
		MySQL.Async.insert(
			"INSERT INTO players (citizenid, cid, license, name, money, charinfo, job, gang, position, metadata) VALUES (:citizenid, :cid, :license, :name, :money, :charinfo, :job, :gang, :position, :metadata) ON DUPLICATE KEY UPDATE cid = :cid, name = :name, charinfo = :charinfo, job = :job, gang = :gang, position = :position, metadata = :metadata",
			{
				citizenid = PlayerData.citizenid,
				cid = tonumber(PlayerData.cid),
				license = PlayerData.license,
				name = PlayerData.name,
				money = json.encode(PlayerData.money),
				charinfo = json.encode(PlayerData.charinfo),
				job = json.encode(PlayerData.job),
				gang = json.encode(PlayerData.gang),
				position = json.encode(PlayerData.position),
				metadata = json.encode(PlayerData.metadata),
			},
			function() saveDone(citizenid) end
		)
		if GetResourceState("w_inventory") ~= "missing" then
			exports["rsg-inventory"]:SaveInventory(PlayerData, true)
		end
		if WCore.Config.Debug then
			WCore.ShowSuccess(GetCurrentResourceName(), PlayerData.name .. " OFFLINE PLAYER SAVED!")
		end
	else
		WCore.ShowError(GetCurrentResourceName(), "ERROR WCORE.PLAYER.SAVEOFFLINE - PLAYERDATA IS EMPTY!")
	end
end

-- Delete character

-- A character is deleted by server/citizen.lua's Purge. The player's own deletion from the
-- character selection and staff's deletion are the same full purge: every resource removes its
-- part, assets are released, the money goes back to the reserve, the history moves to a
-- tombstone, and the number is left clean for someone else (a vanity id that was not renewed).

-- The purge's reasons -> the few the character selection knows (w_creators DELETE_REFUSALS): a
-- resource still busy (a write in flight, a player still leaving) is a retry; a ledger or a
-- resource that is not ready says so; an asset its resource could not release says so; anything
-- else is a failure the server console explains.
local function selectionReason(why)
	why = tostring(why or '')
	if why == 'assets' then return 'assets' end
	if why:find('economy', 1, true) or why:find('not_ready', 1, true) or why:find('unavailable', 1, true) then
		return 'economy_not_ready'
	end
	if why:find('busy', 1, true) or why:find('online', 1, true) or why:find('pending', 1, true)
		or why == 'balance_changed' or why == 'retry' or why == 'restarting' then
		return 'busy'
	end
	return 'database'
end

function WCore.Player.DeleteCharacter(source, citizenid)
	local license = WCore.Functions.GetIdentifier(source, "license")
	local result = MySQL.scalar.await("SELECT license FROM players where citizenid = ?", { citizenid })
	-- a character that is already gone (deleted meanwhile) is no exploit: nothing to delete
	if result == nil then return false, 'database' end
	if license == result then
		-- the money goes back to the reserve during the purge: without the ledger nothing starts
		if not WCore.Economy.ready() then return false, 'economy_not_ready' end
		local by = ("%s (%s)"):format(GetPlayerName(source) or "?", license)
		-- `requester`: this player's own session is never kicked for its own deletion
		local ok, why, where = WCore.Citizen.Purge(citizenid, by, { requester = source })
		if ok ~= true then
			w.print.error(("DeleteCharacter: %s refused by %s for %s"):format(tostring(why), tostring(where), citizenid))
			return false, selectionReason(why)
		end
		return true
	else
		DropPlayer(source, Lang:t("info.exploit_dropped"))
		TriggerEvent(
			"w_log:server:CreateLog",
			"anticheat",
			"Anti-Cheat",
			"white",
			GetPlayerName(source) .. " Has Been Dropped For Character Deletion Exploit",
			true
		)
		-- the caller still gets an answer: nil read as "accepted" and the creator then polled
		-- five seconds for a row that never goes away
		return false, 'exploit'
	end
end

--- The same purge without the ownership check (console / other resources). Returns true, report |
--- false, reason, resource.
function WCore.Player.ForceDeleteCharacter(citizenid)
	local ok, why, where = WCore.Citizen.Purge(citizenid, "force-delete")
	if ok ~= true then
		w.print.error(("ForceDeleteCharacter: %s refused by %s for %s"):format(tostring(why), tostring(where), tostring(citizenid)))
		return false, why, where
	end
	return true, why
end

-- Inventory Backwards Compatibility

function WCore.Player.SaveInventory(source)
	if GetResourceState("w_inventory") == "missing" then return end
	exports["rsg-inventory"]:SaveInventory(source, false)
end

function WCore.Player.SaveOfflineInventory(PlayerData)
	if GetResourceState("w_inventory") == "missing" then return end
	exports["rsg-inventory"]:SaveInventory(PlayerData, true)
end

function WCore.Player.GetTotalWeight(items)
	if GetResourceState("w_inventory") == "missing" then return end
	return exports["rsg-inventory"]:GetTotalWeight(items)
end

function WCore.Player.GetSlotsByItem(items, itemName)
	if GetResourceState("w_inventory") == "missing" then return end
	return exports["rsg-inventory"]:GetSlotsByItem(items, itemName)
end

function WCore.Player.GetFirstSlotByItem(items, itemName)
	if GetResourceState("w_inventory") == "missing" then return end
	return exports["rsg-inventory"]:GetFirstSlotByItem(items, itemName)
end

-- Util Functions

-- ★ The citizen id is sequential now: 1, 2, 3 ... (server/citizen.lua). The old random form
--   (3 letters + 5 digits) is only read: `wcore_citizenid run` moves existing characters over.
function WCore.Player.CreateCitizenId()
	if WCore.Citizen and WCore.Citizen.Next then return WCore.Citizen.Next() end
	local UniqueFound = false
	local CitizenId = nil
	while not UniqueFound do
		CitizenId = tostring(WCore.Shared.RandomStr(3) .. WCore.Shared.RandomInt(5)):upper()
		local inMemoryTaken = false
		if WCore.Players then
			for _, p in pairs(WCore.Players) do
				if p and p.PlayerData and p.PlayerData.citizenid == CitizenId then
					inMemoryTaken = true
					break
				end
			end
		end
		if not inMemoryTaken then
			local result = MySQL.prepare.await("SELECT COUNT(*) as count FROM players WHERE citizenid = ?", { CitizenId })
			if result == 0 then
				UniqueFound = true
			end
		end
	end
	return CitizenId
end

function WCore.Functions.CreateAccountNumber()
	local UniqueFound = false
	local AccountNumber = nil
	while not UniqueFound do
		AccountNumber = "US0"
			.. math.random(1, 9)
			.. "W"
			.. math.random(1111, 9999)
			.. math.random(1111, 9999)
			.. math.random(11, 99)
		local query = "%" .. AccountNumber .. "%"
		local result = MySQL.prepare.await("SELECT COUNT(*) as count FROM players WHERE charinfo LIKE ?", { query })
		if result == 0 then
			UniqueFound = true
		end
	end
	return AccountNumber
end

function WCore.Player.CreateFingerId()
	local UniqueFound = false
	local FingerId = nil
	while not UniqueFound do
		FingerId = tostring(
			WCore.Shared.RandomStr(2)
				.. WCore.Shared.RandomInt(3)
				.. WCore.Shared.RandomStr(1)
				.. WCore.Shared.RandomInt(2)
				.. WCore.Shared.RandomStr(3)
				.. WCore.Shared.RandomInt(4)
		)
		local query = "%" .. FingerId .. "%"
		local result = MySQL.prepare.await("SELECT COUNT(*) as count FROM `players` WHERE `metadata` LIKE ?", { query })
		if result == 0 then
			UniqueFound = true
		end
	end
	return FingerId
end

function WCore.Player.CreateWalletId()
	local UniqueFound = false
	local WalletId = nil
	while not UniqueFound do
		WalletId = "w_" .. math.random(11111111, 99999999)
		local query = "%" .. WalletId .. "%"
		local result = MySQL.prepare.await("SELECT COUNT(*) as count FROM players WHERE metadata LIKE ?", { query })
		if result == 0 then
			UniqueFound = true
		end
	end
	return WalletId
end

function WCore.Player.CreateSerialNumber()
	local UniqueFound = false
	local SerialNumber = nil
	while not UniqueFound do
		SerialNumber = math.random(11111111, 99999999)
		local query = "%" .. SerialNumber .. "%"
		local result = MySQL.prepare.await("SELECT COUNT(*) as count FROM players WHERE metadata LIKE ?", { query })
		if result == 0 then
			UniqueFound = true
		end
	end
	return SerialNumber
end
