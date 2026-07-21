-- --     AE Kaitun — Auto Equip Module (ไอเทมเสริม/อาวุธที่ดีที่สุด → ยูนิตแข็งสุดไล่ทั้งทีม)
-- --     เกม decompile ไม่ได้ระบุชื่อ node สำหรับ equip item → โมดูลนี้ auto-discover
-- --     ชื่อ node + คีย์ container ตอนรันจริง (มี config override + AEKaitun.DumpEquip())

local AutoEquip = {}

local Core = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Core.lua") or loadstring(readfile("expidition/src/Core.lua"))()
local Replicas = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Replicas.lua") or loadstring(readfile("expidition/src/Replicas.lua"))()
local Summon = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Summon.lua") or loadstring(readfile("expidition/src/Summon.lua"))()

local Nodes = Core.Nodes
local Dependencies = Core.Dependencies
local Actions = Core.Actions
local ReplicatedStorage = Core.ReplicatedStorage
local peek = Core.peek

local isInGame = Replicas.isInGame
local getPlayerData = Replicas.getPlayerData

-- Team.lua require Summon.lua อยู่แล้ว → ดึงแบบ lazy กัน circular
local function getTeamModule()
    return _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Team.lua")
        or loadstring(readfile("expidition/src/Team.lua"))()
end

-- Secret > Exclusive > Mythic > Legendary > Epic > Rare
local RARITY_RANK = {
    Secret = 120,
    Exclusive = 110,
    Mythic = 100,
    Legendary = 70,
    Epic = 40,
    Rare = 20,
    Common = 10,
    Basic = 5,
}

local function getCfg()
    local cfg = _G.Settings["Auto Equip"]
    if typeof(cfg) ~= "table" then
        cfg = {}
    end
    return {
        Enabled = cfg.Enabled ~= false and _G.Settings["Auto Equip Items"] ~= false,
        OnlyEquippedUnits = cfg.OnlyEquippedUnits ~= false,
        ItemsPerUnit = math.max(1, tonumber(cfg.ItemsPerUnit) or 1),
        PreferRarity = cfg.PreferRarity ~= false,
        PreferHighLevel = cfg.PreferHighLevel ~= false,
        Delay = math.clamp(tonumber(cfg.Delay) or 0.4, 0.2, 2.0),
        EquipAction = cfg.EquipAction,   -- Fusion Action เช่น "EquipEquipment" (ช่องทางหลัก)
        UnequipAction = cfg.UnequipAction,
        EquipNode = cfg.EquipNode,       -- fallback: string key ใน Nodes
        UnequipNode = cfg.UnequipNode,
        ContainerKey = cfg.ContainerKey, -- เช่น "EquipmentData"
        ArgOrder = tostring(cfg.ArgOrder or "unit_item"), -- unit_item | item_unit | table
    }
end

------------------------------------------------------------------------
-- Discovery: หา container ของ equipment ใน PlayerData + node สำหรับ equip
------------------------------------------------------------------------
local CONTAINER_CANDIDATES = {
    "EquipmentData", "RelicData", "GearData", "AccessoryData",
    "TrinketData", "ArtifactData", "WeaponData", "ItemEquipmentData",
    "CharmData", "AmuletData",
}

-- entry ที่ "ดูเหมือน equipment": เป็น table + มี Asset/Name (ItemData เป็น {Amount} ไม่มี Asset → ถูกกรองออก)
local function looksLikeEquipmentContainer(tbl)
    if typeof(tbl) ~= "table" then
        return false
    end
    local checked, hit = 0, 0
    for _, e in pairs(tbl) do
        checked += 1
        if typeof(e) == "table" and (e.Asset or e.Name) then
            hit += 1
        end
        if checked >= 8 then
            break
        end
    end
    return checked > 0 and hit > 0
end

local function findContainer(cfg)
    local data = peek(Dependencies.PlayerData)
    if typeof(data) ~= "table" then
        data = getPlayerData()
    end
    if typeof(data) ~= "table" then
        return nil, nil
    end
    -- override ก่อน
    if cfg.ContainerKey and looksLikeEquipmentContainer(data[cfg.ContainerKey]) then
        return data[cfg.ContainerKey], cfg.ContainerKey
    end
    for _, key in ipairs(CONTAINER_CANDIDATES) do
        if looksLikeEquipmentContainer(data[key]) then
            return data[key], key
        end
    end
    return nil, nil
end

local ITEM_KEYWORDS = { "ITEM", "RELIC", "GEAR", "ACCESSOR", "TRINKET", "ARTIFACT", "WEAPON", "EQUIPMENT", "CHARM", "AMULET" }

local function nameMatchesItem(up)
    for _, kw in ipairs(ITEM_KEYWORDS) do
        if up:find(kw, 1, true) then
            return true
        end
    end
    return false
end

local function nodeIsFireable(node)
    return typeof(node) == "table"
        and (typeof(node.FireServer) == "function"
            or typeof(node.Request) == "function"
            or typeof(node.Fire) == "function")
end

-- Nodes เป็น proxy (metatable __index) → pairs() ว่าง ต้องเข้าผ่านชื่อ
local function getNodeByName(name)
    local ok, node = pcall(function()
        return Nodes[name]
    end)
    if ok then
        return node
    end
    return nil
end

-- enumerate ชื่อ node ทั้งหมด 3 ทาง (proxy table iterate ตรงไม่ได้)
local nodeNameCache = nil
local function enumerateNodeNames(force)
    if nodeNameCache and not force then
        return nodeNameCache
    end
    local names, seen = {}, {}
    local function add(k)
        if typeof(k) == "string" and k ~= "" and not seen[k] then
            seen[k] = true
            table.insert(names, k)
        end
    end
    -- 1) pairs ตรง (เผื่อไม่ใช่ proxy)
    pcall(function()
        if typeof(Nodes) == "table" then
            for k in pairs(Nodes) do
                add(k)
            end
        end
    end)
    -- 2) proxy: metatable.__index เป็น table
    pcall(function()
        local mt = getmetatable(Nodes)
        if typeof(mt) == "table" and typeof(mt.__index) == "table" then
            for k in pairs(mt.__index) do
                add(k)
            end
        end
    end)
    -- 3) RemoteEvent/Function instances จริง (ชื่อ = คีย์ node ในเกมนี้)
    pcall(function()
        for _, inst in ipairs(ReplicatedStorage:GetDescendants()) do
            if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction")
                or inst:IsA("UnreliableRemoteEvent")
                or inst:IsA("BindableEvent") or inst:IsA("BindableFunction") then
                add(inst.Name)
            end
        end
    end)
    nodeNameCache = names
    return names
end

-- ชื่อ node ที่น่าจะเป็น equip item (probe ตรงผ่าน __index เผื่อ enumerate ไม่เจอ)
-- อิงแพทเทิร์นของเกม: ASSET_SELL_TABLE / UNIT_EQUIP → เดา ASSET_EQUIP*/UNIT_EQUIP_ITEM ฯลฯ
local CANDIDATE_EQUIP_NAMES = {
    "ASSET_EQUIP_TABLE", "ASSET_EQUIP", "EQUIP_ASSET",
    "UNIT_EQUIP_ITEM", "UNIT_ITEM_EQUIP", "UNIT_EQUIP_EQUIPMENT",
    "UNIT_SET_EQUIPMENT", "SET_UNIT_EQUIPMENT", "UNIT_EQUIPMENT_EQUIP",
    "EQUIP_ITEM", "ITEM_EQUIP", "EQUIP_EQUIPMENT", "EQUIPMENT_EQUIP",
    "SET_EQUIPMENT", "EQUIPMENT_SET", "APPLY_EQUIPMENT", "ATTACH_EQUIPMENT",
    "EQUIP_RELIC", "RELIC_EQUIP", "EQUIP_ACCESSORY", "ACCESSORY_EQUIP",
    "EQUIP_GEAR", "GEAR_EQUIP",
}
local CANDIDATE_UNEQUIP_NAMES = {
    "UNIT_UNEQUIP_ITEM", "UNEQUIP_ITEM", "ITEM_UNEQUIP",
    "UNEQUIP_EQUIPMENT", "EQUIPMENT_UNEQUIP", "REMOVE_EQUIPMENT",
    "ASSET_UNEQUIP", "UNEQUIP_ASSET",
}

-- คืนลิสต์ชื่อ node ที่ match (equip / unequip) เรียงตาม trust score (มาก→น้อย)
local function scanNodesForEquip()
    local names = enumerateNodeNames()
    local enumSet = {}
    for _, n in ipairs(names) do
        enumSet[n:upper()] = n
    end

    local equipScore, unequipScore = {}, {}
    local function bump(tbl, name, sc)
        if not name then return end
        if (tbl[name] or -1) < sc then
            tbl[name] = sc
        end
    end

    -- 1) จาก enumerate: แยก strong (มีคำใบ้ item) / generic (EQUIP เฉยๆ)
    for _, name in ipairs(names) do
        local up = name:upper()
        if up == "UNIT_EQUIP" or up == "UNIT_UNEQUIP_ALL" or up:find("LOAD_TEAM", 1, true) then
            -- hotbar / โหลดทีม ข้าม
        elseif up:find("EQUIP", 1, true) and nodeIsFireable(getNodeByName(name)) then
            local isUnequip = up:find("UNEQUIP", 1, true)
            local strong = nameMatchesItem(up)
            local sc = strong and 100 or 50
            if up:find("EQUIPMENT", 1, true) then sc += 5 end
            if up:find("ITEM", 1, true) then sc += 4 end
            if up:find("ASSET", 1, true) then sc += 3 end
            if isUnequip then
                bump(unequipScore, name, sc)
            else
                bump(equipScore, name, sc)
            end
        end
    end

    -- 2) เช็คชื่อ candidate — เฉพาะที่ "มีจริง" ใน enumSet เท่านั้น
    -- (ห้าม getNodeByName ชื่อที่ไม่มีจริง เพราะ proxy __index อาจ WaitForChild → ค้างเกม)
    for _, cand in ipairs(CANDIDATE_EQUIP_NAMES) do
        local real = enumSet[cand]
        if real and nodeIsFireable(getNodeByName(real)) then
            bump(equipScore, real, 90)
        end
    end
    for _, cand in ipairs(CANDIDATE_UNEQUIP_NAMES) do
        local real = enumSet[cand]
        if real and nodeIsFireable(getNodeByName(real)) then
            bump(unequipScore, real, 90)
        end
    end

    -- verified = ชื่อโผล่ใน enumerate จริง (remote instance/proxy) → ปลอดภัยที่จะยิง
    -- unverified = ได้จาก probe ชื่อเดาล้วนๆ (score < 20) → แค่ suggestion ห้ามยิงอัตโนมัติ
    local function toSortedList(scoreMap)
        local out = {}
        for name in pairs(scoreMap) do
            table.insert(out, { name = name, score = scoreMap[name], verified = scoreMap[name] >= 20 })
        end
        table.sort(out, function(a, b)
            return a.score > b.score
        end)
        return out
    end
    return toSortedList(equipScore), toSortedList(unequipScore)
end

-- equip ทำผ่าน Fusion Actions (ยืนยันจาก dump) — หา function ตัวจริง
local EQUIP_ACTION_NAMES = { "EquipEquipment", "EquipAccessory", "EquipAsset" }
local UNEQUIP_ACTION_NAMES = { "UnequipEquipment", "UnequipAccessoryFromUnitId", "UnequipAsset" }

local function findAction(names)
    if typeof(Actions) ~= "table" then
        return nil, nil
    end
    for _, n in ipairs(names) do
        if typeof(Actions[n]) == "function" then
            return Actions[n], n
        end
    end
    return nil, nil
end

local discoverCache = nil
local function discover(cfg, force)
    cfg = cfg or getCfg()
    if discoverCache and not force then
        return discoverCache
    end
    local container, containerKey = findContainer(cfg)

    -- ช่องทางหลัก: Fusion Action
    local equipAction, equipActionName
    if cfg.EquipAction and typeof(Actions) == "table" and typeof(Actions[cfg.EquipAction]) == "function" then
        equipAction, equipActionName = Actions[cfg.EquipAction], cfg.EquipAction
    else
        equipAction, equipActionName = findAction(EQUIP_ACTION_NAMES)
    end
    local unequipAction, unequipActionName
    if cfg.UnequipAction and typeof(Actions) == "table" and typeof(Actions[cfg.UnequipAction]) == "function" then
        unequipAction, unequipActionName = Actions[cfg.UnequipAction], cfg.UnequipAction
    else
        unequipAction, unequipActionName = findAction(UNEQUIP_ACTION_NAMES)
    end

    local equipHits, unequipHits = scanNodesForEquip()

    -- เลือก node ที่จะยิงจริง: override ก่อน → candidate ที่ verified ตัวแรก (ห้ามยิง unverified อัตโนมัติ)
    local function pickVerified(hits)
        for _, h in ipairs(hits) do
            if h.verified then
                return h.name
            end
        end
        return nil
    end

    local equipNode, equipNodeName
    if cfg.EquipNode and nodeIsFireable(getNodeByName(cfg.EquipNode)) then
        equipNode, equipNodeName = getNodeByName(cfg.EquipNode), cfg.EquipNode
    else
        local pick = pickVerified(equipHits)
        if pick then
            equipNode, equipNodeName = getNodeByName(pick), pick
        end
    end

    local unequipNode, unequipNodeName
    if cfg.UnequipNode and nodeIsFireable(getNodeByName(cfg.UnequipNode)) then
        unequipNode, unequipNodeName = getNodeByName(cfg.UnequipNode), cfg.UnequipNode
    else
        local pick = pickVerified(unequipHits)
        if pick then
            unequipNode, unequipNodeName = getNodeByName(pick), pick
        end
    end

    discoverCache = {
        container = container,
        containerKey = containerKey,
        equipAction = equipAction,
        equipActionName = equipActionName,
        unequipAction = unequipAction,
        unequipActionName = unequipActionName,
        equipNode = equipNode,
        equipNodeName = equipNodeName,
        unequipNode = unequipNode,
        unequipNodeName = unequipNodeName,
        equipCandidates = equipHits,
        unequipCandidates = unequipHits,
    }
    return discoverCache
end

------------------------------------------------------------------------
-- Ranking
------------------------------------------------------------------------
local function rarityRank(asset, fallbackRarity)
    local rarity = Summon.getAssetRarity(asset) or fallbackRarity or "Rare"
    return RARITY_RANK[rarity] or 10, rarity
end

-- equipment ในกระเป๋า → เรียง ดีสุดก่อน (rarity → level → worthiness)
local function getEquipmentItems(container, cfg)
    local list = {}
    if typeof(container) ~= "table" then
        return list
    end
    for id, e in pairs(container) do
        if typeof(e) == "table" then
            local asset = e.Asset or e.Name
            if asset then
                local rank, rarity = rarityRank(asset, e.Rarity)
                table.insert(list, {
                    ID = e.ID or e.UUID or id,
                    Asset = asset,
                    Level = tonumber(e.Level or e.Enhancement or e.Tier) or 0,
                    Rarity = rarity,
                    Rank = rank,
                    Worthiness = tonumber(e.Worthiness or e.Power or e.Stat or e.Rating) or 0,
                    EquippedTo = e.EquippedTo or e.UnitID or e.EquippedUnit or e.Unit or e.EquippedToUnit,
                    Locked = e.Locked == true,
                })
            end
        end
    end
    table.sort(list, function(a, b)
        if cfg.PreferRarity and a.Rank ~= b.Rank then
            return a.Rank > b.Rank
        end
        if cfg.PreferHighLevel and a.Level ~= b.Level then
            return a.Level > b.Level
        end
        if a.Worthiness ~= b.Worthiness then
            return a.Worthiness > b.Worthiness
        end
        return a.Rank > b.Rank
    end)
    return list
end

-- ยูนิตในทีม (หรือทั้งกระเป๋า) → เรียง แข็งสุดก่อน
local function rankUnitList(unitData, filterSet)
    local list = {}
    for id, u in pairs(unitData) do
        if typeof(u) == "table" and u.Asset then
            if (not filterSet) or filterSet[tostring(id)] then
                local rank, rarity = rarityRank(u.Asset, u.Rarity)
                table.insert(list, {
                    ID = id,
                    Asset = u.Asset,
                    Level = tonumber(u.Level) or 1,
                    Rarity = rarity,
                    Rank = rank,
                    Shiny = u.Shiny == true,
                    Worthiness = tonumber(u.Worthiness) or 0,
                })
            end
        end
    end
    table.sort(list, function(a, b)
        if a.Rank ~= b.Rank then
            return a.Rank > b.Rank
        end
        -- shiny แข็งกว่าในเรตเดียวกัน → ควรได้ item ก่อน
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

local function getTargetUnits(cfg)
    local data = getPlayerData()
    local unitData = data and data.UnitData
    if typeof(unitData) ~= "table" then
        return {}
    end
    if cfg.OnlyEquippedUnits then
        local Team = getTeamModule()
        local filterSet = (Team and Team.getEquippedUnitIdSet and Team.getEquippedUnitIdSet()) or {}
        local list = rankUnitList(unitData, filterSet)
        if #list > 0 then
            return list
        end
        -- ทีมยังไม่ถูกใส่ (เช่นตอน startup) → fallback ใช้ยูนิตแข็งสุดในกระเป๋าแทน
        print("[AE Kaitun] AutoEquip: ยังไม่มียูนิตในทีม — fallback ใช้ยูนิตแข็งสุดในกระเป๋า")
    end
    return rankUnitList(unitData, nil)
end

------------------------------------------------------------------------
-- Fire
------------------------------------------------------------------------
-- ยิงผ่าน Fusion Action (ช่องทางหลัก) — Actions.EquipEquipment(unitId, equipmentId)
local function fireEquipAction(fn, unitId, itemId, argOrder)
    local args
    if argOrder == "item_unit" then
        args = { itemId, unitId }
    elseif argOrder == "table" then
        args = { { UnitId = unitId, UnitID = unitId, EquipmentId = itemId, EquipmentID = itemId, ItemId = itemId, Id = itemId } }
    else
        args = { unitId, itemId }
    end
    local ok, err = pcall(function()
        return fn(table.unpack(args))
    end)
    if not ok then
        warn("[AE Kaitun] AutoEquip action error:", tostring(err))
    end
    return ok
end

local function fireEquip(node, unitId, itemId, slotIndex, argOrder)
    local args
    if argOrder == "item_unit" then
        args = { itemId, unitId }
    elseif argOrder == "unit_item_slot" then
        args = { unitId, itemId, slotIndex }
    else
        args = { unitId, itemId }
    end
    local ok = pcall(function()
        if typeof(node.FireServer) == "function" then
            node:FireServer(table.unpack(args))
        elseif typeof(node.Request) == "function" then
            local req = node:Request(table.unpack(args))
            if req and req.Timeout then
                req:Timeout(5)
            end
        elseif typeof(node.Fire) == "function" then
            node:Fire(table.unpack(args))
        end
    end)
    return ok
end

------------------------------------------------------------------------
-- Main: ใส่ item ดีสุด → unit แข็งสุด ไล่ทั้งทีม
------------------------------------------------------------------------
local running = false

local function autoEquipBestItems(reason)
    local cfg = getCfg()
    if not cfg.Enabled then
        return false
    end
    if isInGame() then
        return false
    end
    if running then
        return false
    end
    running = true

    local ok, result = pcall(function()
        local disc = discover(cfg, true)

        if not disc.container then
            print("[AE Kaitun] AutoEquip: ไม่พบ container equipment ใน PlayerData —",
                "ตั้ง Auto Equip.ContainerKey หรือรัน AEKaitun.DumpEquip() ดูคีย์จริง")
            return false
        end
        if not disc.equipAction and not disc.equipNode then
            warn("[AE Kaitun] AutoEquip: หา Actions.EquipEquipment / node equip ไม่เจอ —",
                "ตั้ง Auto Equip.EquipAction เอง หรือรัน AEKaitun.DumpEquip()")
            return false
        end

        local items = getEquipmentItems(disc.container, cfg)
        if #items == 0 then
            print("[AE Kaitun] AutoEquip: ไม่มี equipment ในกระเป๋า (container=" .. tostring(disc.containerKey) .. ")")
            return false
        end
        local units = getTargetUnits(cfg)
        if #units == 0 then
            print("[AE Kaitun] AutoEquip: ไม่มียูนิตเป้าหมาย (จัดทีมก่อน)")
            return false
        end

        local method = disc.equipAction and ("action:" .. tostring(disc.equipActionName))
            or ("node:" .. tostring(disc.equipNodeName))
        print(("[AE Kaitun] === AutoEquip (%s) | %s | container=%s | items=%d units=%d ==="):format(
            tostring(reason or "manual"), method, tostring(disc.containerKey), #items, #units
        ))

        local perUnit = cfg.ItemsPerUnit
        local idx = 1
        local fired = 0
        for _, unit in ipairs(units) do
            for slot = 1, perUnit do
                local item = items[idx]
                if not item then
                    break
                end
                idx += 1
                -- ติดถูกตัวอยู่แล้ว → ข้าม (ยังนับว่าใช้ช่องนี้ไป)
                if tostring(item.EquippedTo or "") == tostring(unit.ID) then
                    print(("[AE Kaitun] AutoEquip: %s %s ติด %s อยู่แล้ว — ข้าม"):format(
                        tostring(item.Rarity), tostring(item.Asset), tostring(unit.Asset)
                    ))
                else
                    print(("[AE Kaitun] AutoEquip: %s %s Lv%d → %s %s (slot %d)"):format(
                        tostring(item.Rarity), tostring(item.Asset), item.Level,
                        tostring(unit.Rarity), tostring(unit.Asset), slot
                    ))
                    local okFire
                    if disc.equipAction then
                        okFire = fireEquipAction(disc.equipAction, unit.ID, item.ID, cfg.ArgOrder)
                    else
                        okFire = fireEquip(disc.equipNode, unit.ID, item.ID, slot, cfg.ArgOrder)
                    end
                    if okFire then
                        fired += 1
                    end
                    task.wait(cfg.Delay)
                end
            end
            if not items[idx] then
                break
            end
        end

        print(("[AE Kaitun] === AutoEquip เสร็จ — ยิง equip %d ครั้ง ==="):format(fired))
        return fired > 0
    end)

    running = false
    if not ok then
        warn("[AE Kaitun] AutoEquip error:", result)
        return false
    end
    return result
end

------------------------------------------------------------------------
-- Diagnostic dump — รันครั้งเดียวเพื่อยืนยันชื่อ node/คีย์จริง แล้ว hardcode ได้
------------------------------------------------------------------------
local function dump()
    local L = {}
    local function emit(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[i] = tostring(select(i, ...))
        end
        table.insert(L, table.concat(parts, " "))
    end

    -- ห่อทั้งหมดใน pcall กัน error กลางทางแล้วไม่ได้เซฟไฟล์
    pcall(function()
        local cfg = getCfg()
        local disc = discover(cfg, true)
        emit("========== AE Kaitun AutoEquip DUMP ==========")
        emit("time =", os.date("%Y-%m-%d %H:%M:%S"))
        emit("PlayerData equipment container key =", tostring(disc.containerKey))
        emit("equip ACTION (เลือกใช้) =", tostring(disc.equipActionName))
        emit("unequip ACTION (เลือกใช้) =", tostring(disc.unequipActionName))
        emit("equip node (fallback) =", tostring(disc.equipNodeName))
        emit("unequip node (fallback) =", tostring(disc.unequipNodeName))
        local function fmtCands(hits)
            local s = {}
            for _, h in ipairs(hits or {}) do
                table.insert(s, ("%s[score=%d%s]"):format(h.name, h.score or 0, h.verified and ",verified" or ",UNVERIFIED"))
            end
            return #s > 0 and table.concat(s, ", ") or "(none)"
        end
        emit("equip candidates =", fmtCands(disc.equipCandidates))
        emit("unequip candidates =", fmtCands(disc.unequipCandidates))

        local data = peek(Dependencies.PlayerData)
        if typeof(data) ~= "table" then
            data = getPlayerData()
        end
        if typeof(data) == "table" then
            local keys = {}
            for k, v in pairs(data) do
                table.insert(keys, tostring(k) .. "(" .. typeof(v) .. ")")
            end
            table.sort(keys)
            emit("PlayerData keys =", table.concat(keys, ", "))
        end

        -- ตัวอย่าง entry แรกใน container + กาง Stats subtable (หา field equip reference)
        if typeof(disc.container) == "table" then
            for id, e in pairs(disc.container) do
                emit("sample equipment id =", tostring(id))
                if typeof(e) == "table" then
                    local fields = {}
                    for k, v in pairs(e) do
                        table.insert(fields, tostring(k) .. "=" .. tostring(v))
                        if typeof(v) == "table" then
                            local sub = {}
                            for sk, sv in pairs(v) do
                                table.insert(sub, tostring(sk) .. "=" .. tostring(sv))
                            end
                            table.sort(sub)
                            emit(("    %s.* : %s"):format(tostring(k), table.concat(sub, " | ")))
                        end
                    end
                    table.sort(fields)
                    emit("  fields:", table.concat(fields, " | "))
                end
                break
            end
            local items = getEquipmentItems(disc.container, cfg)
            emit("equipment count =", #items)
            for i = 1, math.min(8, #items) do
                local it = items[i]
                emit(("  [%d] %s %s Lv%d EquippedTo=%s"):format(
                    i, tostring(it.Rarity), tostring(it.Asset), it.Level, tostring(it.EquippedTo)
                ))
            end
        end

        -- ตัวอย่าง UnitData entry — หา field ที่ยูนิตอ้าง equipment (Equipment/Items/Equipped)
        if typeof(data) == "table" and typeof(data.UnitData) == "table" then
            for id, u in pairs(data.UnitData) do
                emit("sample unit id =", tostring(id))
                if typeof(u) == "table" then
                    local ufields = {}
                    for k, v in pairs(u) do
                        table.insert(ufields, tostring(k) .. "=" .. tostring(v))
                        if typeof(v) == "table" then
                            local sub = {}
                            for sk, sv in pairs(v) do
                                table.insert(sub, tostring(sk) .. "=" .. tostring(sv))
                            end
                            table.sort(sub)
                            emit(("    unit.%s.* : %s"):format(tostring(k), table.concat(sub, " | ")))
                        end
                    end
                    table.sort(ufields)
                    emit("  unit fields:", table.concat(ufields, " | "))
                end
                break
            end
        end

        -- node names ทั้งหมด (Nodes เป็น proxy → pairs ตรงว่าง) — เข้าถึงเฉพาะชื่อจริง
        local allNames = enumerateNodeNames(true)
        emit("node names ที่ enumerate ได้ (total) =", #allNames)
        local broad = {}
        for _, name in ipairs(allNames) do
            local up = name:upper()
            if up:find("EQUIP", 1, true) or up:find("ITEM", 1, true)
                or up:find("ACCESSOR", 1, true) or up:find("GEAR", 1, true)
                or up:find("RELIC", 1, true) or up:find("TRINKET", 1, true)
                or up:find("ARTIFACT", 1, true) or up:find("WEAPON", 1, true)
                or up:find("CHARM", 1, true) or up:find("STONE", 1, true)
                or up:find("ENHANC", 1, true) or up:find("UPGRADE", 1, true) then
                local fireable = nodeIsFireable(getNodeByName(name)) and "*" or ""
                table.insert(broad, name .. fireable)
            end
        end
        table.sort(broad)
        emit("Nodes ที่น่าสนใจ (equip/item/gear/... , * = fireable) =", table.concat(broad, ", "))
        -- ลิสต์ node ทั้งหมด (เผื่อชื่อ equip ไม่มีคำใบ้) — อยู่ในไฟล์ ไม่ท่วมคอนโซล
        table.sort(allNames)
        emit("ALL node names =", table.concat(allNames, ", "))

        -- เผื่อ equip ไปทาง Fusion Actions แทน Nodes
        if typeof(Actions) == "table" then
            local aHits, aAll = {}, {}
            pcall(function()
                for k, v in pairs(Actions) do
                    if typeof(k) == "string" then
                        table.insert(aAll, k)
                        local up = k:upper()
                        if up:find("EQUIP", 1, true) or up:find("ITEM", 1, true)
                            or up:find("ACCESSOR", 1, true) or up:find("GEAR", 1, true)
                            or up:find("RELIC", 1, true) then
                            table.insert(aHits, k .. "(" .. typeof(v) .. ")")
                        end
                    end
                end
            end)
            table.sort(aHits)
            table.sort(aAll)
            emit("Actions ที่เกี่ยวข้อง =", table.concat(aHits, ", "))
            emit("Actions ทั้งหมด =", table.concat(aAll, ", "))
        end
        emit("==============================================")
    end)

    local content = table.concat(L, "\n")
    local fileName = "AE_KaitunEquipDump.txt"
    local wrote = false
    if typeof(writefile) == "function" then
        wrote = pcall(writefile, fileName, content)
    end
    if wrote then
        print("[AE Kaitun] AutoEquip DUMP เซฟแล้ว →", fileName, "(" .. #L .. " บรรทัด) — เปิดในโฟลเดอร์ workspace ของ executor")
    else
        warn("[AE Kaitun] writefile ใช้ไม่ได้ — print ลงคอนโซลแทน:")
        print(content)
    end
    return content
end

AutoEquip.getCfg = getCfg
AutoEquip.discover = discover
AutoEquip.getEquipmentItems = getEquipmentItems
AutoEquip.getTargetUnits = getTargetUnits
AutoEquip.autoEquipBestItems = autoEquipBestItems
AutoEquip.dump = dump

return AutoEquip
