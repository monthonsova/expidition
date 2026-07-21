-- [[
--     AE Kaitun — Team & Hotbar Management Module
-- ]]

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

local function ensureTeamReady()
    local unitsList = _G.Settings["Units"] or {}
    local force = _G.Settings["Force Reload Team"] == true

    -- ความสำคัญสูงสุด: มี Units → ใส่ตามลิสต์ แล้วเติม Mythic/Legendary ช่องว่าง
    if #unitsList > 0 then
        equipUnitsFromList()
        local n = getEquippedCount()
        print("[AE Kaitun] Equipped total:", n)
        if n <= 0 then
            warn("[AE Kaitun] Units ไม่ติด — ตรวจชื่อ Asset ในกระเป๋า")
            return false
        end
        -- ช่องว่างที่ปลดล็อกแล้ว (เช่น slot 5 ตอน Lv15+) → เติม Legendary คนละตัว เช่น Utahime
        fillEmptyHotbarWithLegendaries()
        return true
    end

    local n = getEquippedCount()

    -- มีของอยู่แล้ว → ไม่ Load / ไม่ Unequip แต่ยังเติมช่องว่าง
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
Team.ensureTeamReady = ensureTeamReady

return Team
