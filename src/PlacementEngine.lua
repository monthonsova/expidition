-- [[
--     AE Kaitun — Placement Calculation Engine Module
-- ]]

local PlacementEngine = {}
local Replicas = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Replicas.lua") or loadstring(readfile("expidition/src/Replicas.lua"))()

    end
    return slots[tostring(slot)] or slots[tonumber(slot)] or slots[slot]
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

local function getPlayerLevel()
    return getAccountLevel()
end

local function getSlotRequiredLevel(slot)
    local need = 0
    pcall(function()
        local hotbar = peek(Dependencies.HotbarState)
        local levels = hotbar and hotbar.SlotLevels
        if typeof(levels) == "table" then
            need = tonumber(levels[tostring(slot)] or levels[slot]) or 0
        end
        if need <= 0 then
            local info = Dependencies.Information and Dependencies.Information.PlayerLevelInfo
            if info and typeof(info.GetSlotLevel) == "function" then
                need = tonumber(info:GetSlotLevel(slot)) or 0
            elseif info and typeof(info.SlotLevels) == "table" then
                need = tonumber(info.SlotLevels[slot] or info.SlotLevels[tostring(slot)]) or 0
            end
        end
    end)
    return need
end

-- ช่องใช้ได้: มียูนิต + ไม่ Disabled
-- หมายเหตุ: ไอคอนล็อก Level 10 ใน UI ยังวางได้ — อย่าข้ามเพราะเลเวลผู้เล่น
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
    -- fallback จาก PlayerData.HotbarData (ไม่บังคับ Starter — ช่องว่าง = nil)
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
-- fallback: nested peek → replica.Data.Yen
local yenKeyOfState = nil

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

local function getGameYen()
    local best = nil
    local source = "none"
    local keyOfYen = nil

    -- 1) เหมือน HUD: KeyOf — ใช้ตัวนี้เป็นหลัก (ตรงกับที่ผู้เล่นเห็น)
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

    -- 2) fallback เมื่อ KeyOf ยังไม่พร้อม
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

    if not getgenv()._AE_HB_DEBUG then
        getgenv()._AE_HB_DEBUG = true
        print("[AE Kaitun] Hotbar | playerLvl=", getPlayerLevel(), "(ล็อกเลเวลใน UI ยังวางได้)")
        if typeof(slots) == "table" then
            for i = 1, 6 do
                local data = slots[tostring(i)] or slots[i]
                local asset = getSlotAsset(i)
                local need = getSlotRequiredLevel(i)
                local usable = isSlotUsable(i)
                print(("[AE Kaitun] Slot %d → asset=%s uiLockLvl=%s usable=%s disabled=%s"):format(
                    i, tostring(asset), tostring(need), tostring(usable),
                    tostring(typeof(data) == "table" and data.Disabled)
                ))
            end
        end
    end

    if typeof(slots) == "table" then
        for i = 1, 6 do
            if isSlotUsable(i) then
                local asset = getSlotAsset(i)
                if asset and asset ~= "" then
                    table.insert(list, i)
                end
            end
        end
    end

    -- fallback: PlayerData.HotbarData
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

-- เรียงช่อง: ดาเมจก่อน / ฟาร์มทีหลัง (ลำดับเฟสละเอียดอยู่ในลูปวาง)
local FARM_ASSET_FALLBACK = {
    Ichiraku = true, -- Ramen Guy
}

local function isFarmUnit(asset)
    if not asset or asset == "" then
        return false
    end
    if FARM_ASSET_FALLBACK[asset] then
        return true
    end
    local farm = false
    pcall(function()
        local UnitUtils = getCachedUnitUtils()
        if UnitUtils:IsUnitNameFarm(asset) then
            farm = true
            return
        end
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
    end)
    return farm
end

local function getAffordableSlotsOrdered()
    local slots = getHotbarSlots()
    local ranked = {}
    for _, slot in ipairs(slots) do
        local asset = getSlotAsset(slot)
        local cost = getSlotPlacementCost(slot)
        local farmRank = isFarmUnit(asset) and 1 or 0
        table.insert(ranked, { slot = slot, cost = cost, farmRank = farmRank, asset = asset })
    end
    table.sort(ranked, function(a, b)
        if a.farmRank ~= b.farmRank then
            return a.farmRank < b.farmRank
        end
        return a.cost < b.cost
    end)
    local out = {}
    for _, row in ipairs(ranked) do
        table.insert(out, row.slot)
    end
    return out
end

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
        local info = Information:GetAsset(asset)
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
            -- tag อยู่ที่ model / folder
            local anc = hitInst
            while anc do
                if anc == part then
                    return true
                end
                anc = anc.Parent
            end
        end
    end
    -- เผื่อ tag อยู่ที่ parent ของชิ้นที่โดน
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

-- GameUnits เก็บ Owner/Asset/IsPhantom เป็น Fusion State ซ้อน (ต้อง peek แบบ TopHUD)
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

-- จุดปลายทาง = ใกลฐาน (path จุดท้ายของแต่ละเลน)
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
    -- fallback: ท้ายรายการ path รวม
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
            threat = minDistToPoints(ep, pathEnds), -- ใกล้ฐาน = ภัยสูง
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

-- ยิ่งใกล้ = คะแนนยิ่งดี (เลขน้อยกว่า)
-- น้ำหนัก: มอนใกล้ฐาน > ใกล้มอนทั่วไป > ใกล้ปลายทาง > ใกล้ทาง
local function scorePlacePosition(pos, enemies, pathPoints, pathEnds, threatEnemies)
    local nearEnemy = _G.Settings["Place Near Enemies"] ~= false
    local nearPath = _G.Settings["Place Near Path"] ~= false
    local eDist = (#enemies > 0) and minDistToPoints(pos, enemies) or 9999
    local tDist = (threatEnemies and #threatEnemies > 0) and minDistToPoints(pos, threatEnemies) or eDist
    local pDist = (#pathPoints > 0) and distToNearestPath(pos, pathPoints) or 9999
    local endDist = (pathEnds and #pathEnds > 0) and minDistToPoints(pos, pathEnds) or 9999

    local score = 0
    if nearEnemy and #enemies > 0 then
        -- มอนที่ใกล้ฐานสำคัญสุด
        score += tDist * 6 + eDist * 2
        -- ถ้ามอนบุกใกล้ฐานแล้ว → ดึงจุดวางเข้าโซนฐานด้วย
        if endDist < 55 then
            score += endDist * 1.5
        else
            score += endDist * 0.35
        end
        score += pDist * 0.8
        return score
    end
    if nearPath and #pathPoints > 0 then
        -- ไม่มีมอน: กันฐานก่อน (ปลายทาง) แล้วค่อยกระจายตามทาง
        return endDist * 3 + pDist * 2 + eDist
    end
    return tDist + eDist + endDist + pDist
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

local function getTotalPlacementCap()
    -- เหมือน HUD: Fallback(player.TotalUnitPlacementCap, game.GlobalUnitPlacementCap)
    -- ห้าม fallback 8 แล้วอั้นวาง — ค่า 8 เป็น default เก่า/อ่านพลาดบ่อย
    local best = nil
    local source = "none"

    local function consider(n, src)
        if typeof(n) ~= "number" or n ~= n or n <= 0 then
            return
        end
        -- ใช้ค่าสูงสุด (กันอ่านค่าเก่าต่ำแล้วหยุดวางทั้งที่ยังวางได้)
        if best == nil or n > best then
            best = n
            source = src
        end
    end

    pcall(function()
        local scope = Dependencies.scope
        if scope and typeof(scope.KeyOf) == "function" then
            consider(unwrapNumber(peek(scope:KeyOf(Dependencies.GamePlayerState, "TotalUnitPlacementCap"))),
                "KeyOf.PlayerTotal")
            consider(unwrapNumber(peek(scope:KeyOf(Dependencies.GameState, "GlobalUnitPlacementCap"))), "KeyOf.Global")
        end
    end)

    pcall(function()
        local gps = peek(Dependencies.GamePlayerState)
        local gs = peek(Dependencies.GameState)
        if typeof(gps) == "table" then
            consider(unwrapNumber(unwrapField(gps.TotalUnitPlacementCap)), "gps.Total")
        end
        if typeof(gs) == "table" then
            consider(unwrapNumber(unwrapField(gs.GlobalUnitPlacementCap)), "gs.Global")
        end
    end)

    -- จาก replica โดยตรง
    pcall(function()
        local rep = getGamePlayerReplica()
        local data = rep and (rep.Data or rep.data)
        if typeof(data) == "table" then
            consider(unwrapNumber(data.TotalUnitPlacementCap), "replica.Total")
        end
    end)

    if not getgenv()._AE_CAP_DEBUG then
        getgenv()._AE_CAP_DEBUG = true
        print("[AE Kaitun] PlacementCap=", best, "| source=", source)
    end

    -- อ่านไม่ได้ → ไม่บล็อกด้วยตัวเลขปลอม (ให้เซิร์ฟตัดสิน)
    return best
end

-- true เฉพาะเมื่ออ่าน cap ได้ชัด และเต็มแล้ว (nil cap = ยังไม่อั้น)
local function isAtTotalPlacementCap(owned, totalCap)
    return typeof(totalCap) == "number" and totalCap > 0 and owned >= totalCap
end

local function countOwnPlacedUnits()
    -- นับแบบ TopHUD: peek ฟิลด์ซ้อน + ไม่นับ Phantom / Clone
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

local function addSideSeeds(seeds, p, nxt, dists)
    local dir = (Vector3.new(nxt.X, 0, nxt.Z) - Vector3.new(p.X, 0, p.Z))
    if dir.Magnitude < 0.1 then
        dir = Vector3.new(1, 0, 0)
    else
        dir = dir.Unit
    end
    local side = Vector3.new(-dir.Z, 0, dir.X)
    for _, dist in ipairs(dists) do
        table.insert(seeds, p + side * dist)
        table.insert(seeds, p - side * dist)
    end
end

-- หาจุดที่ canPlaceAt ผ่าน — เรียงใกล้มอนใกล้ฐาน / ปลายทางก่อน
local function buildAAStylePlaceCFrames(asset, count)
    count = math.clamp(count or 8, 1, 14)
    local pathPoints = getPathPoints()
    local pathEnds = getPathEndPositions(pathPoints)
    local enemies = getEnemyPositions()
    local threat = getThreatEnemies(enemies, pathEnds, 12)
    local size = getUnitBoxSize(asset)
    local halfY = size.Y / 2
    local seeds = {}

    -- 1) มอนใกล้ฐานก่อน (threat)
    for i = 1, #threat do
        local ep = threat[i]
        for _, off in ipairs(ENEMY_OFFSETS_NEAR) do
            table.insert(seeds, ep + off)
        end
    end

    -- 2) มอนทั่วไป (ถ้ายังมี)
    for i = 1, math.min(#enemies, 10) do
        local ep = enemies[i]
        for _, off in ipairs(ENEMY_OFFSETS_FAR) do
            table.insert(seeds, ep + off)
        end
    end

    -- 3) โซนฐาน (ปลายทาง) — สำคัญตอนมอนบุกเข้ามา / รอบแรกยังไม่มีมอน
    if #pathEnds > 0 then
        for _, p in ipairs(pathEnds) do
            local nxt = pathEnds[#pathEnds]
            addSideSeeds(seeds, p, nxt, { 3.5, 5, 6.5, 8, 10 })
            for _, off in ipairs(BASE_OFFSETS) do
                table.insert(seeds, p + off)
            end
        end
    end

    -- 4) ทางทั้งเส้น (ถี่ขึ้นช่วงท้ายทาง)
    if #pathPoints > 0 then
        local step = math.max(1, math.floor(#pathPoints / 16))
        local startIdx = 1
        -- มีมอนใกล้ฐาน → โฟกัสครึ่งท้ายของทาง
        if #threat > 0 and #pathEnds > 0 then
            local nearestThreat = minDistToPoints(threat[1], pathEnds)
            if nearestThreat < 70 then
                startIdx = math.max(1, math.floor(#pathPoints * 0.45))
            end
        end
        for i = startIdx, #pathPoints, step do
            local p = pathPoints[i]
            local nxt = pathPoints[math.min(i + 1, #pathPoints)]
            addSideSeeds(seeds, p, nxt, { 3.5, 5, 7, 9 })
        end
    end

    local parts, ptype = getPlaceableParts(asset)
    local partN = 0
    for _, part in ipairs(parts) do
        if partN >= 60 then
            break
        end
        local base = part
        if typeof(part) == "Instance" and part:IsA("Model") then
            base = part.PrimaryPart or part:FindFirstChildWhichIsA("BasePart")
        end
        if base and base:IsA("BasePart") then
            partN += 1
            local dPath = (#pathPoints > 0) and distToNearestPath(base.Position, pathPoints) or 0
            local dEnemy = (#enemies > 0) and minDistToPoints(base.Position, enemies) or 0
            local dEnd = (#pathEnds > 0) and minDistToPoints(base.Position, pathEnds) or 0
            -- รับชิ้นใกล้ทาง / มอน / ฐาน (ยกเว้น Hill)
            if ptype == "Hill" or #pathPoints == 0 or dPath <= 45 or dEnemy <= 35 or dEnd <= 50 then
                for _, u in ipairs({ -0.35, 0, 0.35 }) do
                    for _, v in ipairs({ -0.35, 0, 0.35 }) do
                        local localPos = Vector3.new(base.Size.X * u, base.Size.Y * 0.5 + 0.05, base.Size.Z * v)
                        table.insert(seeds, (base.CFrame * localPos))
                    end
                end
            end
        end
    end

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        local bp = hrp.Position
        for _, off in ipairs(HRP_OFFSETS) do
            table.insert(seeds, bp + off)
        end
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
                table.insert(candidates, {
                    cf = cf,
                    score = scorePlacePosition(ground, enemies, pathPoints, pathEnds, threat),
                })
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

    -- emergency: hard=0 ทั้งที่เงินพอ → สแกน GroundPlacement ถี่ๆ ใกล้ทาง/ฐาน
    if #hard == 0 and typeof(parts) == "table" then
        local emergency = {}
        local scanned = 0
        for _, part in ipairs(parts) do
            if #emergency >= math.max(count, 6) then
                break
            end
            local base = part
            if typeof(part) == "Instance" and part:IsA("Model") then
                base = part.PrimaryPart or part:FindFirstChildWhichIsA("BasePart")
            end
            if not (base and base:IsA("BasePart")) then
                continue
            end
            local dPath = (#pathPoints > 0) and distToNearestPath(base.Position, pathPoints) or 0
            local dEnd = (#pathEnds > 0) and minDistToPoints(base.Position, pathEnds) or 0
            local dEnemy = (#enemies > 0) and minDistToPoints(base.Position, enemies) or 0
            if #pathPoints > 0 and dPath > 55 and dEnd > 60 and dEnemy > 40 then
                continue
            end
            for _, u in ipairs({ -0.4, -0.2, 0, 0.2, 0.4 }) do
                for _, v in ipairs({ -0.4, -0.2, 0, 0.2, 0.4 }) do
                    if #emergency >= math.max(count, 6) then
                        break
                    end
                    scanned += 1
                    if scanned % 30 == 0 then
                        task.wait()
                    end
                    local localPos = Vector3.new(base.Size.X * u, base.Size.Y * 0.5 + 0.05, base.Size.Z * v)
                    local seed = base.CFrame * localPos
                    local ground = snapToPlaceableGround(seed, asset)
                    if ground then
                        local cf = makePlaceCFrame(ground, halfY)
                        if canPlaceAt(asset, cf) and farEnough(emergency, cf.Position) then
                            table.insert(emergency, cf)
                        end
                    end
                end
            end
        end
        hard = emergency
        if not getgenv()._AE_EMERGENCY_PT then
            getgenv()._AE_EMERGENCY_PT = true
            print("[AE Kaitun] emergency points=", #hard, "| asset=", asset)
        end
    end

    local key = "_AE_PT_" .. tostring(asset)
    local now = os.clock()
    if (getgenv()[key] or 0) + 6 < now then
        getgenv()[key] = now
        local best = hard[1] and scorePlacePosition(hard[1].Position, enemies, pathPoints, pathEnds, threat) or -1
        local threatToBase = (#threat > 0 and #pathEnds > 0) and minDistToPoints(threat[1], pathEnds) or -1
        print("[AE Kaitun] points hard=", #hard, "| snap=", snapOk, "| seeds=", #seeds,
            "| enemies=", #enemies, "| threat=", #threat,
            "| threat→base~=", typeof(threatToBase) == "number" and string.format("%.1f", threatToBase) or threatToBase,
            "| bestScore~=", typeof(best) == "number" and string.format("%.1f", best) or best,
            "| grounds=", typeof(parts) == "table" and #parts or 0)
    end

    return hard
end

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

    -- ใช้ค่าที่สูงกว่าระหว่างนับจริงกับ PlacementCounts (กันนับ 0 ทั้งที่มีตัวบนสนาม)
    if fromCounts and fromCounts > n then
        if not getgenv()._AE_COUNT_DEBUG then
            getgenv()._AE_COUNT_DEBUG = true
            print("[AE Kaitun] count", asset, "| GameUnits=", n, "| PlacementCounts=", fromCounts,
                "| unitsSeen=", totalSeen, "→ ใช้ PlacementCounts")
        end
        return fromCounts
    end

    if n == 0 and totalSeen > 0 and not getgenv()._AE_COUNT_ZERO then
        getgenv()._AE_COUNT_ZERO = true
        print("[AE Kaitun] count warn: มี GameUnits=", totalSeen, "แต่นับ", asset, "= 0 (เช็ค Owner/Asset peek)")
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

local placeRunning = false
local function autoPlaceUnits()
    if not _G.Settings["Auto Place Units"] then
        return
    end
    if placeRunning then
        return
    end
    placeRunning = true

    print("[AE Kaitun] เริ่มวาง (Yen + Limit + จุด hard เท่านั้น) — วนจนกว่าครบลิมิต")
    waitForPlacementReady(6)
    task.wait(0.2)

    -- ปิด ghost placement ของ UI กันกด Place แล้วขึ้น "cannot place"
    pcall(function()
        Shared.SelectedHotbarIndex:set(nil)
    end)

    local delaySec = math.clamp(tonumber(_G.Settings["Place Delay"]) or 0.85, 0.75, 2.5)
    local maxPerSlot = tonumber(_G.Settings["Max Place Per Slot"]) or 4
    local pointCache = {} -- asset -> { hard, t, idx }
    local skipAsset = {}
    local everPlaced = false
    local lastRebuildWarn = 0
    local failStreak = 0

    local function getPoints(asset, force)
        local meta = pointCache[asset]
        local now = os.clock()
        local enemies = getEnemyPositions()
        local pathEnds = getPathEndPositions(getPathPoints())
        local threat = getThreatEnemies(enemies, pathEnds, 4)
        local nearBase = false
        if #threat > 0 and #pathEnds > 0 then
            nearBase = minDistToPoints(threat[1], pathEnds) < 70
        end
        -- มอนใกล้ฐาน → cache สั้น; hard ว่าง → ห้าม cache นาน
        local ttl = nearBase and 0.45 or ((#enemies > 0) and 0.85 or 2.0)
        local cachedHard = meta and meta.hard or nil
        if not force and meta and (now - meta.t) < ttl and cachedHard and #cachedHard > 0 then
            return cachedHard
        end
        local _, placed, limit = canPlaceMoreOfAsset(asset)
        local need = math.max(4, math.min(12, (limit - placed) + 4))
        local hard = buildAAStylePlaceCFrames(asset, need)
        pointCache[asset] = {
            hard = hard or {},
            t = now,
            idx = 1,
        }
        return pointCache[asset].hard
    end

    local function nextPlaceCFrame(asset)
        local hard = getPoints(asset, false)
        local meta = pointCache[asset]
        if not hard or #hard == 0 then
            -- บังคับรีบิลด์ครั้งหนึ่ง
            hard = getPoints(asset, true)
            meta = pointCache[asset]
        end
        if not hard or #hard == 0 then
            return nil
        end

        -- หาจุดที่ยัง IsPlacementAllowed ตอนนี้ — จุดเสียตัดทิ้งเลย
        local guard = #hard + 2
        while #hard > 0 and guard > 0 do
            guard -= 1
            local i = meta.idx or 1
            if i < 1 or i > #hard then
                i = 1
            end
            local cf = hard[i]
            meta.idx = i + 1
            if cf and canPlaceAt(asset, cf) then
                return cf
            end
            table.remove(hard, i)
            if meta.idx > i then
                meta.idx -= 1
            end
        end
        return nil
    end

    local function dropPoint(asset, cf)
        local meta = pointCache[asset]
        if not meta or not meta.hard or not cf then
            return
        end
        for i, p in ipairs(meta.hard) do
            if p == cf or (p.Position - cf.Position).Magnitude < 0.5 then
                table.remove(meta.hard, i)
                break
            end
        end
    end

    local function allAssetsAtLimit(slots)
        if #slots == 0 then
            return true
        end
        for _, slot in ipairs(slots) do
            local asset = getSlotAsset(slot)
            if asset then
                local placed = countOwnPlacedByAsset(asset)
                local lim = math.min(maxPerSlot, getPlacementLimit(asset))
                if placed < lim then
                    return false
                end
            end
        end
        return true
    end

    task.spawn(function()
        local attempts = 0
        while isInGame() do
            attempts += 1
            if attempts > 300 then
                attempts = 1
                skipAsset = {}
                pointCache = {}
            end

            pcall(function()
                Shared.SelectedHotbarIndex:set(nil)
            end)

            local slots = getAffordableSlotsOrdered()


PlacementEngine.buildAAStylePlaceCFrames = buildAAStylePlaceCFrames
PlacementEngine.scorePlacePosition = scorePlacePosition
PlacementEngine.canPlaceAt = canPlaceAt
PlacementEngine.getAffordableSlotsOrdered = getAffordableSlotsOrdered

return PlacementEngine
