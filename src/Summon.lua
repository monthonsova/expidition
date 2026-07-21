-- --     AE Kaitun — Summon & Inventory Module

local Summon = {}
local Core = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Core.lua") or loadstring(readfile("expidition/src/Core.lua"))()
local Replicas = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Replicas.lua") or loadstring(readfile("expidition/src/Replicas.lua"))()
local Utils = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Utils.lua") or loadstring(readfile("expidition/src/Utils.lua"))()
local AutoFarmManager = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/AutoFarmManager.lua") or loadstring(readfile("expidition/src/AutoFarmManager.lua"))()

local Nodes = Core.Nodes
local Dependencies = Core.Dependencies
local peek = Core.peek

local getCachedInformation = Utils.getCachedInformation

local isInGame = Replicas.isInGame
local getPlayerData = Replicas.getPlayerData
local getAccountLevel = Replicas.getAccountLevel

local getAutoFarm = AutoFarmManager.getAutoFarm

local fastSummonEnabled = false

-- Team.lua ก็ require Summon.lua (ใช้ getSummonTeamUnitsInBag) — ห้าม require Team.lua
-- ตอนโหลดโมดูล (top-level) เพราะจะเกิด circular require ค้าง ต้องดึงแบบ lazy ตอนเรียกใช้จริงเท่านั้น
local function getTeamModule()
    return _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Team.lua")
        or loadstring(readfile("expidition/src/Team.lua"))()
end

local function enableFastSummonAlways()
    if fastSummonEnabled then
        return
    end
    fastSummonEnabled = true
    pcall(function()
        Nodes.CLIENT_CHANGE_SETTING:FireServer("FastSummon", true)
    end)
    print("[AE Kaitun] FastSummon = on")
end

local summonPromptCloserStarted = false
local function startAutoCloseSummonResults()
    if summonPromptCloserStarted then
        return
    end
    summonPromptCloserStarted = true

    local function closePromptSoon(promptId)
        task.delay(0.35, function()
            if promptId then
                pcall(function()
                    Nodes.PROMPT_CLOSE:Fire(promptId)
                end)
                pcall(function()
                    Nodes.PROMPT_CLOSED:FireServer(promptId)
                end)
            end
            pcall(function()
                Nodes.PROMPT_CLOSE_ALL:FireSelf()
            end)
        end)
    end

    pcall(function()
        Nodes.PROMPT_OBTAINED_REWARD_SLOTS:Connect(function(_, _, promptId)
            closePromptSoon(promptId)
        end)
    end)
    pcall(function()
        Nodes.PROMPT_OBTAINED_REWARDS:Connect(function(_, _, promptId)
            closePromptSoon(promptId)
        end)
    end)
end

local function closeSummonUiNow()
    pcall(function()
        Nodes.PROMPT_CLOSE_ALL:FireSelf()
    end)
end

local function getAssetRarity(asset)
    if not asset then
        return nil
    end
    local rarity = nil
    pcall(function()
        local Information = getCachedInformation()
        rarity = Information:GetAssetRarity(asset)
    end)
    return rarity
end

-- รายการ Legendary ในกระเป๋า (UnitData)
local function getLegendaryUnitsInBag()
    local list = {}
    local data = getPlayerData()
    local unitData = data and data.UnitData
    if typeof(unitData) ~= "table" then
        return list
    end
    for id, u in pairs(unitData) do
        if typeof(u) == "table" and u.Asset then
            if getAssetRarity(u.Asset) == "Legendary" then
                table.insert(list, {
                    ID = id,
                    Asset = u.Asset,
                    Level = tonumber(u.Level) or 1,
                    Rarity = "Legendary",
                })
            end
        end
    end
    table.sort(list, function(a, b)
        return a.Level > b.Level
    end)
    return list
end

local function countLegendariesInBag()
    return #getLegendaryUnitsInBag()
end

-- นับ Legendary คนละตัว (Asset ไม่ซ้ำ) — สำเนาตัวเดียวกันไม่นับเพิ่ม
local function countUniqueLegendariesInBag()
    local seen = {}
    local n = 0
    for _, u in ipairs(getLegendaryUnitsInBag()) do
        local asset = tostring(u.Asset)
        if not seen[asset] then
            seen[asset] = true
            n += 1
        end
    end
    return n
end

-- เป้าสุ่มตามเลเวลจาก Settings["Summon Unique Legendary"]
local function getSummonStopUniqueLegendary()
    local lvl = getAccountLevel()
    local rows = _G.Settings["Summon Unique Legendary"]
    if typeof(rows) ~= "table" or #rows == 0 then
        -- fallback: ใช้ MapsByLevel แถวที่ 2 เป็นเกณฑ์เลเวลสูง
        local af = getAutoFarm()
        local unlock = 15
        for _, row in ipairs(af.MapsByLevel) do
            if typeof(row) == "table" and (row.Map == "FlowerForest" or row.MapName == "FlowerForest") then
                unlock = tonumber(row.MinLevel) or 15
                break
            end
        end
        return (lvl >= unlock) and 5 or 4
    end

    local bestCount = 4
    local bestMin = -1
    for _, row in ipairs(rows) do
        if typeof(row) == "table" then
            local minLv = tonumber(row.MinLevel) or 1
            local count = tonumber(row.Count) or 4
            if lvl >= minLv and minLv >= bestMin then
                bestMin = minLv
                bestCount = math.max(1, count)
            end
        end
    end
    return bestCount
end

-- Mythic + Legendary สำหรับใส่ทีมหลังสุ่ม (Mythic มาก่อน)
local function getMythicUnitsInBag()
    local list = {}
    local data = getPlayerData()
    local unitData = data and data.UnitData
    if typeof(unitData) ~= "table" then
        return list
    end
    for id, u in pairs(unitData) do
        if typeof(u) == "table" and u.Asset then
            if getAssetRarity(u.Asset) == "Mythic" then
                table.insert(list, {
                    ID = id,
                    Asset = u.Asset,
                    Level = tonumber(u.Level) or 1,
                    Worthiness = tonumber(u.Worthiness) or 0,
                    Shiny = u.Shiny == true,
                    Rarity = "Mythic",
                })
            end
        end
    end
    table.sort(list, function(a, b)
        if a.Shiny ~= b.Shiny then
            return a.Shiny
        end
        if a.Level ~= b.Level then
            return a.Level > b.Level
        end
        return a.Worthiness > b.Worthiness
    end)
    return list
end

local function getSummonTeamUnitsInBag()
    local mythics = getMythicUnitsInBag()
    local legendaries = getLegendaryUnitsInBag()
    local list = {}
    for _, u in ipairs(mythics) do
        table.insert(list, u)
    end
    for _, u in ipairs(legendaries) do
        table.insert(list, u)
    end
    return list, #mythics, #legendaries
end

-- นับ Mythic คนละตัว (Asset ไม่ซ้ำ)
local function countUniqueMythicsInBag()
    local seen = {}
    local n = 0
    for _, u in ipairs(getMythicUnitsInBag()) do
        local asset = tostring(u.Asset)
        if not seen[asset] then
            seen[asset] = true
            n += 1
        end
    end
    return n
end

-- generic: ยูนิตใน bag ตาม rarity ใดก็ได้ (Secret/Exclusive ได้จากซัมมอนตรงๆ ถ้าแบนเนอร์มี pool นั้น)
local function getUnitsByRarityInBag(rarity)
    local list = {}
    local data = getPlayerData()
    local unitData = data and data.UnitData
    if typeof(unitData) ~= "table" then
        return list
    end
    for id, u in pairs(unitData) do
        if typeof(u) == "table" and u.Asset and getAssetRarity(u.Asset) == rarity then
            table.insert(list, {
                ID = id,
                Asset = u.Asset,
                Level = tonumber(u.Level) or 1,
                Worthiness = tonumber(u.Worthiness) or 0,
                Shiny = u.Shiny == true,
                Rarity = rarity,
            })
        end
    end
    table.sort(list, function(a, b)
        if a.Shiny ~= b.Shiny then
            return a.Shiny
        end
        if a.Level ~= b.Level then
            return a.Level > b.Level
        end
        return a.Worthiness > b.Worthiness
    end)
    return list
end

local function countUniqueByRarityInBag(rarity)
    local seen = {}
    local n = 0
    for _, u in ipairs(getUnitsByRarityInBag(rarity)) do
        local asset = tostring(u.Asset)
        if not seen[asset] then
            seen[asset] = true
            n += 1
        end
    end
    return n
end

-- เป้า Mythic คนละตัวตามเลเวล
local function getSummonStopUniqueMythic()
    local lvl = getAccountLevel()
    local rows = _G.Settings["Summon Unique Mythic"]
    if typeof(rows) ~= "table" or #rows == 0 then
        return (lvl >= 30) and 3 or ((lvl >= 15) and 2 or 1)
    end
    local bestCount = 1
    local bestMin = -1
    for _, row in ipairs(rows) do
        if typeof(row) == "table" then
            local minLv = tonumber(row.MinLevel) or 1
            local count = tonumber(row.Count) or 1
            if lvl >= minLv and minLv >= bestMin then
                bestMin = minLv
                bestCount = math.max(0, count)
            end
        end
    end
    return bestCount
end

local function getItemAmount(itemName)
    local data = peek(Dependencies.PlayerData)
    if typeof(data) ~= "table" then
        data = getPlayerData()
    end
    local items = data and data.ItemData
    if typeof(items) ~= "table" then
        return 0
    end
    local entry = items[itemName]
    if typeof(entry) == "table" then
        return tonumber(entry.Amount) or 0
    end
    return tonumber(entry) or 0
end

-- เพชรสำหรับสุ่ม (เก็บใน ItemData["Gem"].Amount)
local function getGemCount()
    return getItemAmount("Gem")
end

-- ราคาสุ่ม/พูล 1 ครั้ง — ลองอ่านจาก BannerData ก่อน แล้ว fallback config
-- คืน number หรือ nil (nil = ไม่รู้ราคา → ให้ใช้ no-op detection แทน)
local function getSummonCostPerPull(banner)
    banner = banner or _G.Settings["Summon Banner"] or "Standard"
    local override = tonumber(_G.Settings["Summon Cost Per Pull"])
    if override then
        return override
    end
    local cost = nil
    pcall(function()
        local all = peek(Dependencies.BannerData)
        if typeof(all) ~= "table" then
            return
        end
        local bd = all[banner] or all[tostring(banner)]
        if typeof(bd) ~= "table" then
            local okb, peeked = pcall(peek, bd)
            if okb and typeof(peeked) == "table" then
                bd = peeked
            else
                return
            end
        end
        for _, key in ipairs({ "Cost", "Price", "SummonCost", "CostPerSummon", "GemCost", "CostAmount", "SummonPrice" }) do
            local v = bd[key]
            if typeof(v) == "table" then
                local okv, peeked = pcall(peek, v)
                if okv then
                    v = peeked
                end
                if typeof(v) == "table" then
                    v = v.Amount or v.Value or v.Gem or v.Gems
                end
            end
            local n = tonumber(v)
            if n and n > 0 then
                cost = n
                return
            end
        end
    end)
    return cost
end

local function countUnitsByRarity(rarity)
    local n = 0
    local data = peek(Dependencies.PlayerData)
    if typeof(data) ~= "table" then
        data = getPlayerData()
    end
    local unitData = data and data.UnitData
    if typeof(unitData) ~= "table" then
        return 0
    end
    for _, u in pairs(unitData) do
        if typeof(u) == "table" and u.Asset and getAssetRarity(u.Asset) == rarity then
            n += 1
        end
    end
    return n
end


local function getBannerPoolByRarity(banner, rarity)
    banner = banner or _G.Settings["Summon Banner"] or "Standard"
    rarity = rarity or "Mythic"
    local list = {}
    pcall(function()
        local all = peek(Dependencies.BannerData)
        if typeof(all) ~= "table" then
            return
        end
        local bd = all[banner] or all[tostring(banner)]
        if typeof(bd) ~= "table" then
            local okb, peekedBd = pcall(peek, bd)
            if okb and typeof(peekedBd) == "table" then
                bd = peekedBd
            else
                return
            end
        end
        local pool = bd.CurrentPool
        if typeof(pool) ~= "table" or pool[rarity] == nil then
            local okp, peekedPool = pcall(peek, pool)
            if okp and typeof(peekedPool) == "table" then
                pool = peekedPool
            end
        end
        local entries = pool and pool[rarity]
        if typeof(entries) ~= "table" then
            return
        end
        for _, entry in ipairs(entries) do
            if typeof(entry) == "table" and entry.Asset then
                table.insert(list, {
                    Asset = entry.Asset,
                    Chance = tonumber(entry.Chance) or 0,
                    Featured = entry.Featured == true,
                })
            elseif typeof(entry) == "string" then
                table.insert(list, { Asset = entry, Chance = 0, Featured = false })
            end
        end
        table.sort(list, function(a, b)
            if a.Featured ~= b.Featured then
                return a.Featured
            end
            return (a.Chance or 0) > (b.Chance or 0)
        end)
    end)
    return list, banner
end

local function getUnitDisplayName(asset)
    if not asset then
        return "?"
    end
    local name = tostring(asset)
    pcall(function()
        local info = Dependencies.Information:GetAsset(asset)
        if info and typeof(info.Name) == "string" and info.Name ~= "" then
            name = info.Name
        elseif info and typeof(info.DisplayName) == "string" and info.DisplayName ~= "" then
            name = info.DisplayName
        end
    end)
    return name
end

-- ชื่อ Mythic ในแบนเนอร์ (สำหรับ UI) — แค่ชื่อ คั่นด้วย ,
local function getBannerMythicNames(banner)
    local list = getBannerPoolByRarity(banner, "Mythic")
    local names = {}
    for _, row in ipairs(list) do
        table.insert(names, getUnitDisplayName(row.Asset))
    end
    return names
end

-- เซ็ต asset ที่ห้ามขาย (ตามลิสต์ Units + map ชื่อ UI → asset จริง)
local function buildProtectedAssetSet()
    local protected = {}
    for _, name in ipairs(_G.Settings["Units"] or {}) do
        protected[tostring(name)] = true
    end
    local displayMap = {
        ["Ramen Guy"] = "Ichiraku",
        ["Scissor"] = "Riyo",
        ["The Hero"] = "HimmelTheHero",
        ["Forbidden Teacher"] = "Utahime",
        ["Greed"] = "Ban",
        ["Carrot"] = "Goku",
        ["Ice Queen"] = "Gray",
        ["Water Princess"] = "Noelle",
    }
    for disp, asset in pairs(displayMap) do
        if protected[disp] then
            protected[asset] = true
        end
    end
    return protected
end

-- ยิงขายชุด id (ASSET_SELL_TABLE → UNIT_SELL_TABLE → ทีละตัว) คืนจำนวนที่ส่งขาย
local function bulkSellUnitIds(ids)
    if #ids == 0 then
        return 0
    end
    local idMap = {}
    for _, id in ipairs(ids) do
        idMap[id] = true
    end

    local okBulk = pcall(function()
        Nodes.ASSET_SELL_TABLE:FireServer("Unit", idMap)
    end)
    if okBulk then
        print("[AE Kaitun] ส่งขายชุดเดียวแล้ว", #ids, "ตัว (ASSET_SELL_TABLE)")
        task.wait(1.2)
        return #ids
    end

    okBulk = pcall(function()
        Nodes.UNIT_SELL_TABLE:FireServer(idMap)
    end)
    if okBulk then
        print("[AE Kaitun] ส่งขายชุดเดียวแล้ว", #ids, "ตัว (UNIT_SELL_TABLE)")
        task.wait(1.2)
        return #ids
    end

    warn("[AE Kaitun] ขายชุดไม่ได้ — ขายทีละตัว (หน่วง 0.7 วิ)")
    local sold = 0
    for _, id in ipairs(ids) do
        if isInGame() then
            break
        end
        local ok = pcall(function()
            Nodes.UNIT_SELL:FireServer(id)
        end)
        if ok then
            sold += 1
        end
        task.wait(0.7)
    end
    print("[AE Kaitun] ส่งขายแล้ว", sold, "/", #ids, "ตัว")
    task.wait(0.5)
    return sold
end

local function getBagUnitsByRarities(rarities, opts)
    opts = opts or {}
    local want = {}
    for _, r in ipairs(rarities or {}) do
        want[tostring(r)] = true
    end
    local protected = buildProtectedAssetSet()

    local list = {}
    local data = getPlayerData()
    local unitData = data and data.UnitData
    if typeof(unitData) ~= "table" then
        return list
    end
    -- shiny หายาก/สตัทดีกว่า → กันขายเป็นค่าเริ่มต้น (ตั้ง Keep Shiny=false ถ้าอยากขาย)
    -- opts.includeShiny = ยอมขาย shiny (last resort ตอนกระเป๋าเต็มจนสุ่มไม่ได้)
    local keepShiny = (_G.Settings["Keep Shiny"] ~= false) and not opts.includeShiny
    for id, u in pairs(unitData) do
        if typeof(u) == "table" and u.Asset then
            if u.Equipped or u.Locked or u.Favorite then
                continue
            end
            if keepShiny and u.Shiny == true then
                continue
            end
            if protected[u.Asset] then
                continue
            end
            local rarity = getAssetRarity(u.Asset)
            if rarity and want[rarity] then
                table.insert(list, {
                    ID = id,
                    Asset = u.Asset,
                    Rarity = rarity,
                    Shiny = u.Shiny == true,
                })
            end
        end
    end
    return list
end

local function sellBagByRarities(rarities, opts)
    if isInGame() then
        warn("[AE Kaitun] อยู่ในแมตช์ — ไม่ขายกระเป๋า")
        return 0
    end
    rarities = rarities or _G.Settings["Sell Bag Rarities"] or { "Rare", "Epic" }
    local targets = getBagUnitsByRarities(rarities, opts)
    if #targets == 0 then
        print("[AE Kaitun] ไม่มี", table.concat(rarities, "/"), "ในกระเป๋าให้ขาย")
        return 0
    end

    print("[AE Kaitun] ขายกระเป๋า", table.concat(rarities, "/"), "=", #targets, "ตัว")

    local ids = {}
    for _, u in ipairs(targets) do
        table.insert(ids, u.ID)
        print("[AE Kaitun] ขาย", u.Rarity, u.Asset, "id=", u.ID)
    end
    return bulkSellUnitIds(ids)
end

-- ขายยูนิตซ้ำ Asset (เก็บตัวดีสุด: shiny → level → worthiness) — default เฉพาะ Legendary
-- ทำงานในทุกรอบ auto-sell ไม่ต้องรอกระเป๋าเต็ม (respect Keep Shiny + protected list)
local function sellDuplicateUnits(rarities)
    if isInGame() then
        warn("[AE Kaitun] อยู่ในแมตช์ — ไม่ขายตัวซ้ำ")
        return 0
    end
    local want = {}
    for _, r in ipairs(rarities or { "Legendary" }) do
        want[tostring(r)] = true
    end
    local keepShiny = _G.Settings["Keep Shiny"] ~= false
    local protected = buildProtectedAssetSet()

    local data = getPlayerData()
    local unitData = data and data.UnitData
    if typeof(unitData) ~= "table" then
        return 0
    end

    local byAsset = {}
    for id, u in pairs(unitData) do
        if typeof(u) == "table" and u.Asset then
            if not (u.Equipped or u.Locked or u.Favorite or protected[u.Asset]) then
                local rarity = getAssetRarity(u.Asset)
                if rarity and want[rarity] then
                    local key = tostring(u.Asset)
                    byAsset[key] = byAsset[key] or {}
                    table.insert(byAsset[key], {
                        ID = id,
                        Level = tonumber(u.Level) or 1,
                        Worthiness = tonumber(u.Worthiness) or 0,
                        Shiny = u.Shiny == true,
                    })
                end
            end
        end
    end

    local ids = {}
    for asset, list in pairs(byAsset) do
        if #list > 1 then
            -- ตัวดีสุด index 1 (shiny → level → worthiness) → เก็บไว้ ขายที่เหลือ
            table.sort(list, function(a, b)
                if a.Shiny ~= b.Shiny then
                    return a.Shiny
                end
                if a.Level ~= b.Level then
                    return a.Level > b.Level
                end
                return a.Worthiness > b.Worthiness
            end)
            for i = 2, #list do
                -- Keep Shiny → เก็บทุกตัว shiny (ไม่ขายแม้ซ้ำ)
                if not (keepShiny and list[i].Shiny) then
                    table.insert(ids, list[i].ID)
                    print(("[AE Kaitun] ขายตัวซ้ำ %s Lv%d%s"):format(
                        asset, list[i].Level, list[i].Shiny and " ★" or ""
                    ))
                end
            end
        end
    end

    if #ids == 0 then
        return 0
    end
    print("[AE Kaitun] ขายตัวซ้ำ", table.concat(rarities or { "Legendary" }, "/"), "=", #ids, "ตัว")
    return bulkSellUnitIds(ids)
end

local function sellDuplicateLegendaries()
    if _G.Settings["Sell Duplicate Legendaries"] == false then
        return 0
    end
    return sellDuplicateUnits(_G.Settings["Dedup Rarities"] or { "Legendary" })
end

local function autoSellBagUnits()
    if not _G.Settings["Auto Sell Bag"] then
        return 0
    end
    local sold = sellBagByRarities(_G.Settings["Sell Bag Rarities"])
    -- ขาย Legendary (หรือเรตที่ตั้ง) ที่ซ้ำ Asset ด้วยทุกรอบ ไม่รอกระเป๋าเต็ม
    sold += sellDuplicateLegendaries()
    return sold
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

local function getUnitBagLimit()
    local base = 100
    local expansions = 0
    pcall(function()
        local Information = getCachedInformation()
        if Information and Information.AssetTypes and Information.AssetTypes.Unit then
            local lim = Information.AssetTypes.Unit.InventoryLimit
            if lim then
                base = tonumber(lim.Limit) or base
            end
        elseif Information and tonumber(Information.UnitInventoryLimit) then
            base = tonumber(Information.UnitInventoryLimit)
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

local function ensureBagSpaceBeforeSummon(minFree)
    minFree = minFree or 12
    local free = getUnitBagLimit() - countUnitBag()
    if free >= minFree then
        return free
    end
    print(("[AE Kaitun] กระเป๋าใกล้เต็ม (%d/%d free=%d) — ขายก่อนสุ่ม"):format(
        countUnitBag(), getUnitBagLimit(), free
    ))
    -- บังคับขาย Rare/Epic แม้ Auto Sell ปิด (กันสุ่มไม่ได้ตอนกระเป๋าเต็ม)
    local rarities = _G.Settings["Sell Bag Rarities"] or { "Rare", "Epic" }
    sellBagByRarities(rarities)
    task.wait(0.8)
    free = getUnitBagLimit() - countUnitBag()
    -- ยังไม่พอ + Keep Shiny กันไว้หมด → last resort: ขาย shiny เรตต่ำ (Rare/Epic) ด้วย
    if free < minFree and _G.Settings["Keep Shiny"] ~= false then
        print("[AE Kaitun] กระเป๋ายังเต็ม — ขาย shiny เรตต่ำเป็นทางเลือกสุดท้าย")
        sellBagByRarities(rarities, { includeShiny = true })
        task.wait(0.8)
        free = getUnitBagLimit() - countUnitBag()
    end
    return free
end

-- ช่อง hotbar ที่เปิดแล้ว (ไม่ Disabled / หรือเลเวลผู้เล่นถึงแล้ว)

local function summonBanner(banner, amount)
    local ok, err = pcall(function()
        Nodes.BANNER_SUMMON:FireServer(banner, amount)
    end)
    if not ok then
        warn("[AE Kaitun] Summon error:", err)
    end
    return ok
end

local function printBannerMythics(banner)
    local list, name = getBannerPoolByRarity(banner, "Mythic")
    if #list == 0 then
        print("[AE Kaitun] Banner", name, "| Mythic pool: (ยังโหลดไม่ครบ / ว่าง)")
        return list
    end
    local names = getBannerMythicNames(banner)
    print("[AE Kaitun] Banner", name, "| Mythic:", table.concat(names, ", "))
    return list
end

local function autoSummonAfterCodes()
    if not _G.Settings["Auto Summon"] then
        return
    end
    if isInGame() then
        return
    end

    enableFastSummonAlways()
    startAutoCloseSummonResults()

    local stopLeg = getSummonStopUniqueLegendary()
    local stopMythic = getSummonStopUniqueMythic()
    local haveLeg = countUniqueLegendariesInBag()
    local haveMythic = countUniqueMythicsInBag()
    local lvl = getAccountLevel()
    -- normalize ผ่าน Team.getTeamMode() → "SmartSecret"→Secret, "Smart"/"Auto"→Mythic (กัน Summon/Team ไม่ตรงกัน)
    local teamModeModule = getTeamModule()
    local teamMode = (teamModeModule and teamModeModule.getTeamMode and teamModeModule.getTeamMode())
        or tostring(_G.Settings["Team Mode"] or "Mythic")

    -- Secret mode: Secret/Exclusive ได้ทั้งจากซัมมอนตรงๆ (ถ้าแบนเนอร์มี pool) และ evolve Mythic
    -- นับตัวหายากที่ใส่ทีมได้ทั้งหมด (Secret+Exclusive+Mythic) เทียบเป้า
    local function shouldStopSummonMythicFirst()
        if teamMode == "Secret" then
            local target = (stopMythic > 0) and stopMythic or stopLeg
            local uniqueHigh = countUniqueByRarityInBag("Secret")
                + countUniqueByRarityInBag("Exclusive")
                + countUniqueMythicsInBag()
            return uniqueHigh >= target
        end
        if teamMode == "Mythic" and stopMythic > 0 then
            return haveMythic >= stopMythic
        end
        return haveLeg >= stopLeg
    end

    if shouldStopSummonMythicFirst() then
        print(("[AE Kaitun] เป้าสุ่มครบ UniqueMythic=%d/%d UniqueLeg=%d/%d (Lv %d) — ข้ามสุ่ม"):format(
            haveMythic, stopMythic, haveLeg, stopLeg, lvl
        ))
        local Team = getTeamModule()
        if Team.ensureTeamReady then
            Team.ensureTeamReady()
        elseif Team.ensureMythicTeam then
            Team.ensureMythicTeam()
        else
            Team.equipLegendariesToHotbar()
            Team.fillEmptyHotbarWithLegendaries()
        end
        return
    end

    local banner = _G.Settings["Summon Banner"] or "Standard"
    local amount = tonumber(_G.Settings["Summon Amount"]) or 10
    local rounds = tonumber(_G.Settings["Summon Rounds"]) or 8
    local delaySec = math.max(tonumber(_G.Settings["Summon Delay"]) or 4, 2)

    -- เช็คเพชรก่อนสุ่ม: ไม่พอ = ข้ามเลย (ถ้ารู้ราคา) กันยิงรัวเสียเวลา
    local skipIfNoGems = _G.Settings["Skip Summon If No Gems"] ~= false
    local costPerPull = getSummonCostPerPull(banner)
    if skipIfNoGems and costPerPull then
        local gems = getGemCount()
        if gems < costPerPull then
            print(("[AE Kaitun] เพชรไม่พอสุ่ม (มี %d < ราคา %d/ครั้ง) — ข้ามสุ่ม"):format(gems, costPerPull))
            local Team = getTeamModule()
            if Team.ensureTeamReady then
                Team.ensureTeamReady()
            elseif Team.ensureMythicTeam then
                Team.ensureMythicTeam()
            end
            return
        end
        print(("[AE Kaitun] เพชร %d | ราคา ~%d/ครั้ง"):format(gems, costPerPull))
    end

    print("[AE Kaitun] Summon", banner, "×" .. amount, "สูงสุด", rounds, "รอบ | TeamMode=", teamMode)
    print(("[AE Kaitun] เป้า Unique Mythic=%d | Unique Leg=%d | มีแล้ว M=%d L=%d | Lv %d"):format(
        stopMythic, stopLeg, haveMythic, haveLeg, lvl
    ))
    printBannerMythics(banner)
    if teamMode == "Secret" then
        local secPool = select(1, getBannerPoolByRarity(banner, "Secret"))
        local exPool = select(1, getBannerPoolByRarity(banner, "Exclusive"))
        print(("[AE Kaitun] Secret mode | แบนเนอร์นี้มี pool Secret=%d Exclusive=%d | มีในกระเป๋า Secret=%d Exclusive=%d")
            :format(#secPool, #exPool, countUniqueByRarityInBag("Secret"), countUniqueByRarityInBag("Exclusive")))
        if #secPool == 0 and #exPool == 0 then
            print("[AE Kaitun] แบนเนอร์นี้ไม่มี Secret/Exclusive ในพูล → ต้อง evolve Mythic เอา (SmartPlay จัดให้)")
        end
    end
    ensureBagSpaceBeforeSummon(amount + 5)
    task.wait(1)

    for i = 1, rounds do
        if isInGame() then
            break
        end

        haveLeg = countUniqueLegendariesInBag()
        haveMythic = countUniqueMythicsInBag()
        if shouldStopSummonMythicFirst() then
            print(("[AE Kaitun] เป้าสุ่มครบ M=%d/%d L=%d/%d — หยุดสุ่ม"):format(
                haveMythic, stopMythic, haveLeg, stopLeg
            ))
            break
        end

        ensureBagSpaceBeforeSummon(amount + 2)
        if (getUnitBagLimit() - countUnitBag()) < 3 then
            warn("[AE Kaitun] กระเป๋ายังเต็มหลังขาย — หยุดสุ่ม")
            break
        end

        -- เพชรไม่พอกลางทาง → หยุด (ถ้ารู้ราคา)
        if skipIfNoGems and costPerPull then
            local gems = getGemCount()
            if gems < costPerPull then
                print(("[AE Kaitun] เพชรหมด (เหลือ %d < %d) — หยุดสุ่ม"):format(gems, costPerPull))
                break
            end
        end

        print(("[AE Kaitun] Summon round %d/%d | Unique M=%d/%d L=%d/%d"):format(
            i, rounds, haveMythic, stopMythic, haveLeg, stopLeg
        ))

        -- no-op detection: จำนวนยูนิตก่อนสุ่ม (กันเพชรหมดแต่ไม่รู้ราคา)
        local bagBefore = countUnitBag()
        local spaceBefore = getUnitBagLimit() - bagBefore
        summonBanner(banner, amount)

        for _ = 1, math.max(1, math.floor(delaySec / 0.5)) do
            task.wait(0.5)
            closeSummonUiNow()
        end

        task.wait(0.8)
        -- สุ่มแล้วยูนิตไม่เพิ่มทั้งที่มีที่ว่างพอ = สุ่มไม่สำเร็จ (เพชรหมด) → หยุด
        if spaceBefore >= math.min(amount, 3) and countUnitBag() <= bagBefore then
            print("[AE Kaitun] สุ่มแล้วยูนิตไม่เพิ่ม (น่าจะเพชรหมด) — หยุดสุ่ม")
            break
        end
        haveLeg = countUniqueLegendariesInBag()
        haveMythic = countUniqueMythicsInBag()
        if haveMythic > 0 then
            print("[AE Kaitun] มี Mythic คนละตัว", haveMythic, "ตัวในกระเป๋า")
        end
        if shouldStopSummonMythicFirst() then
            print(("[AE Kaitun] เป้าสุ่มครบหลังรอบ %d — หยุด"):format(i))
            break
        end
    end

    closeSummonUiNow()
    task.wait(0.5)
    local Team = getTeamModule()
    if Team.ensureTeamReady then
        Team.ensureTeamReady()
    elseif Team.ensureMythicTeam then
        Team.ensureMythicTeam()
    else
        Team.equipLegendariesToHotbar()
        Team.fillEmptyHotbarWithLegendaries()
    end
end



Summon.enableFastSummonAlways = enableFastSummonAlways
Summon.startAutoCloseSummonResults = startAutoCloseSummonResults
Summon.closeSummonUiNow = closeSummonUiNow
Summon.getAssetRarity = getAssetRarity
Summon.getLegendaryUnitsInBag = getLegendaryUnitsInBag
Summon.countLegendariesInBag = countLegendariesInBag
Summon.countUniqueLegendariesInBag = countUniqueLegendariesInBag
Summon.getSummonStopUniqueLegendary = getSummonStopUniqueLegendary
Summon.getMythicUnitsInBag = getMythicUnitsInBag
Summon.countUniqueMythicsInBag = countUniqueMythicsInBag
Summon.getSummonStopUniqueMythic = getSummonStopUniqueMythic
Summon.getUnitsByRarityInBag = getUnitsByRarityInBag
Summon.countUniqueByRarityInBag = countUniqueByRarityInBag
Summon.getSummonTeamUnitsInBag = getSummonTeamUnitsInBag
Summon.getItemAmount = getItemAmount
Summon.getGemCount = getGemCount
Summon.getSummonCostPerPull = getSummonCostPerPull
Summon.countUnitsByRarity = countUnitsByRarity
Summon.getBannerPoolByRarity = getBannerPoolByRarity
Summon.getUnitDisplayName = getUnitDisplayName
Summon.getBannerMythicNames = getBannerMythicNames
Summon.printBannerMythics = printBannerMythics
Summon.summonBanner = summonBanner
Summon.autoSummonAfterCodes = autoSummonAfterCodes
Summon.getBagUnitsByRarities = getBagUnitsByRarities
Summon.sellBagByRarities = sellBagByRarities
Summon.autoSellBagUnits = autoSellBagUnits
Summon.sellDuplicateUnits = sellDuplicateUnits
Summon.sellDuplicateLegendaries = sellDuplicateLegendaries
Summon.countUnitBag = countUnitBag
Summon.getUnitBagLimit = getUnitBagLimit
Summon.ensureBagSpaceBeforeSummon = ensureBagSpaceBeforeSummon

return Summon
