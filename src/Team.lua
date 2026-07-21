-- --     AE Kaitun — Team & Hotbar Management Module

local Team = {}
local Core = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Core.lua") or loadstring(readfile("expidition/src/Core.lua"))()
local Replicas = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Replicas.lua") or loadstring(readfile("expidition/src/Replicas.lua"))()
local Summon = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Summon.lua") or loadstring(readfile("expidition/src/Summon.lua"))()

local Nodes = Core.Nodes
local Dependencies = Core.Dependencies
local ReplicatedStorage = Core.ReplicatedStorage
local peek = Core.peek

local getAccountLevel = Replicas.getAccountLevel
local getPlayerData = Replicas.getPlayerData
local getEquippedCount = Replicas.getEquippedCount
local getSummonTeamUnitsInBag = Summon.getSummonTeamUnitsInBag

local function getUnlockedHotbarSlots()
    local open = {}
    local hotbar = peek(Dependencies.HotbarState)
    local maxSlots = (hotbar and tonumber(hotbar.MaxSlots)) or 6
    local slots = hotbar and hotbar.Slots
    local playerLvl = 1
    pcall(function()
        playerLvl = getAccountLevel()
    end)

    for i = 1, maxSlots do
        local data = nil
        if typeof(slots) == "table" then
            data = slots[tostring(i)] or slots[i]
        end
        local disabled = typeof(data) == "table" and data.Disabled == true
        -- บางที Disabled ค้างทั้งที่เลเวลถึงแล้ว — เช็ค SlotLevels ประกอบ
        local needLv = 0
        pcall(function()
            local levels = hotbar and hotbar.SlotLevels
            if typeof(levels) == "table" then
                needLv = tonumber(levels[tostring(i)] or levels[i]) or 0
            end
        end)
        if needLv > 0 and playerLvl >= needLv then
            disabled = false
        end
        if not disabled then
            table.insert(open, i)
        end
    end

    -- ยังไม่มี HotbarState → ประมาณช่องตามเลเวล (1-2 เริ่มต้น, +1 ทุก ~5 เลเวลถึง 6)
    if #open == 0 then
        local approx = 2
        if playerLvl >= 5 then approx = 3 end
        if playerLvl >= 10 then approx = 4 end
        if playerLvl >= 15 then approx = 5 end
        if playerLvl >= 20 then approx = 6 end
        for i = 1, math.min(approx, maxSlots) do
            table.insert(open, i)
        end
    end
    return open
end

local function getEmptyUnlockedSlots()
    local empty = {}
    local hotbar = peek(Dependencies.HotbarState)
    local slots = hotbar and hotbar.Slots
    for _, i in ipairs(getUnlockedHotbarSlots()) do
        local data = typeof(slots) == "table" and (slots[tostring(i)] or slots[i]) or nil
        local id = typeof(data) == "table" and data.ID or nil
        if id == nil or id == "" or id == false then
            table.insert(empty, i)
        end
    end
    return empty
end

local function getEquippedUnitIdSet()
    local set = {}
    local data = getPlayerData()
    local unitData = data and data.UnitData
    if typeof(unitData) == "table" then
        for id, u in pairs(unitData) do
            if typeof(u) == "table" and u.Equipped then
                set[tostring(id)] = true
            end
        end
    end
    local hotbar = peek(Dependencies.HotbarState)
    local slots = hotbar and hotbar.Slots
    if typeof(slots) == "table" then
        for _, data in pairs(slots) do
            if typeof(data) == "table" and data.ID then
                set[tostring(data.ID)] = true
            end
        end
    end
    return set
end

-- Asset ที่อยู่บน hotbar แล้ว (กันเติม Noelle ซ้ำแทน Utahime)
local function getEquippedAssetSet()
    local set = {}
    local data = getPlayerData()
    local unitData = data and data.UnitData
    if typeof(unitData) == "table" then
        for _, u in pairs(unitData) do
            if typeof(u) == "table" and u.Equipped and u.Asset then
                set[tostring(u.Asset)] = true
            end
        end
    end
    local hotbar = peek(Dependencies.HotbarState)
    local slots = hotbar and hotbar.Slots
    if typeof(slots) == "table" and typeof(unitData) == "table" then
        for _, data in pairs(slots) do
            if typeof(data) == "table" and data.ID then
                local u = unitData[data.ID] or unitData[tostring(data.ID)]
                if typeof(u) == "table" and u.Asset then
                    set[tostring(u.Asset)] = true
                end
            end
        end
    end
    return set
end

-- เติมช่องว่างด้วย Mythic ก่อน แล้วค่อย Legendary (ไม่ถอดของที่มีอยู่, ไม่ซ้ำ Asset)
local function fillEmptyHotbarWithLegendaries()
    task.wait(0.4)
    local empty = getEmptyUnlockedSlots()
    if #empty == 0 then
        print("[AE Kaitun] Hotbar เต็มแล้ว — ไม่เติม Mythic/Legendary")
        return 0
    end

    local usedId = getEquippedUnitIdSet()
    local usedAsset = getEquippedAssetSet()
    local pool = getSummonTeamUnitsInBag()
    local filled = 0
    local li = 1

    for _, slot in ipairs(empty) do
        while li <= #pool do
            local cand = pool[li]
            local id = tostring(cand.ID)
            local asset = tostring(cand.Asset)
            if usedId[id] or usedAsset[asset] then
                li += 1
            else
                break
            end
        end
        if li > #pool then
            break
        end
        local unit = pool[li]
        usedId[tostring(unit.ID)] = true
        usedAsset[tostring(unit.Asset)] = true
        print("[AE Kaitun] เติม", unit.Rarity, unit.Asset, "→ slot", slot)
        pcall(function()
            Nodes.UNIT_EQUIP:FireServer(unit.ID, tostring(slot))
        end)
        filled += 1
        li += 1
        task.wait(0.35)
    end

    print("[AE Kaitun] เติม Mythic/Legendary ช่องว่าง =", filled, "/", #empty)
    return filled
end

-- ใส่ Mythic+Legendary ลง hotbar (Mythic ก่อน) เมื่อไม่มี Settings.Units
local function equipLegendariesToHotbar()
    if #(_G.Settings["Units"] or {}) > 0 then
        -- มี Units แล้ว — จะเติมช่องว่างทีหลังใน equipUnitsFromList (รวม Mythic)
        return false
    end

    local pool, mythicN, legN = getSummonTeamUnitsInBag()
    if #pool < 1 then
        print("[AE Kaitun] ไม่มี Mythic/Legendary ในกระเป๋า — ยังไม่ใส่ hotbar")
        return false
    end
    if #pool < 2 and mythicN == 0 then
        print("[AE Kaitun] Legendary ในกระเป๋า =", legN, "(ต้อง >= 2) — ยังไม่ใส่ hotbar")
        return false
    end

    local slots = getUnlockedHotbarSlots()
    print("[AE Kaitun] ใส่ทีม Mythic=", mythicN, "| Legendary=", legN, "→ hotbar", #slots, "ช่อง")

    pcall(function()
        Nodes.UNIT_UNEQUIP_ALL:FireServer()
    end)
    task.wait(0.5)

    local n = math.min(#pool, #slots)
    for i = 1, n do
        local unit = pool[i]
        local slot = slots[i]
        print("[AE Kaitun] Equip", unit.Rarity, unit.Asset, "→ slot", slot, "id=", unit.ID)
        pcall(function()
            Nodes.UNIT_EQUIP:FireServer(unit.ID, tostring(slot))
        end)
        task.wait(0.4)
    end

    task.wait(0.5)
    print("[AE Kaitun] Equipped after Mythic/Legendary:", getEquippedCount())
    return true
end


local function unequipAll()
    pcall(function()
        Nodes.UNIT_UNEQUIP_ALL:FireServer()
    end)
    task.wait(0.5)
end

local function loadTeam()
    local idx = _G.Settings["Team Index"]
    local withEq = _G.Settings["Include Equipment"]
    print("[AE Kaitun] LoadTeam", idx, "equipment=", withEq)
    Nodes.UNIT_LOAD_TEAM:FireServer(idx, withEq)
    task.wait(1)
end

local function equipUnitsFromList()
    local list = _G.Settings["Units"] or {}
    if #list == 0 then
        warn("[AE Kaitun] Settings.Units ว่าง — ข้าม Equip")
        return false
    end

    -- แปลงชื่อ UI → Asset (ดู UnitNames.lua เป็นคู่มือ — ไม่โหลดไฟล์)
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

    local resolved = {}
    for _, name in ipairs(list) do
        table.insert(resolved, displayMap[name] or name)
    end

    print("[AE Kaitun] Equip ตาม Units:", table.concat(list, ", "), "→", table.concat(resolved, ", "))
    unequipAll()

    local data = getPlayerData()
    local unitData = (data and data.UnitData) or {}
    local slots = getUnlockedHotbarSlots()
    local slotIdx = 1
    local Information = nil
    pcall(function()
        Information = require(ReplicatedStorage.Shared.Information)
    end)

    for _, name in ipairs(resolved) do
        if slotIdx > #slots then
            break
        end
        local foundId = nil
        for id, u in pairs(unitData) do
            if typeof(u) == "table" and u.Asset then
                local asset = u.Asset
                local display = nil
                if Information then
                    pcall(function()
                        display = Information:GetAssetDisplayName(asset)
                    end)
                end
                if asset == name or u.Name == name or tostring(id) == name or display == name then
                    foundId = id
                    break
                end
            end
        end

        if foundId then
            local slot = slots[slotIdx]
            print("[AE Kaitun] Equip", name, "→", foundId, "slot", slot)
            Nodes.UNIT_EQUIP:FireServer(foundId, tostring(slot))
            slotIdx += 1
            task.wait(0.35)
        else
            warn("[AE Kaitun] ไม่พบยูนิต:", name)
        end
    end

    -- ช่องที่เหลือ → เติม Mythic ก่อน แล้ว Legendary
    fillEmptyHotbarWithLegendaries()
    return slotIdx > 1
end

local RARITY_RANK = {
    Mythic = 100,
    Exclusive = 95,
    Secret = 90,
    Legendary = 70,
    Epic = 40,
    Rare = 20,
}

local function getSmartMythicCfg()
    local cfg = _G.Settings["Smart Mythic Team"]
    if typeof(cfg) ~= "table" then
        cfg = {}
    end
    return {
        Enabled = cfg.Enabled ~= false,
        PreferMythic = cfg.PreferMythic ~= false,
        FillWithLegendary = cfg.FillWithLegendary ~= false,
        ReplaceWeakUnits = cfg.ReplaceWeakUnits ~= false,
        PreferShiny = cfg.PreferShiny ~= false,
        PreferHighWorthiness = cfg.PreferHighWorthiness ~= false,
    }
end

local function getTeamMode()
    local mode = tostring(_G.Settings["Team Mode"] or "Mythic")
    if mode == "Smart" or mode == "Auto" then
        return "Mythic"
    end
    return mode
end

local function unitScore(entry, cfg)
    cfg = cfg or getSmartMythicCfg()
    local score = (entry.Rank or 0) * 1000000
    if cfg.PreferShiny and entry.Shiny then
        score += 50000
    end
    score += (entry.Level or 1) * 100
    if cfg.PreferHighWorthiness then
        score += math.min(tonumber(entry.Worthiness) or 0, 999)
    end
    return score
end

-- ไอดีใหม่ยังไม่มี Ichiraku/Riyo ในลิสต์ → ใส่อย่างน้อยยูนิตที่มีในกระเป๋า (starter ก็ได้)
local function equipAnyUnitsFallback()
    local data = getPlayerData()
    local unitData = data and data.UnitData
    if typeof(unitData) ~= "table" then
        return 0
    end
    local slots = getUnlockedHotbarSlots()
    local candidates = {}
    for id, u in pairs(unitData) do
        if typeof(u) == "table" and u.Asset then
            local rarity = Summon.getAssetRarity(u.Asset) or "Rare"
            table.insert(candidates, {
                ID = id,
                Asset = u.Asset,
                Level = tonumber(u.Level) or 1,
                Worthiness = tonumber(u.Worthiness) or 0,
                Shiny = u.Shiny == true,
                Rank = RARITY_RANK[rarity] or 10,
                Rarity = rarity,
            })
        end
    end
    table.sort(candidates, function(a, b)
        return unitScore(a) > unitScore(b)
    end)

    local equipped = 0
    local used = getEquippedUnitIdSet()
    local usedAsset = {}
    for _, cand in ipairs(candidates) do
        if equipped >= #slots then
            break
        end
        local id = tostring(cand.ID)
        local asset = tostring(cand.Asset)
        if not used[id] and not usedAsset[asset] then
            local slot = slots[equipped + 1]
            print("[AE Kaitun] Fallback equip", cand.Asset, "→ slot", slot)
            pcall(function()
                Nodes.UNIT_EQUIP:FireServer(cand.ID, tostring(slot))
            end)
            used[id] = true
            usedAsset[asset] = true
            equipped += 1
            task.wait(0.3)
        end
    end
    return equipped
end

-- จัดอันดับยูนิตในกระเป๋า: Mythic ก่อน → shiny → level → worthiness (ไม่ซ้ำ Asset)
local function getBestUnitsForTeam(limit, opts)
    limit = limit or 6
    opts = opts or {}
    local cfg = getSmartMythicCfg()
    local mythicOnly = opts.MythicOnly == true
    local allowLegendary = opts.AllowLegendary
    if allowLegendary == nil then
        allowLegendary = cfg.FillWithLegendary ~= false
    end

    local list = {}
    local data = getPlayerData()
    local unitData = data and data.UnitData
    if typeof(unitData) ~= "table" then
        return list
    end
    for id, u in pairs(unitData) do
        if typeof(u) == "table" and u.Asset then
            local rarity = Summon.getAssetRarity(u.Asset) or "Rare"
            local rank = RARITY_RANK[rarity] or 10
            if mythicOnly and rarity ~= "Mythic" then
                continue
            end
            if not allowLegendary and rarity == "Legendary" then
                continue
            end
            -- ทีม smart: ไม่ใส่ Rare/Epic (ยกเว้นกระเป๋าไม่มีอะไรเลย — จัดการตอน fallback)
            if rank < RARITY_RANK.Legendary and not opts.AllowWeak then
                continue
            end
            table.insert(list, {
                ID = id,
                Asset = u.Asset,
                Level = tonumber(u.Level) or 1,
                Worthiness = tonumber(u.Worthiness) or 0,
                Shiny = u.Shiny == true,
                Rarity = rarity,
                Rank = rank,
            })
        end
    end
    table.sort(list, function(a, b)
        return unitScore(a, cfg) > unitScore(b, cfg)
    end)
    local out = {}
    local seen = {}
    for _, u in ipairs(list) do
        local key = tostring(u.Asset)
        if not seen[key] then
            seen[key] = true
            table.insert(out, u)
            if #out >= limit then
                break
            end
        end
    end
    return out
end

-- ถอดทีมเก่า → ใส่ยูนิตแรงสุดในกระเป๋า (หลังแพ้ติด / SmartPlay)
local function remakeBestTeam()
    local slots = getUnlockedHotbarSlots()
    local pool = getBestUnitsForTeam(#slots)
    if #pool == 0 then
        pool = getBestUnitsForTeam(#slots, { AllowWeak = true })
    end
    if #pool == 0 then
        warn("[AE Kaitun] remakeBestTeam — กระเป๋าว่าง")
        return false
    end

    print("[AE Kaitun] Remake Best Team →", #pool, "ตัว /", #slots, "ช่อง")
    unequipAll()
    task.wait(0.35)

    local n = math.min(#pool, #slots)
    for i = 1, n do
        local unit = pool[i]
        local slot = slots[i]
        print("[AE Kaitun] Best Equip", unit.Rarity, unit.Asset, "Lv", unit.Level,
            unit.Shiny and "★Shiny" or "", "→ slot", slot)
        pcall(function()
            Nodes.UNIT_EQUIP:FireServer(unit.ID, tostring(slot))
        end)
        task.wait(0.35)
    end

    task.wait(0.4)
    local equipped = getEquippedCount()
    print("[AE Kaitun] Remake Best Team equipped:", equipped)
    return equipped > 0
end

-- Smart Mythic Team: ใส่ Mythic คนละตัวให้เต็มก่อน แล้วค่อย Legendary
local function buildMythicTeam()
    local cfg = getSmartMythicCfg()
    local slots = getUnlockedHotbarSlots()
    if #slots == 0 then
        warn("[AE Kaitun] ไม่มีช่อง hotbar — รอเลเวล")
        return false
    end

    local pool = getBestUnitsForTeam(#slots, {
        AllowLegendary = cfg.FillWithLegendary ~= false,
    })
    if #pool == 0 then
        pool = getBestUnitsForTeam(#slots, { AllowWeak = true })
    end
    if #pool == 0 then
        warn("[AE Kaitun] Mythic Team — กระเป๋าว่าง")
        return false
    end

    local mythicN = 0
    local legN = 0
    for _, u in ipairs(pool) do
        if u.Rarity == "Mythic" then
            mythicN += 1
        elseif u.Rarity == "Legendary" then
            legN += 1
        end
    end

    print(("[AE Kaitun] Smart Mythic Team → Mythic=%d Legendary=%d / slots=%d"):format(
        mythicN, legN, #slots
    ))
    unequipAll()
    task.wait(0.4)

    local n = math.min(#pool, #slots)
    for i = 1, n do
        local unit = pool[i]
        local slot = slots[i]
        print(("[AE Kaitun] MythicTeam Equip %s %s Lv%d%s → slot %s"):format(
            unit.Rarity, unit.Asset, unit.Level,
            unit.Shiny and " ★" or "", tostring(slot)
        ))
        pcall(function()
            Nodes.UNIT_EQUIP:FireServer(unit.ID, tostring(slot))
        end)
        task.wait(0.35)
    end

    task.wait(0.45)
    local equipped = getEquippedCount()
    print("[AE Kaitun] Smart Mythic Team equipped:", equipped)
    return equipped > 0
end

-- เรียกก่อนคิว / หลังสุ่ม / SmartPlay
local function ensureMythicTeam()
    local cfg = getSmartMythicCfg()
    if cfg.Enabled == false then
        return remakeBestTeam()
    end
    return buildMythicTeam()
end

local function ensureTeamReady()
    local mode = getTeamMode()
    local unitsList = _G.Settings["Units"] or {}
    local force = _G.Settings["Force Reload Team"] == true
    local cfg = getSmartMythicCfg()

    print("[AE Kaitun] Team Mode =", mode)

    -- โหมด Mythic / Best → ไม่ยึดลิสต์ Units (ยกเว้นยังไม่มี Mythic/Leg เลย)
    if mode == "Mythic" or mode == "Best" then
        local mythics = Summon.getMythicUnitsInBag and Summon.getMythicUnitsInBag() or {}
        local legs = Summon.getLegendaryUnitsInBag and Summon.getLegendaryUnitsInBag() or {}
        local hasStrong = #mythics > 0 or #legs > 0

        if hasStrong or cfg.ReplaceWeakUnits ~= false then
            if mode == "Mythic" then
                if ensureMythicTeam() then
                    return true
                end
            else
                if remakeBestTeam() then
                    return true
                end
            end
        end

        -- ยังไม่มี Mythic/Leg → fallback ลิสต์ Units / ยูนิตที่มี
        if #unitsList > 0 then
            print("[AE Kaitun] ยังไม่มี Mythic/Leg — ใช้ Units fallback")
            equipUnitsFromList()
            if getEquippedCount() > 0 then
                return true
            end
        end
        unequipAll()
        if equipAnyUnitsFallback() > 0 then
            return true
        end
        warn("[AE Kaitun] กระเป๋าว่าง — รอ Summon/Starter ก่อน")
        return false
    end

    -- โหมด Units: ตามลิสต์ แล้วเติม Mythic/Leg ช่องว่าง
    if #unitsList > 0 then
        equipUnitsFromList()
        local n = getEquippedCount()
        print("[AE Kaitun] Equipped total:", n)
        if n <= 0 then
            warn("[AE Kaitun] Units ในลิสต์ไม่ติด — fallback")
            unequipAll()
            if cfg.ReplaceWeakUnits ~= false and ensureMythicTeam() then
                return true
            end
            equipAnyUnitsFallback()
            fillEmptyHotbarWithLegendaries()
            n = getEquippedCount()
            if n <= 0 then
                warn("[AE Kaitun] กระเป๋าว่างจริง — รอ Summon/Starter ก่อน")
                return false
            end
            return true
        end
        -- มี Mythic ในกระเป๋า + ReplaceWeak → สร้างทีม Mythic ทับลิสต์อ่อน
        if cfg.ReplaceWeakUnits and #(Summon.getMythicUnitsInBag() or {}) > 0 then
            print("[AE Kaitun] มี Mythic — แทนที่ทีม Units ด้วย Smart Mythic")
            return ensureMythicTeam()
        end
        fillEmptyHotbarWithLegendaries()
        return true
    end

    local n = getEquippedCount()
    if n > 0 and not force then
        print("[AE Kaitun] Hotbar มีอยู่แล้ว (", n, ") — เติมเฉพาะช่องว่าง")
        fillEmptyHotbarWithLegendaries()
        return true
    end

    if _G.Settings["Use Load Team"] then
        loadTeam()
    end

    n = getEquippedCount()
    print("[AE Kaitun] Equipped units:", n)
    if n <= 0 then
        if ensureMythicTeam() then
            return true
        end
        equipLegendariesToHotbar()
        n = getEquippedCount()
    end
    if n <= 0 then
        equipAnyUnitsFallback()
        n = getEquippedCount()
    end
    if n <= 0 then
        warn("[AE Kaitun] Hotbar ว่าง — ใส่ยูนิตในเกมก่อน หรือตั้ง Units / Team Index")
        return false
    end
    fillEmptyHotbarWithLegendaries()
    return true
end



Team.getUnlockedHotbarSlots = getUnlockedHotbarSlots
Team.getEmptyUnlockedSlots = getEmptyUnlockedSlots
Team.getEquippedUnitIdSet = getEquippedUnitIdSet
Team.getEquippedAssetSet = getEquippedAssetSet
Team.fillEmptyHotbarWithLegendaries = fillEmptyHotbarWithLegendaries
Team.equipLegendariesToHotbar = equipLegendariesToHotbar
Team.unequipAll = unequipAll
Team.loadTeam = loadTeam
Team.equipUnitsFromList = equipUnitsFromList
Team.getBestUnitsForTeam = getBestUnitsForTeam
Team.remakeBestTeam = remakeBestTeam
Team.buildMythicTeam = buildMythicTeam
Team.ensureMythicTeam = ensureMythicTeam
Team.getTeamMode = getTeamMode
Team.ensureTeamReady = ensureTeamReady

return Team
