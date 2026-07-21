-- --     AE Kaitun — Smart Play (fail recovery)
-- --     แพ้ติดกัน → เคลียร์กระเป๋า → สุ่ม → ฟีด/evolve → สร้างทีมใหม่จากยูนิตที่แรงสุด

local SmartPlay = {}

local Core = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Core.lua") or loadstring(readfile("expidition/src/Core.lua"))()
local Replicas = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Replicas.lua") or loadstring(readfile("expidition/src/Replicas.lua"))()
local Summon = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Summon.lua") or loadstring(readfile("expidition/src/Summon.lua"))()
local Team = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Team.lua") or loadstring(readfile("expidition/src/Team.lua"))()
local AutoFarmManager = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/AutoFarmManager.lua") or loadstring(readfile("expidition/src/AutoFarmManager.lua"))()

local Nodes = Core.Nodes
local Dependencies = Core.Dependencies
local ReplicatedStorage = Core.ReplicatedStorage
local peek = Core.peek

local isInGame = Replicas.isInGame
local getPlayerData = Replicas.getPlayerData
local getFarmState = AutoFarmManager.getFarmState

local RARITY_RANK = {
	Mythic = 100,
	Exclusive = 95,
	Secret = 90,
	Legendary = 70,
	Epic = 40,
	Rare = 20,
}

local function getSmartCfg()
	local cfg = _G.Settings["Smart Play"]
	if typeof(cfg) ~= "table" then
		cfg = {}
	end
	return {
		Enabled = cfg.Enabled ~= false and _G.Settings["Smart Play Enabled"] ~= false,
		SellWhenFreeSlotsBelow = tonumber(cfg.SellWhenFreeSlotsBelow) or 15,
		SummonRounds = math.max(1, tonumber(cfg.SummonRounds) or 3),
		SummonAmount = tonumber(cfg.SummonAmount) or tonumber(_G.Settings["Summon Amount"]) or 10,
		FeedEquipped = cfg.FeedEquipped ~= false,
		TryEvolve = cfg.TryEvolve ~= false,
		RemakeTeam = cfg.RemakeTeam ~= false,
		PreferBestUnits = cfg.PreferBestUnits ~= false,
		SellDuplicateLegendaries = cfg.SellDuplicateLegendaries == true,
		FeedFoodPerUnit = math.max(1, tonumber(cfg.FeedFoodPerUnit) or 25),
	}
end

local function getInformation()
	local info = Dependencies and Dependencies.Information
	if info then
		return info
	end
	local ok, mod = pcall(function()
		return require(ReplicatedStorage.Shared.Information)
	end)
	if ok then
		return mod
	end
	return nil
end

local function countUnitBag()
	local n = 0
	local data = getPlayerData()
	local unitData = data and data.UnitData
	if typeof(unitData) ~= "table" then
		return 0
	end
	for _, u in pairs(unitData) do
		if typeof(u) == "table" and u.Asset then
			n += 1
		end
	end
	return n
end

-- Limit = base 100 + InventoryExpansions.Unit (Max 500)
local function getUnitBagLimit()
	local base = 100
	local expansions = 0
	pcall(function()
		local info = getInformation()
		if info and info.AssetTypes and info.AssetTypes.Unit and info.AssetTypes.Unit.InventoryLimit then
			base = tonumber(info.AssetTypes.Unit.InventoryLimit.Limit) or base
		elseif info and tonumber(info.UnitInventoryLimit) then
			base = tonumber(info.UnitInventoryLimit)
		end
	end)
	pcall(function()
		local data = peek(Dependencies.PlayerData)
		if typeof(data) ~= "table" then
			data = getPlayerData()
		end
		if typeof(data) == "table" and typeof(data.InventoryExpansions) == "table" then
			expansions = tonumber(data.InventoryExpansions.Unit) or 0
		end
	end)
	return base + expansions
end

local function getBagFreeSlots()
	return math.max(0, getUnitBagLimit() - countUnitBag())
end

local function closeUiNoise()
	pcall(function()
		Nodes.PROMPT_CLOSE_ALL:FireSelf()
	end)
end

local function ensureBagSpace(cfg)
	if isInGame() then
		return 0
	end
	local free = getBagFreeSlots()
	local need = tonumber(cfg.SellWhenFreeSlotsBelow) or 15
	print(("[AE Kaitun] SmartPlay bag %d/%d (free=%d)"):format(countUnitBag(), getUnitBagLimit(), free))
	if free >= need then
		return 0
	end

	print("[AE Kaitun] SmartPlay กระเป๋าใกล้เต็ม — ขาย Rare/Epic")
	local sold = Summon.sellBagByRarities(_G.Settings["Sell Bag Rarities"] or { "Rare", "Epic" })
	task.wait(0.8)
	free = getBagFreeSlots()

	-- ยังแน่น → ขาย Legendary ซ้ำ Asset (เก็บเลเวลสูงสุดไว้)
	if free < need and cfg.SellDuplicateLegendaries then
		local data = getPlayerData()
		local unitData = data and data.UnitData
		local byAsset = {}
		if typeof(unitData) == "table" then
			for id, u in pairs(unitData) do
				if typeof(u) == "table" and u.Asset and not u.Equipped and not u.Locked and not u.Favorite then
					if Summon.getAssetRarity(u.Asset) == "Legendary" then
						local key = tostring(u.Asset)
						byAsset[key] = byAsset[key] or {}
						table.insert(byAsset[key], {
							ID = id,
							Level = tonumber(u.Level) or 1,
						})
					end
				end
			end
		end
		local idMap = {}
		local nDup = 0
		for _, list in pairs(byAsset) do
			if #list > 1 then
				table.sort(list, function(a, b)
					return a.Level > b.Level
				end)
				for i = 2, #list do
					idMap[list[i].ID] = true
					nDup += 1
				end
			end
		end
		if nDup > 0 then
			print("[AE Kaitun] SmartPlay ขาย Legendary ซ้ำ", nDup, "ตัว")
			pcall(function()
				Nodes.ASSET_SELL_TABLE:FireServer("Unit", idMap)
			end)
			task.wait(1.0)
			sold += nDup
		end
	end

	print(("[AE Kaitun] SmartPlay หลังขาย free=%d"):format(getBagFreeSlots()))
	return sold
end

local function getExpFoodInventory()
	local foods = {}
	local data = peek(Dependencies.PlayerData)
	if typeof(data) ~= "table" then
		data = getPlayerData()
	end
	local items = data and data.ItemData
	local info = getInformation()
	if typeof(items) ~= "table" or not info then
		return foods
	end
	for name, entry in pairs(items) do
		local amount = 0
		if typeof(entry) == "table" then
			amount = tonumber(entry.Amount) or 0
		else
			amount = tonumber(entry) or 0
		end
		if amount > 0 then
			local exp = 0
			pcall(function()
				local asset = info:GetAsset(name)
				exp = asset and tonumber(asset.EXP) or 0
			end)
			if exp > 0 then
				table.insert(foods, { Name = name, Amount = amount, EXP = exp })
			end
		end
	end
	-- ใช้ของ EXP สูงก่อน (ยิงครั้งละน้อยกว่า)
	table.sort(foods, function(a, b)
		return a.EXP > b.EXP
	end)
	return foods
end

local function getUnitMaxLevel()
	local maxLv = 100
	pcall(function()
		local info = getInformation()
		if info and info.UnitLevelInfo and tonumber(info.UnitLevelInfo.MaxLevel) then
			maxLv = tonumber(info.UnitLevelInfo.MaxLevel)
		end
	end)
	return maxLv
end

local function getEquippedUnitEntries()
	local list = {}
	local data = getPlayerData()
	local unitData = data and data.UnitData
	if typeof(unitData) ~= "table" then
		return list
	end
	local equippedIds = Team.getEquippedUnitIdSet()
	for id, u in pairs(unitData) do
		if typeof(u) == "table" and u.Asset and equippedIds[tostring(id)] then
			table.insert(list, {
				ID = id,
				Asset = u.Asset,
				Level = tonumber(u.Level) or 1,
				Worthiness = tonumber(u.Worthiness) or 0,
			})
		end
	end
	table.sort(list, function(a, b)
		return a.Level < b.Level
	end)
	return list
end

local function feedEquippedUnits(cfg)
	if not cfg.FeedEquipped or isInGame() then
		return 0
	end
	local foods = getExpFoodInventory()
	if #foods == 0 then
		print("[AE Kaitun] SmartPlay ไม่มีอาหาร EXP — ข้ามฟีด")
		return 0
	end
	local maxLv = getUnitMaxLevel()
	local units = getEquippedUnitEntries()
	local fed = 0
	local perUnit = cfg.FeedFoodPerUnit

	for _, unit in ipairs(units) do
		if unit.Level >= maxLv then
			continue
		end
		-- เลือกอาหารที่ยังมีของ
		local foodMap = {}
		local left = perUnit
		for _, food in ipairs(foods) do
			if left <= 0 then
				break
			end
			local take = math.min(food.Amount, left)
			if take > 0 then
				foodMap[food.Name] = take
				food.Amount -= take
				left -= take
			end
		end
		local any = false
		for _ in pairs(foodMap) do
			any = true
			break
		end
		if not any then
			break
		end
		local ok = pcall(function()
			Nodes.UNIT_FEED:FireServer(unit.ID, foodMap)
		end)
		if ok then
			fed += 1
			print("[AE Kaitun] SmartPlay Feed", unit.Asset, "Lv", unit.Level, "→", foodMap)
		end
		task.wait(0.55)
	end
	print("[AE Kaitun] SmartPlay Feed เสร็จ", fed, "ตัว")
	return fed
end

local function countOwnedAsset(asset, excludeId)
	local n = 0
	local data = getPlayerData()
	local unitData = data and data.UnitData
	if typeof(unitData) ~= "table" then
		return 0
	end
	for id, u in pairs(unitData) do
		if tostring(id) ~= tostring(excludeId) and typeof(u) == "table" and u.Asset == asset then
			if not u.Locked then
				n += 1
			end
		end
	end
	return n
end

local function getItemAmount(name)
	return Summon.getItemAmount(name)
end

local function canAffordEvolveRequirements(unitId, evolvedAsset)
	local info = getInformation()
	if not info or not info.Evolutions then
		return false
	end
	local filtered = nil
	pcall(function()
		filtered = info.Evolutions:GetFilteredRecipe(evolvedAsset)
	end)
	if typeof(filtered) ~= "table" or typeof(filtered.Requirements) ~= "table" then
		-- ไม่มี mat เพิ่ม → ลองได้
		return true
	end
	for _, req in ipairs(filtered.Requirements) do
		if typeof(req) == "table" and req.Asset then
			local need = tonumber(req.Amount) or 1
			local assetInfo = nil
			pcall(function()
				assetInfo = info:GetAsset(req.Asset)
			end)
			local isItem = assetInfo and (assetInfo.EXP ~= nil or assetInfo.SubType == "Food" or assetInfo.Type == "Item")
			-- ถ้าไม่ใช่ unit ใน UnitData ให้นับเป็น item
			local have = 0
			if isItem or (assetInfo and assetInfo.EXP) then
				have = getItemAmount(req.Asset)
			else
				have = countOwnedAsset(req.Asset, unitId)
				-- ถ้า count 0 ลอง item
				if have <= 0 then
					have = getItemAmount(req.Asset)
				end
			end
			if have < need then
				return false
			end
		end
	end
	return true
end

local function tryEvolveEquipped(cfg)
	if not cfg.TryEvolve or isInGame() then
		return 0
	end
	local info = getInformation()
	if not info or not info.Evolutions then
		print("[AE Kaitun] SmartPlay ไม่มี Evolutions module — ข้าม")
		return 0
	end
	local maxLv = getUnitMaxLevel()
	local units = getEquippedUnitEntries()
	local evolved = 0

	for _, unit in ipairs(units) do
		local target = nil
		pcall(function()
			target = info.Evolutions:GetEvolvedUnit(unit.Asset)
		end)
		if not target then
			continue
		end
		-- ฟีดเต็มเลเวลก่อน evolve จะสำเร็จง่ายกว่า
		if unit.Level < math.min(maxLv, 50) then
			continue
		end
		if not canAffordEvolveRequirements(unit.ID, target) then
			print("[AE Kaitun] SmartPlay evolve", unit.Asset, "→", target, "วัตถุดิบไม่ครบ")
			continue
		end
		print("[AE Kaitun] SmartPlay TRY_EVOLVING", unit.Asset, "→", target)
		local ok, result = pcall(function()
			local req = Nodes.TRY_EVOLVING_UNIT:Request(unit.ID, target)
			if req and req.Timeout then
				req:Timeout(6)
			end
			if req and req.Wait then
				return req:Wait()
			end
			return req
		end)
		closeUiNoise()
		if ok and result ~= false then
			evolved += 1
			print("[AE Kaitun] SmartPlay evolve สำเร็จ?", unit.Asset, "→", target)
		else
			warn("[AE Kaitun] SmartPlay evolve ไม่ผ่าน", unit.Asset, result)
		end
		task.wait(1.0)
	end
	return evolved
end

local function smartSummonRounds(cfg)
	if isInGame() then
		return 0
	end
	local sp = _G.Settings["Smart Play"]
	if typeof(sp) == "table" and sp.ForceSummon == false then
		return 0
	end
	if cfg.SummonRounds <= 0 then
		return 0
	end

	Summon.enableFastSummonAlways()
	Summon.startAutoCloseSummonResults()
	ensureBagSpace(cfg)

	local banner = _G.Settings["Summon Banner"] or "Standard"
	local amount = cfg.SummonAmount
	local rounds = cfg.SummonRounds
	local delaySec = math.max(tonumber(_G.Settings["Summon Delay"]) or 4, 2)
	local did = 0

	print(("[AE Kaitun] SmartPlay Summon %s ×%d ×%d รอบ"):format(banner, amount, rounds))
	for i = 1, rounds do
		if isInGame() then
			break
		end
		ensureBagSpace(cfg)
		if getBagFreeSlots() < 5 then
			warn("[AE Kaitun] SmartPlay กระเป๋ายังเต็ม — หยุดสุ่ม")
			break
		end
		print("[AE Kaitun] SmartPlay summon round", i, "/", rounds)
		Summon.summonBanner(banner, amount)
		did += 1
		for _ = 1, math.max(1, math.floor(delaySec / 0.5)) do
			task.wait(0.5)
			Summon.closeSummonUiNow()
		end
		task.wait(0.6)
	end
	Summon.closeSummonUiNow()
	return did
end

local function remakeTeam(cfg)
	if not cfg.RemakeTeam or isInGame() then
		return false
	end
	print("[AE Kaitun] SmartPlay สร้างทีมใหม่ PreferBest=", cfg.PreferBestUnits)
	if Team.ensureMythicTeam then
		return Team.ensureMythicTeam()
	end
	if cfg.PreferBestUnits then
		return Team.remakeBestTeam()
	end
	return Team.ensureTeamReady()
end

-- จุดเข้าหลักหลัง soft-reset / กลับ lobby หลังแพ้
local function runRecovery(reason)
	local cfg = getSmartCfg()
	if not cfg.Enabled then
		print("[AE Kaitun] SmartPlay ปิดอยู่ — ข้าม")
		return false
	end
	if isInGame() then
		warn("[AE Kaitun] SmartPlay อยู่ในแมตช์ — ข้าม")
		return false
	end

	local st = getFarmState()
	st.needSmartPlay = false
	st.smartPlayAt = os.clock()

	print(("[AE Kaitun] === SmartPlay Recovery | %s ==="):format(tostring(reason or "manual")))

	ensureBagSpace(cfg)
	smartSummonRounds(cfg)
	ensureBagSpace(cfg)
	Summon.autoSellBagUnits()
	task.wait(0.5)

	-- ทีมก่อน แล้วค่อยฟีด/evolve ของที่ใส่อยู่
	remakeTeam(cfg)
	task.wait(0.6)
	feedEquippedUnits(cfg)
	task.wait(0.4)
	tryEvolveEquipped(cfg)
	task.wait(0.5)

	-- หลัง evolve อาจได้ตัวใหม่ → ใส่ทีมอีกรอบ
	remakeTeam(cfg)
	print("[AE Kaitun] === SmartPlay เสร็จ — พร้อมคิวใหม่ ===")
	return true
end

local function consumeIfNeeded(reason)
	local st = getFarmState()
	if st.needSmartPlay then
		return runRecovery(reason or "flag")
	end
	-- แพ้รอบล่าสุด (ยังไม่ soft-reset ในแมตช์) ก็รันถ้าตั้ง OnLobbyReturnAfterFail
	local cfg = _G.Settings["Smart Play"]
	local onFail = true
	if typeof(cfg) == "table" and cfg.OnLobbyReturnAfterFail == false then
		onFail = false
	end
	if onFail and st.lastVictory == false and (tonumber(st.failStreak) or 0) >= 3 then
		return runRecovery(reason or "fail-return")
	end
	return false
end

SmartPlay.getSmartCfg = getSmartCfg
SmartPlay.countUnitBag = countUnitBag
SmartPlay.getUnitBagLimit = getUnitBagLimit
SmartPlay.getBagFreeSlots = getBagFreeSlots
SmartPlay.ensureBagSpace = ensureBagSpace
SmartPlay.feedEquippedUnits = feedEquippedUnits
SmartPlay.tryEvolveEquipped = tryEvolveEquipped
SmartPlay.smartSummonRounds = smartSummonRounds
SmartPlay.remakeTeam = remakeTeam
SmartPlay.runRecovery = runRecovery
SmartPlay.consumeIfNeeded = consumeIfNeeded

return SmartPlay
