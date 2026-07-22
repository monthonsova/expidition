-- AE Kaitun - Placement Engine Module (Slots, Pathing, CFrame & Placement)
-- Port ตรงจาก Kaitun.lua (strategy จริงที่เทสต์แล้ว) — ใช้ CollectionService/MapState/Actions จริง
-- เดิมไฟล์นี้เป็นเวอร์ชัน rewrite ที่ใช้ workspace folder ผิด + ขาด getThreatEnemies → วางพัง
local PlacementEngine = {}

local Core = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Core.lua") or loadstring(readfile("expidition/src/Core.lua"))()
local Replicas = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Replicas.lua") or loadstring(readfile("expidition/src/Replicas.lua"))()

local Dependencies = Core.Dependencies
local peek = Core.peek
local Nodes = Core.Nodes
local Actions = Core.Actions
local Workspace = Core.Workspace
local CollectionService = Core.CollectionService
local LocalPlayer = Core.LocalPlayer
local getCachedUnitUtils = Core.getCachedUnitUtils
local getCachedInformation = Core.getCachedInformation
local getGamePlayerReplica = Replicas.getGamePlayerReplica

local getgenv = getgenv or function() return _G end

-- ------------------------------------------------------------------------
-- Seed offset ตารางสำหรับสร้างจุดวางรอบมอน/ฐาน/ทาง
-- ------------------------------------------------------------------------
local ENEMY_OFFSETS_NEAR = {
    Vector3.new(4, 0, 0), Vector3.new(-4, 0, 0),
    Vector3.new(0, 0, 4), Vector3.new(0, 0, -4),
    Vector3.new(6, 0, 0), Vector3.new(-6, 0, 0),
    Vector3.new(0, 0, 6), Vector3.new(0, 0, -6),
    Vector3.new(5, 0, 5), Vector3.new(-5, 0, -5),
    Vector3.new(5, 0, -5), Vector3.new(-5, 0, 5),
    Vector3.new(8, 0, 3), Vector3.new(-8, 0, 3),
    Vector3.new(3, 0, 8), Vector3.new(3, 0, -8),
    Vector3.new(7, 0, 7), Vector3.new(-7, 0, 7),
    Vector3.new(7, 0, -7), Vector3.new(-7, 0, -7),
}
local ENEMY_OFFSETS_FAR = {
    Vector3.new(5, 0, 0), Vector3.new(-5, 0, 0),
    Vector3.new(0, 0, 5), Vector3.new(0, 0, -5),
    Vector3.new(8, 0, 0), Vector3.new(0, 0, 8),
}

-- ------------------------------------------------------------------------
-- Unwrap helpers (Fusion State ซ้อน — peek แบบ TopHUD)
-- ------------------------------------------------------------------------
local function unwrapField(v)
    if v == nil then
        return nil
    end
    local t = typeof(v)
    if t == "Instance" or t == "string" or t == "number" or t == "boolean" or t == "Vector3" or t == "CFrame" then
        return v
    end
    if t == "table" then
        local ok, peeked = pcall(peek, v)
        if ok and peeked ~= v then
            return unwrapField(peeked)
        end
    end
    return v
end

local function unwrapYen(v)
    if v == nil then
        return nil
    end
    local n = tonumber(v)
    if n ~= nil then
        return n
    end
    if typeof(v) == "table" then
        local ok, peeked = pcall(peek, v)
        if ok then
            return tonumber(peeked)
        end
    end
    return nil
end

local function unwrapNumber(v)
    if v == nil then
        return nil
    end
    local n = tonumber(v)
    if n ~= nil then
        return n
    end
    if typeof(v) == "table" then
        local ok, peeked = pcall(peek, v)
        if ok then
            return tonumber(peeked)
        end
    end
    return nil
end

local function unwrapBool(v)
    if typeof(v) == "boolean" then
        return v
    end
    if typeof(v) == "table" then
        local ok, peeked = pcall(peek, v)
        if ok and typeof(peeked) == "boolean" then
            return peeked
        end
    end
    return nil
end

local function isOwnGameUnit(data)
    if typeof(data) ~= "table" then
        return false
    end
    local o = unwrapField(data.Owner)
    return o == LocalPlayer
        or o == LocalPlayer.UserId
        or o == LocalPlayer.Name
        or tostring(o) == tostring(LocalPlayer.UserId)
end

-- อ่านชื่อ Asset จาก GameUnits state (table) — ไม่ใช่ Instance
local function getUnitAssetName(data)
    if typeof(data) ~= "table" then
        return nil
    end
    local a = unwrapField(data.Asset)
    if typeof(a) == "string" and a ~= "" then
        return a
    end
    local nested = unwrapField(data.Data)
    if typeof(nested) == "table" then
        local a2 = unwrapField(nested.Asset)
        if typeof(a2) == "string" and a2 ~= "" then
            return a2
        end
    end
    return nil
end

-- ------------------------------------------------------------------------
-- Slot / Hotbar / Level
-- ------------------------------------------------------------------------
local function resolveUnitAsset(unitId)
    if not unitId then
        return nil
    end
    local pdata = peek(Dependencies.PlayerData)
    local unitData = pdata and pdata.UnitData
    if typeof(unitData) ~= "table" then
        return nil
    end
    local unit = unitData[unitId] or unitData[tostring(unitId)]
    if typeof(unit) == "table" then
        return unit.Asset or unit.Name
    end
    return nil
end

local function getSlotEntry(slot)
    local hotbar = peek(Dependencies.HotbarState)
    local slots = hotbar and hotbar.Slots
    if typeof(slots) ~= "table" then
        return nil
    end
    return slots[tostring(slot)] or slots[tonumber(slot)] or slots[slot]
end

local function getPlayerLevel()
    local pdata = peek(Dependencies.PlayerData)
    return (pdata and tonumber(pdata.Level)) or 1
end

local function getSlotRequiredLevel(slot)
    local need = 0
    pcall(function()
        local hotbar = peek(Dependencies.HotbarState)
        local levels = hotbar and hotbar.SlotLevels
        if typeof(levels) == "table" then
            need = tonumber(levels[tostring(slot)] or levels[slot]) or 0
        end
    end)
    return need
end

-- ช่องใช้ได้: มียูนิต + ไม่ Disabled (ไอคอนล็อกเลเวลใน UI ยังวางได้)
local function isSlotUsable(slot)
    local data = getSlotEntry(slot)
    if typeof(data) ~= "table" then
        return false
    end
    if not data.ID and not data.Asset then
        return false
    end
    if unwrapBool(data.Disabled) == true then
        return false
    end
    return true
end

-- HotbarState.Slots[i] = { ID = unitUuid, AssetType = "Unit" } — Asset อยู่ที่ UnitData[ID]
local function getSlotAsset(slot)
    local data = getSlotEntry(slot)
    if typeof(data) == "table" then
        if typeof(data.Asset) == "string" and data.Asset ~= "" then
            return data.Asset
        end
        if typeof(data.Data) == "table" and typeof(data.Data.Asset) == "string" then
            return data.Data.Asset
        end
        local fromId = resolveUnitAsset(data.ID)
        if fromId then
            return fromId
        end
    end
    local pdata = peek(Dependencies.PlayerData)
    local hb = pdata and pdata.HotbarData
    if typeof(hb) == "table" then
        local id = hb[tostring(slot)] or hb[tonumber(slot)]
        local asset = resolveUnitAsset(id)
        if asset then
            return asset
        end
    end
    return nil
end

-- เงินในด่าน: ตรงกับ HUD (BottomHUD = KeyOf(GamePlayerState, "Yen"))
local yenKeyOfState = nil
local function getGameYen()
    local best = nil
    local source = "none"
    local keyOfYen = nil

    pcall(function()
        if yenKeyOfState == nil then
            local scope = Dependencies.scope
            if scope and typeof(scope.KeyOf) == "function" then
                yenKeyOfState = scope:KeyOf(Dependencies.GamePlayerState, "Yen")
            end
        end
        if yenKeyOfState ~= nil then
            keyOfYen = unwrapYen(peek(yenKeyOfState))
        end
    end)
    if keyOfYen ~= nil then
        return keyOfYen, "KeyOf"
    end

    local function consider(n, src)
        if n == nil then
            return
        end
        if best == nil or n > best then
            best = n
            source = src
        end
    end

    pcall(function()
        local gps = peek(Dependencies.GamePlayerState)
        if typeof(gps) == "table" then
            consider(unwrapYen(gps.Yen), "GamePlayerState")
        end
    end)
    pcall(function()
        local rep = getGamePlayerReplica()
        local data = rep and (rep.Data or rep.data)
        if typeof(data) == "table" then
            consider(unwrapYen(data.Yen), "replica")
        end
    end)

    if not getgenv()._AE_YEN_DEBUG then
        getgenv()._AE_YEN_DEBUG = true
        print("[AE Kaitun] Yen debug | best=", best, "| source=", source)
    end
    return best, source
end

-- ราคาวาง: HotbarState.Slots[i].PlacementCost → fallback UpgradeInfo Cost
local function getSlotPlacementCost(slot)
    local entry = getSlotEntry(slot)
    if typeof(entry) == "table" then
        local c = unwrapYen(entry.PlacementCost)
        if c and c >= 0 then
            return c
        end
        if typeof(entry.Data) == "table" then
            c = unwrapYen(entry.Data.PlacementCost or entry.Data.Cost)
            if c and c >= 0 then
                return c
            end
        end
    end
    local asset = getSlotAsset(slot)
    local cost = 0
    pcall(function()
        local info = Dependencies.Information:GetAsset(asset)
        local ups = info and info.UpgradeInfo
        if typeof(ups) ~= "table" then
            return
        end
        local up = ups[0] or ups["0"] or ups[1]
        cost = tonumber(up and up.Cost) or 0
    end)
    return cost
end

local function canAffordSlot(slot)
    local cost = getSlotPlacementCost(slot)
    local yen = getGameYen()
    -- อ่านเงินไม่ได้ → ไม่บล็อก (เกมก็ถือ nil = พอ)
    if yen == nil then
        return true, -1, cost
    end
    return yen >= cost, yen, cost
end

local function getHotbarSlots()
    local list = {}
    local hotbar = peek(Dependencies.HotbarState)
    local slots = hotbar and hotbar.Slots

    if typeof(slots) == "table" then
        for i = 1, 6 do
            local asset = getSlotAsset(i)
            if asset and asset ~= "" then
                table.insert(list, i)
            end
        end
    end

    if #list == 0 then
        local pdata = peek(Dependencies.PlayerData)
        local hb = pdata and pdata.HotbarData
        if typeof(hb) == "table" then
            for i = 1, 6 do
                local id = hb[tostring(i)] or hb[i]
                if id and resolveUnitAsset(id) then
                    table.insert(list, i)
                end
            end
        end
    end
    return list
end

-- ------------------------------------------------------------------------
-- Magical / Farm detection
-- ------------------------------------------------------------------------
-- อ่าน asset info ให้ชัวร์ที่สุด (Archetype อยู่ระดับ top-level ของ unit module ไม่ใช่ใน UpgradeInfo)
-- ยืนยันจาก decompile: JaceUnit.Archetype="Magical", Information:GetAsset(name)=Information.Assets[name]
local function getAssetInfo(asset)
    local info = nil
    pcall(function()
        if Dependencies.Information and typeof(Dependencies.Information.GetAsset) == "function" then
            info = Dependencies.Information:GetAsset(asset)
        end
    end)
    if typeof(info) ~= "table" then
        pcall(function()
            local Information = getCachedInformation()
            if Information and typeof(Information.GetAsset) == "function" then
                info = Information:GetAsset(asset)
            end
        end)
    end
    if typeof(info) ~= "table" then
        pcall(function()
            local UnitUtils = getCachedUnitUtils()
            if UnitUtils and typeof(UnitUtils.GetUnitInfo) == "function" then
                info = UnitUtils:GetUnitInfo(asset)
            end
        end)
    end
    return typeof(info) == "table" and info or nil
end

-- คืน Archetype string ของยูนิต (เช่น "Magical"/"Physical"/"Psychic") หรือ nil
local function getUnitArchetype(asset)
    local info = getAssetInfo(asset)
    if not info then
        return nil
    end
    return info.Archetype or info.DamageType or info.Type
end

local magicalCache = {}
local function isMagicalUnit(asset)
    if not asset or asset == "" then
        return false
    end
    if magicalCache[asset] ~= nil then
        return magicalCache[asset]
    end
    local arche = getUnitArchetype(asset)
    local isMagical = (arche == "Magical")
    magicalCache[asset] = isMagical
    return isMagical
end

local FARM_ASSET_FALLBACK = {
    Ichiraku = true,       -- Ramen Guy
    RamenGuy = true,
    StoneAlchemist = true, -- Stone Alchemist
    Stone_Alchemist = true,
    Alchemist = true,
    Bulma = true,
    Speedwagon = true,
}
local function isFarmUnit(asset)
    if not asset or asset == "" then
        return false
    end
    if FARM_ASSET_FALLBACK[asset] then
        return true
    end
    local lowerAsset = tostring(asset):lower()
    if lowerAsset:find("farm") or lowerAsset:find("ichiraku") or lowerAsset:find("ramen") or lowerAsset:find("alchemist") or lowerAsset:find("money") then
        return true
    end
    local farm = false
    pcall(function()
        local UnitUtils = getCachedUnitUtils()
        if UnitUtils and UnitUtils:IsUnitNameFarm(asset) then
            farm = true
            return
        end
        if UnitUtils then
            local stats = UnitUtils:GetUpgradeStats(asset, 0)
            if typeof(stats) == "table" then
                if stats.HitboxType == "Farm" then
                    farm = true
                elseif tonumber(stats.Farm) and tonumber(stats.Farm) > 0 then
                    local dmg = tonumber(stats.Damage) or 0
                    if dmg <= 0 then
                        farm = true
                    end
                end
            end
        end
    end)
    return farm
end

-- สถิติต่อสู้ (Damage/Range/DPS) — ใช้จัดลำดับตัวแรงใน Team
local combatStatsCache = {}
local function getUnitCombatStats(asset)
    if not asset or asset == "" then
        return { damage = 0, range = 0, spa = 1, dps = 0, farm = false }
    end
    if combatStatsCache[asset] ~= nil then
        return combatStatsCache[asset]
    end
    local out = { damage = 0, range = 0, spa = 1, dps = 0, farm = isFarmUnit(asset) }
    pcall(function()
        local UnitUtils = getCachedUnitUtils()
        local stats = UnitUtils and UnitUtils:GetUpgradeStats(asset, 0)
        if typeof(stats) == "table" then
            out.damage = tonumber(stats.Damage) or 0
            out.range = tonumber(stats.Range or stats.Radius or stats.AttackRange) or 0
            local spa = tonumber(stats.SPA or stats.Cooldown or stats.AttackSpeed or stats.AttackInterval)
            if spa and spa > 0 then
                out.spa = spa
            end
            out.dps = out.damage / out.spa
        end
    end)
    if out.range <= 0 then
        out.range = 30
    end
    combatStatsCache[asset] = out
    return out
end

-- เรียงช่อง: วางตัวผลิตเงิน (Farm) ก่อนจนครบลิมิต → จากนั้นวางตัวที่มีดาเมจ/DPS สูงสุดเรียงลงมา
local function getAffordableSlotsOrdered()
    local slots = getHotbarSlots()
    local ranked = {}
    for _, slot in ipairs(slots) do
        local asset = getSlotAsset(slot)
        local isFarm = isFarmUnit(asset)
        local canFarm = isFarm and (countOwnPlacedByAsset(asset) < getPlacementLimit(asset))
        local combat = getUnitCombatStats(asset)
        table.insert(ranked, {
            slot = slot,
            asset = asset,
            cost = getSlotPlacementCost(slot),
            arche = getUnitArchetype(asset),
            canPlaceFarm = canFarm and 1 or 0,
            isFarm = isFarm and 1 or 0,
            dps = combat and combat.dps or 0,
            magical = isMagicalUnit(asset) and 1 or 0,
        })
    end
    table.sort(ranked, function(a, b)
        -- 1. วางตัวผลิตเงิน (Farm) ก่อนจนกว่าจะวางเพิ่มไม่ได้ (ครบลิมิต)
        if a.canPlaceFarm ~= b.canPlaceFarm then
            return a.canPlaceFarm > b.canPlaceFarm
        end
        -- 2. เมื่อวางตัวผลิตเงินไม่ได้แล้ว → วางยูนิตที่มี DPS/ดาเมจสูงสุดเรียงลงมา
        if math.abs((a.dps or 0) - (b.dps or 0)) > 0.01 then
            return (a.dps or 0) > (b.dps or 0)
        end
        if a.cost ~= b.cost then
            return a.cost > b.cost
        end
        return a.slot < b.slot
    end)
    local out = {}
    for _, row in ipairs(ranked) do
        table.insert(out, row.slot)
    end

    -- debug: ดูลำดับจริง + asset/cost/archetype/magical (ทุก ~8 วิ กันสแปม)
    local now = os.clock()
    if (getgenv()._AE_ORDER_DEBUG or 0) + 8 < now then
        getgenv()._AE_ORDER_DEBUG = now
        local parts = {}
        for i, row in ipairs(ranked) do
            table.insert(parts, ("#%d slot%s=%s cost=%s arche=%s magic=%d"):format(
                i, tostring(row.slot), tostring(row.asset),
                tostring(row.cost), tostring(row.arche), row.magical
            ))
        end
        print("[AE Kaitun] SlotOrder (MagicalFirst=" .. tostring(magicalFirst) .. "): "
            .. (#parts > 0 and table.concat(parts, " | ") or "(ไม่มีช่องใช้ได้)"))
    end

    return out
end

-- ------------------------------------------------------------------------
-- Geometry: placeable parts / path / enemies
-- ------------------------------------------------------------------------
local function getHalfHeight(asset)
    local half = 1.5
    if not asset then
        return half
    end
    pcall(function()
        local UnitUtils = getCachedUnitUtils()
        local size = UnitUtils:GetUnitBoundingBoxSize(asset)
        if size and size.Y then
            half = size.Y / 2
        end
    end)
    return half
end

local function getPlaceableParts(asset)
    local ptype = "Ground"
    pcall(function()
        local Information = getCachedInformation()
        local info = Information and Information:GetAsset(asset)
        if info and info.PlacementType then
            ptype = info.PlacementType
        end
    end)
    if ptype == "Hill" then
        return CollectionService:GetTagged("HillPlacement"), ptype
    end
    local grounds = CollectionService:GetTagged("GroundPlacement")
    if #grounds > 0 then
        return grounds, "Ground"
    end
    return CollectionService:GetTagged("HillPlacement"), "Hill"
end

local function getPathPoints()
    local points = {}
    local mapState = peek(Dependencies.MapState)
    local paths = mapState and mapState.Paths
    if typeof(paths) == "table" then
        for _, path in pairs(paths) do
            if typeof(path) == "table" then
                for _, pt in ipairs(path) do
                    if typeof(pt) == "Vector3" then
                        table.insert(points, pt)
                    elseif typeof(pt) == "CFrame" then
                        table.insert(points, pt.Position)
                    end
                end
            end
        end
    end
    if #points == 0 then
        for _, part in ipairs(CollectionService:GetTagged("Path")) do
            if part:IsA("BasePart") then
                table.insert(points, part.Position)
            end
        end
    end
    return points
end

local function distToNearestPath(pos, pathPoints)
    local best = math.huge
    local flat = Vector3.new(pos.X, 0, pos.Z)
    for _, p in ipairs(pathPoints) do
        local d = (flat - Vector3.new(p.X, 0, p.Z)).Magnitude
        if d < best then
            best = d
        end
    end
    return best
end

-- เกมใช้ CFrame ตั้งตรงเท่านั้น (ไม่ lookAt) — หมุนแล้ว Blockcast พลาด GroundPlacement
local function makePlaceCFrame(groundPos, halfY)
    return CFrame.new(groundPos) * CFrame.new(0, halfY, 0)
end

local function flattenInstances(list, out)
    out = out or {}
    if typeof(list) ~= "table" then
        if typeof(list) == "Instance" then
            table.insert(out, list)
        end
        return out
    end
    for _, v in pairs(list) do
        if typeof(v) == "Instance" then
            table.insert(out, v)
        elseif typeof(v) == "table" then
            flattenInstances(v, out)
        end
    end
    return out
end

local function getUnitBoxSize(asset)
    local size = Vector3.new(2, 3, 1)
    pcall(function()
        local UnitUtils = getCachedUnitUtils()
        local s = UnitUtils:GetUnitBoundingBoxSize(asset)
        if typeof(s) == "Vector3" then
            size = s
        end
    end)
    return size
end

local function isTaggedPlaceable(hitInst, placeableParts)
    if not hitInst then
        return false
    end
    for _, part in ipairs(placeableParts) do
        if hitInst == part then
            return true
        end
        if typeof(part) == "Instance" then
            if hitInst:IsDescendantOf(part) or part:IsDescendantOf(hitInst) then
                return true
            end
            local anc = hitInst
            while anc do
                if anc == part then
                    return true
                end
                anc = anc.Parent
            end
        end
    end
    local p = hitInst
    while p do
        if CollectionService:HasTag(p, "GroundPlacement") or CollectionService:HasTag(p, "HillPlacement") then
            return true
        end
        p = p.Parent
    end
    return false
end

local function boxesCollide(cfA, sizeA, cfB, sizeB)
    local localPos = cfA:PointToObjectSpace(cfB.Position)
    local ha, hb = sizeA * 0.5, sizeB * 0.5
    return math.abs(localPos.X) <= ha.X + hb.X
        and math.abs(localPos.Y) <= ha.Y + hb.Y
        and math.abs(localPos.Z) <= ha.Z + hb.Z
end

local placementDebugPrinted = false
-- เช็คเองเป็นหลัก — Actions.IsPlacementAllowed มักพังจาก GET_ALL_UNIT_MODELS (PrimaryPart nil) แล้ว hard=0 ทั้งแมพ
local function canPlaceAt(asset, cframe)
    if not asset or typeof(cframe) ~= "CFrame" then
        return false
    end

    local okGame, resultGame = pcall(function()
        return Actions.IsPlacementAllowed(asset, cframe)
    end)
    if okGame and resultGame == true then
        return true
    end

    local ok = false
    local failReason = nil
    pcall(function()
        local UnitUtils = getCachedUnitUtils()
        local placeable = select(1, getPlaceableParts(asset))
        if typeof(placeable) ~= "table" or #placeable == 0 then
            failReason = "no_placeable_parts"
            return
        end

        local size = getUnitBoxSize(asset)
        local halfY = size.Y / 2
        local ignore = flattenInstances(UnitUtils:GetPlacementIgnoreList())
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = ignore

        local castCf = cframe + Vector3.new(0, halfY, 0)
        local hit = Workspace:Blockcast(castCf, size, Vector3.new(0, -(halfY + 1), 0), params)
        if not hit or not isTaggedPlaceable(hit.Instance, placeable) then
            failReason = hit and ("hit_" .. hit.Instance:GetFullName()) or "no_blockcast"
            return
        end

        -- ชนยูนิตที่มีอยู่ (ข้ามตัวที่ PrimaryPart หาย — อันนี้ทำให้ของเกมพัง)
        local collide = false
        pcall(function()
            local models = Nodes.GET_ALL_UNIT_MODELS:InvokeSelf()
            if typeof(models) ~= "table" then
                return
            end
            for _, model in pairs(models) do
                if typeof(model) == "Instance" then
                    local pp = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
                    if pp then
                        if boxesCollide(pp.CFrame, pp.Size, cframe, size) then
                            collide = true
                            break
                        end
                    end
                end
            end
        end)
        if collide then
            failReason = "collide"
            return
        end

        ok = true
    end)

    if not placementDebugPrinted and not ok then
        placementDebugPrinted = true
        warn("[AE Kaitun] canPlaceAt fail sample:", asset, failReason,
            "| gameOk=", okGame, "gameResult=", resultGame)
    end
    return ok
end

-- จุดปลายทาง = ใกล้ฐาน (path จุดท้ายของแต่ละเลน)
local function getPathEndPositions(pathPoints)
    local ends = {}
    local mapState = peek(Dependencies.MapState)
    local paths = mapState and mapState.Paths
    if typeof(paths) == "table" then
        for _, path in pairs(paths) do
            if typeof(path) == "table" and #path > 0 then
                local take = math.min(4, #path)
                for i = #path - take + 1, #path do
                    local pt = path[i]
                    if typeof(pt) == "Vector3" then
                        table.insert(ends, pt)
                    elseif typeof(pt) == "CFrame" then
                        table.insert(ends, pt.Position)
                    end
                end
            end
        end
    end
    if #ends == 0 and typeof(pathPoints) == "table" and #pathPoints > 0 then
        local take = math.min(6, #pathPoints)
        for i = #pathPoints - take + 1, #pathPoints do
            table.insert(ends, pathPoints[i])
        end
    end
    return ends
end

local function getEnemyPositions()
    local list = {}
    pcall(function()
        local enemies = peek(Dependencies.GameEnemies) or {}
        for model in pairs(enemies) do
            if typeof(model) == "Instance" and model:IsA("Model") and model.PrimaryPart then
                table.insert(list, model.PrimaryPart.Position)
            elseif typeof(model) == "Instance" and model:IsA("BasePart") then
                table.insert(list, model.Position)
            end
        end
    end)
    if #list == 0 then
        local folder = Workspace:FindFirstChild("Enemies")
        if folder then
            for _, m in ipairs(folder:GetChildren()) do
                if m:IsA("Model") and m.PrimaryPart then
                    table.insert(list, m.PrimaryPart.Position)
                end
            end
        end
    end
    return list
end

-- โมเดลศัตรูจริง (Instance) สำหรับ GET_ENEMY_INFOS
local function getEnemyModels()
    local list = {}
    pcall(function()
        local enemies = peek(Dependencies.GameEnemies) or {}
        for model in pairs(enemies) do
            if typeof(model) == "Instance" then
                table.insert(list, model)
            end
        end
    end)
    if #list == 0 then
        local folder = Workspace:FindFirstChild("Enemies")
        if folder then
            for _, m in ipairs(folder:GetChildren()) do
                if m:IsA("Model") or m:IsA("BasePart") then
                    table.insert(list, m)
                end
            end
        end
    end
    return list
end

-- มีบอสในสนามตอนนี้มั้ย — enemy Info.Type มีคำว่า "Boss" (ยืนยันจาก decompile v1.Boss/getTargets)
-- fallback: ชื่อโมเดลมี "Boss"
local function isBossPresent()
    local models = getEnemyModels()
    if #models == 0 then
        return false
    end
    local found = false
    pcall(function()
        local infos = Nodes.GET_ENEMY_INFOS:InvokeSelf(models)
        if typeof(infos) == "table" then
            for _, info in pairs(infos) do
                local t = typeof(info) == "table" and info.Type
                if typeof(t) == "string" and string.find(t, "Boss") then
                    found = true
                    return
                end
            end
        end
    end)
    if not found then
        for _, m in ipairs(models) do
            if typeof(m) == "Instance" and string.find(m.Name, "Boss") then
                found = true
                break
            end
        end
    end
    return found
end

local function distFlat(a, b)
    local dx, dz = a.X - b.X, a.Z - b.Z
    return math.sqrt(dx * dx + dz * dz)
end

local function minDistToPoints(pos, points)
    local best = math.huge
    for _, p in ipairs(points) do
        local d = distFlat(pos, p)
        if d < best then
            best = d
        end
    end
    return best
end

-- มอนที่ใกล้ฐานที่สุดก่อน (ภัยสูงสุด)
local function getThreatEnemies(enemies, pathEnds, maxN)
    maxN = maxN or 12
    if typeof(enemies) ~= "table" or #enemies == 0 then
        return {}
    end
    if typeof(pathEnds) ~= "table" or #pathEnds == 0 then
        local out = {}
        for i = 1, math.min(#enemies, maxN) do
            out[i] = enemies[i]
        end
        return out
    end
    local ranked = {}
    for _, ep in ipairs(enemies) do
        table.insert(ranked, {
            pos = ep,
            threat = minDistToPoints(ep, pathEnds),
        })
    end
    table.sort(ranked, function(a, b)
        return a.threat < b.threat
    end)
    local out = {}
    for i = 1, math.min(#ranked, maxN) do
        out[i] = ranked[i].pos
    end
    return out
end

-- มอนหน้าสุด (ใกล้ฐานสุด) — เผื่อโมดูลอื่นเรียกใช้
local function getFrontmostEnemy(enemies, pathEnds)
    local threat = getThreatEnemies(enemies, pathEnds, 1)
    return threat[1]
end

-- strategy: โฟกัสตัวนำหน้าสุด — คะแนน = ระยะถึงตัวที่นำหน้าสุด (ยิ่งชิดยิ่งดี)
-- ไม่สน cluster/มอนทั้งกลุ่ม — targeting เลือกเป้าเอง (Boss/Closest)
local function scorePlacePosition(pos, enemies, pathPoints, pathEnds)
    if typeof(enemies) == "table" and #enemies > 0 then
        pathEnds = pathEnds or getPathEndPositions(pathPoints or getPathPoints())
        local front = getFrontmostEnemy(enemies, pathEnds)
        if front then
            return (pos - front).Magnitude
        end
        return minDistToPoints(pos, enemies)
    end
    if typeof(pathPoints) == "table" and #pathPoints > 0 then
        return distToNearestPath(pos, pathPoints)
    end
    return math.huge
end

-- ------------------------------------------------------------------------
-- Placement cap / counts
-- ------------------------------------------------------------------------
-- Fallback(GamePlayerState.TotalUnitPlacementCap, GameState.GlobalUnitPlacementCap)
-- ใช้ per-player ก่อน ไม่ใช่เอา max — nil = อ่านไม่ได้ (ไม่บล็อกด้วยเลขปลอม)
local function getTotalPlacementCap()
    local perPlayer, global = nil, nil

    pcall(function()
        local scope = Dependencies.scope
        if scope and typeof(scope.KeyOf) == "function" then
            perPlayer = unwrapNumber(peek(scope:KeyOf(Dependencies.GamePlayerState, "TotalUnitPlacementCap")))
            global = unwrapNumber(peek(scope:KeyOf(Dependencies.GameState, "GlobalUnitPlacementCap")))
        end
    end)
    pcall(function()
        local gps = peek(Dependencies.GamePlayerState)
        local gs = peek(Dependencies.GameState)
        if perPlayer == nil and typeof(gps) == "table" then
            perPlayer = unwrapNumber(unwrapField(gps.TotalUnitPlacementCap))
        end
        if global == nil and typeof(gs) == "table" then
            global = unwrapNumber(unwrapField(gs.GlobalUnitPlacementCap))
        end
    end)
    pcall(function()
        if perPlayer == nil then
            local rep = getGamePlayerReplica()
            local data = rep and (rep.Data or rep.data)
            if typeof(data) == "table" then
                perPlayer = unwrapNumber(data.TotalUnitPlacementCap)
            end
        end
    end)

    local cap = nil
    if typeof(perPlayer) == "number" and perPlayer > 0 then
        cap = perPlayer
    elseif typeof(global) == "number" and global > 0 then
        cap = global
    end

    if not getgenv()._AE_CAP_DEBUG then
        getgenv()._AE_CAP_DEBUG = true
        print("[AE Kaitun] PlacementCap=", cap, "| perPlayer=", perPlayer, "| global=", global)
    end
    return cap
end

local function isAtTotalPlacementCap(owned, totalCap)
    return typeof(totalCap) == "number" and totalCap > 0 and owned >= totalCap
end

local function countOwnPlacedUnits()
    local n = 0
    pcall(function()
        local units = peek(Dependencies.GameUnits)
        if typeof(units) ~= "table" then
            return
        end
        for _, state in pairs(units) do
            local data = peek(state)
            if typeof(data) == "table" then
                local isPhantom = unwrapField(data.IsPhantom) == true
                local isClone = unwrapField(data.IsClone) == true
                if not isPhantom and not isClone and isOwnGameUnit(data) then
                    n += 1
                end
            end
        end
    end)
    return n
end

-- ------------------------------------------------------------------------
-- Point generation (buildAAStylePlaceCFrames) — หัวใจการวาง
-- ------------------------------------------------------------------------
local function snapToPlaceableGround(worldPos, asset)
    local parts = select(1, getPlaceableParts(asset))
    local include = {}
    for _, p in ipairs(parts) do
        if typeof(p) == "Instance" then
            table.insert(include, p)
        end
    end
    if #include == 0 then
        return nil
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = include
    local hit = Workspace:Raycast(worldPos + Vector3.new(0, 60, 0), Vector3.new(0, -200, 0), params)
    if hit then
        return hit.Position
    end
    return nil
end

-- strategy: โฟกัส "ตัวนำหน้าสุด" (ใกล้ฐาน/ปลาย path สุด) ตัวเดียว
-- ไม่มีมอน (เช่น ต้นเวฟ / พักเวฟ) → ใช้จุดเริ่มต้นของ path หรือ GroundPlacement เป็น anchor วางดักล่วงหน้าได้ทันที!
local function buildAAStylePlaceCFrames(asset, count)
    count = math.clamp(count or 8, 1, 14)
    local pathPoints = getPathPoints()
    local enemies = getEnemyPositions()

    local anchor = nil
    if #enemies > 0 then
        local pathEnds = getPathEndPositions(pathPoints)
        anchor = getFrontmostEnemy(enemies, pathEnds) or enemies[1]
    elseif #pathPoints > 0 then
        -- ไม่มีมอนในสนาม → ใช้จุดเริ่มต้น path วางดักล่วงหน้า
        anchor = pathPoints[1] or pathPoints[math.ceil(#pathPoints / 2)]
    else
        -- Fallback: ใช้ตำแหน่ง GroundPlacement ชิ้นแรก
        pcall(function()
            local parts = select(1, getPlaceableParts(asset))
            if parts and parts[1] and parts[1]:IsA("BasePart") then
                anchor = parts[1].Position
            end
        end)
    end

    if not anchor then
        return {}
    end

    local size = getUnitBoxSize(asset)
    local halfY = size.Y / 2

    -- หว่าน seed รอบ anchor (NEAR + FAR ให้จุดพอ)
    local seeds = {}
    for _, off in ipairs(ENEMY_OFFSETS_NEAR) do
        table.insert(seeds, anchor + off)
    end
    for _, off in ipairs(ENEMY_OFFSETS_FAR) do
        table.insert(seeds, anchor + off)
    end

    local candidates = {}
    local checked = 0
    local snapOk = 0
    for _, seed in ipairs(seeds) do
        checked += 1
        if checked % 40 == 0 then
            task.wait()
        end
        local ground = snapToPlaceableGround(seed, asset)
        if ground then
            snapOk += 1
            local cf = makePlaceCFrame(ground, halfY)
            if canPlaceAt(asset, cf) then
                -- ยิ่งชิดตัวนำหน้าสุดยิ่งดี (วางรุมตัวที่นำหน้า)
                local score = (ground - anchor).Magnitude
                table.insert(candidates, { cf = cf, score = score })
            end
        end
    end

    table.sort(candidates, function(a, b)
        return a.score < b.score
    end)

    local hard = {}
    local minSep = 4.0
    local function farEnough(list, pos)
        for _, cf in ipairs(list) do
            if (cf.Position - pos).Magnitude < minSep then
                return false
            end
        end
        return true
    end

    for _, row in ipairs(candidates) do
        if #hard >= count then
            break
        end
        if farEnough(hard, row.cf.Position) then
            table.insert(hard, row.cf)
        end
    end

    local key = "_AE_PT_" .. tostring(asset)
    local now = os.clock()
    if (getgenv()[key] or 0) + 6 < now then
        getgenv()[key] = now
        print("[AE Kaitun] points hard=", #hard, "| snap=", snapOk, "| seeds=", #seeds,
            "| enemies=", #enemies, "(วางรุมตัวนำหน้าสุด)")
    end

    return hard
end

-- ------------------------------------------------------------------------
-- Placement limit / counts per asset
-- ------------------------------------------------------------------------
local placementLimitCache = {}
local function getPlacementLimit(asset)
    if not asset then
        return 4
    end
    local maxFarm = math.max(1, tonumber(_G.Settings["Max Farm Place"]) or 1)
    if placementLimitCache[asset] ~= nil then
        local lim = placementLimitCache[asset]
        if isFarmUnit(asset) then
            lim = math.min(lim, maxFarm)
        end
        return lim
    end
    local lim = tonumber(_G.Settings["Max Place Per Slot"]) or 4
    pcall(function()
        local info = Dependencies.Information:GetAsset(asset)
        local fromInfo = tonumber(info and info.PlacementLimit)
        if fromInfo and fromInfo == fromInfo and fromInfo < 1e9 then
            lim = fromInfo
        end
        local gps = peek(Dependencies.GamePlayerState)
        local limits = gps and gps.PlacementLimits
        if typeof(limits) == "table" then
            local fromState = tonumber(limits[asset])
            if fromState and fromState == fromState and fromState < 1e9 then
                lim = fromState
            end
        end
    end)
    if lim ~= lim or lim <= 0 then
        lim = 4
    end
    placementLimitCache[asset] = lim
    if isFarmUnit(asset) then
        lim = math.min(lim, maxFarm)
    end
    return lim
end

-- นับจาก GameUnits จริง (peek Owner/Asset แบบ TopHUD) + fallback PlacementCounts
local function countOwnPlacedByAsset(asset)
    if not asset then
        return 0
    end
    local n = 0
    local totalSeen = 0
    pcall(function()
        local units = peek(Dependencies.GameUnits)
        if typeof(units) ~= "table" then
            return
        end
        for _, state in pairs(units) do
            local data = peek(state)
            if typeof(data) == "table" then
                totalSeen += 1
                local isPhantom = unwrapField(data.IsPhantom) == true
                local isClone = unwrapField(data.IsClone) == true
                if not isPhantom and not isClone and isOwnGameUnit(data) then
                    local a = getUnitAssetName(data)
                    if a == asset then
                        n += 1
                    end
                end
            end
        end
    end)

    local fromCounts = nil
    pcall(function()
        local gps = peek(Dependencies.GamePlayerState)
        local counts = gps and unwrapField(gps.PlacementCounts)
        if typeof(counts) ~= "table" then
            counts = gps and gps.PlacementCounts
        end
        if typeof(counts) == "table" then
            fromCounts = tonumber(unwrapField(counts[asset])) or unwrapNumber(counts[asset])
        end
    end)

    if fromCounts and fromCounts > n then
        return fromCounts
    end
    return n
end

local function canPlaceMoreOfAsset(asset)
    local placed = countOwnPlacedByAsset(asset)
    local limit = getPlacementLimit(asset)
    local maxPer = tonumber(_G.Settings["Max Place Per Slot"]) or 4
    local perCap = math.min(limit, maxPer)
    if placed >= perCap then
        return false, placed, perCap
    end
    return true, placed, perCap
end

-- debug: ดู field ประเภทยูนิต (ใช้หา field ที่บอก Magical จริง)
local function dumpUnitType(asset)
    if not asset then
        print("[AE Kaitun] dumpUnitType: ต้องใส่ asset")
        return
    end
    local printed = false
    pcall(function()
        local UnitUtils = getCachedUnitUtils()
        local stats = UnitUtils and UnitUtils:GetUpgradeStats(asset, 0)
        if typeof(stats) == "table" then
            print("[AE Kaitun] GetUpgradeStats(" .. tostring(asset) .. "):")
            for k, v in pairs(stats) do
                if typeof(v) ~= "table" then
                    print("   ", k, "=", tostring(v))
                end
            end
            printed = true
        end
    end)
    pcall(function()
        local info = getAssetInfo(asset)
        if typeof(info) == "table" then
            print("[AE Kaitun] Information:GetAsset(" .. tostring(asset) .. "):")
            for k, v in pairs(info) do
                if typeof(v) ~= "table" then
                    print("   ", k, "=", tostring(v))
                end
            end
            printed = true
        end
    end)
    if not printed then
        print("[AE Kaitun] dumpUnitType: อ่านข้อมูล", asset, "ไม่ได้")
    end
    print("[AE Kaitun] Archetype(" .. tostring(asset) .. ")=", tostring(getUnitArchetype(asset)),
        "| isMagicalUnit=", isMagicalUnit(asset))
end

-- ------------------------------------------------------------------------
-- Exports
-- ------------------------------------------------------------------------
PlacementEngine.isMagicalUnit = isMagicalUnit
PlacementEngine.getUnitArchetype = getUnitArchetype
PlacementEngine.getAssetInfo = getAssetInfo
PlacementEngine.isFarmUnit = isFarmUnit
PlacementEngine.getUnitCombatStats = getUnitCombatStats
PlacementEngine.dumpUnitType = dumpUnitType

PlacementEngine.getSlotAsset = getSlotAsset
PlacementEngine.getSlotPlacementCost = getSlotPlacementCost
PlacementEngine.canAffordSlot = canAffordSlot
PlacementEngine.getHotbarSlots = getHotbarSlots
PlacementEngine.getAffordableSlotsOrdered = getAffordableSlotsOrdered
PlacementEngine.getGameYen = getGameYen

PlacementEngine.getPlaceableParts = getPlaceableParts
PlacementEngine.getPathPoints = getPathPoints
PlacementEngine.getPathEndPositions = getPathEndPositions
PlacementEngine.getEnemyPositions = getEnemyPositions
PlacementEngine.getEnemyModels = getEnemyModels
PlacementEngine.isBossPresent = isBossPresent
PlacementEngine.getThreatEnemies = getThreatEnemies
PlacementEngine.getFrontmostEnemy = getFrontmostEnemy
PlacementEngine.minDistToPoints = minDistToPoints
PlacementEngine.distToNearestPath = distToNearestPath
PlacementEngine.scorePlacePosition = scorePlacePosition

PlacementEngine.buildAAStylePlaceCFrames = buildAAStylePlaceCFrames
PlacementEngine.canPlaceAt = canPlaceAt
PlacementEngine.snapToPlaceableGround = snapToPlaceableGround

PlacementEngine.getPlacementLimit = getPlacementLimit
PlacementEngine.canPlaceMoreOfAsset = canPlaceMoreOfAsset
PlacementEngine.countOwnPlacedByAsset = countOwnPlacedByAsset
PlacementEngine.countOwnPlacedUnits = countOwnPlacedUnits
PlacementEngine.getTotalPlacementCap = getTotalPlacementCap
PlacementEngine.isAtTotalPlacementCap = isAtTotalPlacementCap

return PlacementEngine
