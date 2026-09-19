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
			local license = WCore.Functions.GetIdentifier(source, "license")
			local PlayerData = MySQL.prepare.await("SELECT * FROM players where citizenid = ?", { citizenid })
			if PlayerData and license == PlayerData.license then
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

	PlayerData.citizenid = PlayerData.citizenid or WCore.Player.CreateCitizenId()
	PlayerData.cid = PlayerData.cid or 1
	PlayerData.money = PlayerData.money or {}
	PlayerData.optin = PlayerData.optin or true
	for moneytype, startamount in pairs(WCore.Config.Money.MoneyTypes) do
		PlayerData.money[moneytype] = PlayerData.money[moneytype] or startamount
	end
	if PlayerData.money.bloodmoney and not PlayerData.money.gold then
		PlayerData.money.gold = PlayerData.money.bloodmoney
	elseif PlayerData.money.gold and not PlayerData.money.bloodmoney then
		PlayerData.money.bloodmoney = PlayerData.money.gold
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

    self.Functions.AddXp = function(skill, amount)
		local skill = skill:lower()
		local amount = tonumber(amount)
		if self.PlayerData.metadata.xp[skill] and amount > 0 then
			self.PlayerData.metadata.xp[skill] = self.PlayerData.metadata.xp[skill] + amount
			self.Functions.UpdateLevelData(skill)
			self.Functions.UpdatePlayerData()
			TriggerEvent('w_log:server:CreateLog', 'levels', 'AddXp', 'lightgreen', '**'..GetPlayerName(self.PlayerData.source) .. ' (citizenid: '..self.PlayerData.citizenid..' | id: '..self.PlayerData.source..')** has received: '..amount..'xp in the skill: '..skill..'. Their current xp amount is: '..self.PlayerData.metadata['xp'][skill])
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
			TriggerEvent('w_log:server:CreateLog', 'levels', 'RemoveXp', 'lightgreen', '**'..GetPlayerName(self.PlayerData.source) .. ' (citizenid: '..self.PlayerData.citizenid..' | id: '..self.PlayerData.source..')** was stripped of: '..amount..'xp in the skill: '..skill..'. Their current xp amount is: '..self.PlayerData.metadata['xp'][skill])
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
			TriggerEvent('w_log:server:CreateLog', 'levels', 'AddXp', 'lightgreen', '**'..GetPlayerName(self.PlayerData.source) .. ' [CitizenID: '..self.PlayerData.citizenid..' | id: '..self.PlayerData.source..']** got '..level..' levels '..amount..' [current level: '..self.PlayerData.metadata.levels[level])
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
			TriggerEvent('w_log:server:CreateLog', 'levels', 'RemoveXp', 'lightgreen', '**'..GetPlayerName(self.PlayerData.source) .. ' [CitizenID: '..self.PlayerData.citizenid..' | id: '..self.PlayerData.source..']** lost '..level..' levels '..amount..' current level: '..self.PlayerData.metadata.levels[level])
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



	function self.Functions.AddMoney(moneytype, amount, reason)
		reason = reason or "unknown"
		moneytype = moneytype:lower()
		amount = tonumber(amount)
		if amount < 0 then return false end
		if moneytype == 'gold' and not self.PlayerData.money['gold'] and self.PlayerData.money['bloodmoney'] then
			moneytype = 'bloodmoney'
		elseif moneytype == 'bloodmoney' and not self.PlayerData.money['bloodmoney'] and self.PlayerData.money['gold'] then
			moneytype = 'gold'
		end
		if not self.PlayerData.money[moneytype] then return false end

		self.PlayerData.money[moneytype] = self.PlayerData.money[moneytype] + amount
		if moneytype == 'gold' and self.PlayerData.money['bloodmoney'] ~= nil then
			self.PlayerData.money['bloodmoney'] = self.PlayerData.money['gold']
		elseif moneytype == 'bloodmoney' and self.PlayerData.money['gold'] ~= nil then
			self.PlayerData.money['gold'] = self.PlayerData.money['bloodmoney']
		end

		if not self.Offline then
			self.Functions.UpdatePlayerData()
			if amount > 100000 then
				TriggerEvent(
					"w_log:server:CreateLog",
					"playermoney",
					"AddMoney",
					"lightgreen",
					"**"
						.. GetPlayerName(self.PlayerData.source)
						.. " (citizenid: "
						.. self.PlayerData.citizenid
						.. " | id: "
						.. self.PlayerData.source
						.. ")** $"
						.. amount
						.. " ("
						.. moneytype
						.. ") added, new "
						.. moneytype
						.. " balance: "
						.. self.PlayerData.money[moneytype]
						.. " reason: "
						.. reason,
					true
				)
			else
				TriggerEvent(
					"w_log:server:CreateLog",
					"playermoney",
					"AddMoney",
					"lightgreen",
					"**"
						.. GetPlayerName(self.PlayerData.source)
						.. " (citizenid: "
						.. self.PlayerData.citizenid
						.. " | id: "
						.. self.PlayerData.source
						.. ")** $"
						.. amount
						.. " ("
						.. moneytype
						.. ") added, new "
						.. moneytype
						.. " balance: "
						.. self.PlayerData.money[moneytype]
						.. " reason: "
						.. reason
				)
			end
			TriggerClientEvent("hud:client:OnMoneyChange", self.PlayerData.source, moneytype, amount, false)
			TriggerEvent("WCore:Server:OnMoneyChange", self.PlayerData.source, moneytype, amount, "add", reason)
		end

		return true
	end

	function self.Functions.RemoveMoney(moneytype, amount, reason)
		reason = reason or "unknown"
		moneytype = moneytype:lower()
		amount = tonumber(amount)
		if amount < 0 then return false end
		if moneytype == 'gold' and not self.PlayerData.money['gold'] and self.PlayerData.money['bloodmoney'] then
			moneytype = 'bloodmoney'
		elseif moneytype == 'bloodmoney' and not self.PlayerData.money['bloodmoney'] and self.PlayerData.money['gold'] then
			moneytype = 'gold'
		end
		if not self.PlayerData.money[moneytype] then return false end

		for _, mtype in pairs(WCore.Config.Money.DontAllowMinus) do
			if mtype == moneytype or (mtype == 'gold' and moneytype == 'bloodmoney') or (mtype == 'bloodmoney' and moneytype == 'gold') then
				if (self.PlayerData.money[moneytype] - amount) < 0 then
					return false
				end
			end
		end
		self.PlayerData.money[moneytype] = self.PlayerData.money[moneytype] - amount
		if moneytype == 'gold' and self.PlayerData.money['bloodmoney'] ~= nil then
			self.PlayerData.money['bloodmoney'] = self.PlayerData.money['gold']
		elseif moneytype == 'bloodmoney' and self.PlayerData.money['gold'] ~= nil then
			self.PlayerData.money['gold'] = self.PlayerData.money['bloodmoney']
		end

		if not self.Offline then
			self.Functions.UpdatePlayerData()
			if amount > 100000 then
				TriggerEvent(
					"w_log:server:CreateLog",
					"playermoney",
					"RemoveMoney",
					"red",
					"**"
						.. GetPlayerName(self.PlayerData.source)
						.. " (citizenid: "
						.. self.PlayerData.citizenid
						.. " | id: "
						.. self.PlayerData.source
						.. ")** $"
						.. amount
						.. " ("
						.. moneytype
						.. ") removed, new "
						.. moneytype
						.. " balance: "
						.. self.PlayerData.money[moneytype]
						.. " reason: "
						.. reason,
					true
				)
			else
				TriggerEvent(
					"w_log:server:CreateLog",
					"playermoney",
					"RemoveMoney",
					"red",
					"**"
						.. GetPlayerName(self.PlayerData.source)
						.. " (citizenid: "
						.. self.PlayerData.citizenid
						.. " | id: "
						.. self.PlayerData.source
						.. ")** $"
						.. amount
						.. " ("
						.. moneytype
						.. ") removed, new "
						.. moneytype
						.. " balance: "
						.. self.PlayerData.money[moneytype]
						.. " reason: "
						.. reason
				)
			end
			TriggerClientEvent("hud:client:OnMoneyChange", self.PlayerData.source, moneytype, amount, true)
			TriggerEvent("WCore:Server:OnMoneyChange", self.PlayerData.source, moneytype, amount, "remove", reason)
		end

		return true
	end

	function self.Functions.SetMoney(moneytype, amount, reason)
		reason = reason or "unknown"
		moneytype = moneytype:lower()
		amount = tonumber(amount)
		if amount < 0 then return false end
		if moneytype == 'gold' and not self.PlayerData.money['gold'] and self.PlayerData.money['bloodmoney'] then
			moneytype = 'bloodmoney'
		elseif moneytype == 'bloodmoney' and not self.PlayerData.money['bloodmoney'] and self.PlayerData.money['gold'] then
			moneytype = 'gold'
		end
		if not self.PlayerData.money[moneytype] then return false end
		local difference = amount - self.PlayerData.money[moneytype]
		self.PlayerData.money[moneytype] = amount
		if moneytype == 'gold' and self.PlayerData.money['bloodmoney'] ~= nil then
			self.PlayerData.money['bloodmoney'] = self.PlayerData.money['gold']
		elseif moneytype == 'bloodmoney' and self.PlayerData.money['gold'] ~= nil then
			self.PlayerData.money['gold'] = self.PlayerData.money['bloodmoney']
		end

		if not self.Offline then
			self.Functions.UpdatePlayerData()
			TriggerEvent(
				"w_log:server:CreateLog",
				"playermoney",
				"SetMoney",
				"green",
				"**"
					.. GetPlayerName(self.PlayerData.source)
					.. " (citizenid: "
					.. self.PlayerData.citizenid
					.. " | id: "
					.. self.PlayerData.source
					.. ")** $"
					.. amount
					.. " ("
					.. moneytype
					.. ") set, new "
					.. moneytype
					.. " balance: "
					.. self.PlayerData.money[moneytype]
					.. " reason: "
					.. reason
			)
			TriggerClientEvent("hud:client:OnMoneyChange", self.PlayerData.source, moneytype, math.abs(difference), difference < 0)
			TriggerEvent("WCore:Server:OnMoneyChange", self.PlayerData.source, moneytype, amount, "set", reason)
		end

		return true
	end

	function self.Functions.GetMoney(moneytype)
		if not moneytype then
			return false
		end
		moneytype = moneytype:lower()
		if moneytype == 'gold' and self.PlayerData.money['gold'] == nil and self.PlayerData.money['bloodmoney'] ~= nil then
			return self.PlayerData.money['bloodmoney']
		elseif moneytype == 'bloodmoney' and self.PlayerData.money['bloodmoney'] == nil and self.PlayerData.money['gold'] ~= nil then
			return self.PlayerData.money['gold']
		end
		return self.PlayerData.money[moneytype]
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

function WCore.Player.Save(source)
	local ped = GetPlayerPed(source)
	local pcoords = GetEntityCoords(ped)
	local PlayerData = WCore.Players[source].PlayerData
	if PlayerData then
		MySQL.insert(
			"INSERT INTO players (citizenid, cid, license, name, money, charinfo, job, gang, position, metadata) VALUES (:citizenid, :cid, :license, :name, :money, :charinfo, :job, :gang, :position, :metadata) ON DUPLICATE KEY UPDATE cid = :cid, name = :name, money = :money, charinfo = :charinfo, job = :job, gang = :gang, position = :position, metadata = :metadata",
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
			}
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
		MySQL.Async.insert(
			"INSERT INTO players (citizenid, cid, license, name, money, charinfo, job, gang, position, metadata) VALUES (:citizenid, :cid, :license, :name, :money, :charinfo, :job, :gang, :position, :metadata) ON DUPLICATE KEY UPDATE cid = :cid, name = :name, money = :money, charinfo = :charinfo, job = :job, gang = :gang, position = :position, metadata = :metadata",
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
			}
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

-- Tables that carry a citizenid and exist in this stack (a table that does not exist rolls the
-- whole transaction back and the character survives). Appearance and clothes rows belong to
-- w_creators, needs to w_hud, the bag to w_inventory: each deletes its own.
local playertables = { -- Add tables as needed
	{ table = "players", column = "citizenid" },
	{ table = "bank_accounts", column = "citizenid" },
	{ table = "stables", column = "charidentifier" }, -- w_stables
}

function WCore.Player.DeleteCharacter(source, citizenid)
	local license = WCore.Functions.GetIdentifier(source, "license")
	local result = MySQL.scalar.await("SELECT license FROM players where citizenid = ?", { citizenid })
	if license == result then
		local query = "DELETE FROM %s WHERE %s = ?"
		local tableCount = #playertables
		local queries = table.create(tableCount, 0)

		for i = 1, tableCount do
			local v = playertables[i]
			queries[i] = { query = query:format(v.table, v.column), values = { citizenid } }
		end

		local ok = MySQL.transaction.await(queries)
		if ok then
			TriggerEvent(
				"w_log:server:CreateLog",
				"joinleave",
				"Character Deleted",
				"red",
				"**" .. GetPlayerName(source) .. "** " .. license .. " deleted **" .. citizenid .. "**.."
			)
		else
			w.print.error(('DeleteCharacter: transaction failed for %s'):format(citizenid))
		end
		return ok == true
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
	end
end

function WCore.Player.ForceDeleteCharacter(citizenid)
	local result = MySQL.scalar.await("SELECT license FROM players where citizenid = ?", { citizenid })
	if result then
		local query = "DELETE FROM %s WHERE %s = ?"
		local tableCount = #playertables
		local queries = table.create(tableCount, 0)
		local Player = WCore.Functions.GetPlayerByCitizenId(citizenid)

		if Player then
			DropPlayer(Player.PlayerData.source, Lang:t("info.character_deleted"))
		end
		for i = 1, tableCount do
			local v = playertables[i]
			queries[i] = { query = query:format(v.table, v.column), values = { citizenid } }
		end

		local ok = MySQL.transaction.await(queries)
		if ok then
			TriggerEvent(
				"w_log:server:CreateLog",
				"joinleave",
				"Character Force Deleted",
				"red",
				"Character **" .. citizenid .. "** got deleted"
			)
		end
		return ok == true
	end
	return false
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

function WCore.Player.CreateCitizenId()
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
