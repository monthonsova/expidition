-- AE Kaitun - Placement Engine Module (Math, Pathing & CFrame Algorithms)

local PlacementEngine = {}

local Services = {
    Players = game:GetService("Players"),
    Workspace = game:GetService("Workspace"),
    CollectionService = game:GetService("CollectionService"),
    ReplicatedStorage = game:GetService("ReplicatedStorage"),
}

local LocalPlayer = Services.Players.LocalPlayer

local Core = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Core.lua") or loadstring(readfile("expidition/src/Core.lua"))()
local Replicas = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Replicas.lua") or loadstring(readfile("expidition/src/Replicas.lua"))()
local Utils = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Utils.lua") or loadstring(readfile("expidition/src/Utils.lua"))()

local Dependencies = Core.Dependencies
local peek = Core.peek
local getCachedUnitUtils = Core.getCachedUnitUtils
local getPlayerData = Replicas.getPlayerData
local getGamePlayerReplica = Replicas.getGamePlayerReplica

-- ------------------------------------------------------------------------
-- Helper Functions
-- ------------------------------------------------------------------------
local function unwrapField(v)
    if typeof(v) == "table" then
        if v.Value ~= nil then return v.Value end
        if v.val ~= nil then return v.val end
    end
    return v
end

local function isOwnGameUnit(data)
    if typeof(data) ~= "table" then return false end
    local p = unwrapField(data.Player) or unwrapField(data.Owner) or unwrapField(data.player)
    if typeof(p) == "Instance" and p:IsA("Player") then
        return p == LocalPlayer
    end
    if typeof(p) == "string" or typeof(p) == "number" then
        return tostring(p) == tostring(LocalPlayer.UserId) or tostring(p) == LocalPlayer.Name
    end
    return true
end

local function getUnitAssetName(unitInst)
    if not unitInst then return nil end
    local a = unitInst:FindFirstChild("Asset") or unitInst:FindFirstChild("UnitName")
    if a and a:IsA("StringValue") and a.Value ~= "" then
        return a.Value
    end
    return unitInst.Name
end

local function resolveUnitAsset(unitId)
    if not unitId then return nil end
    local data = getPlayerData()
    local unitData = data and data.UnitData
    if typeof(unitData) == "table" then
        local u = unitData[unitId] or unitData[tostring(unitId)]
        if typeof(u) == "table" and u.Asset then
            return u.Asset
        end
    end
    return nil
end

local function getSlotEntry(slot)
    local hotbar = peek(Dependencies.HotbarState)
    local slots = hotbar and hotbar.Slots
    if typeof(slots) == "table" then
        return slots[tostring(slot)] or slots[slot]
    end
    return nil
end

local function unwrapBool(val)
    if typeof(val) == "boolean" then return val end
    if typeof(val) == "table" and val.Value ~= nil then return val.Value == true end
    return false
end

local function getPlayerLevel()
    local pdata = peek(Dependencies.PlayerData)
    return (pdata and tonumber(pdata.Level)) or 1
end

local function getSlotRequiredLevel(slot)
    slot = tonumber(slot) or 1
    local req = { 1, 1, 1, 1, 15, 30 }
    return req[slot] or 1
end

local function isSlotUsable(slot)
    local entry = getSlotEntry(slot)
    if typeof(entry) == "table" then
        if unwrapBool(entry.Disabled) or unwrapBool(entry.Locked) then
            return false
        end
    end
    return true
end

local function getSlotAsset(slot)
    local entry = getSlotEntry(slot)
    if typeof(entry) == "table" and entry.ID then
        local asset = resolveUnitAsset(entry.ID)
        if asset and asset ~= "" then return asset end
    end
    local pdata = peek(Dependencies.PlayerData)
    local hb = pdata and pdata.HotbarData
    if typeof(hb) == "table" then
        local id = hb[tostring(slot)] or hb[slot]
        if id then return resolveUnitAsset(id) end
    end
    return nil
end

local function unwrapYen(val)
    if typeof(val) == "number" then return val end
    if typeof(val) == "table" and val.Value ~= nil then return tonumber(val.Value) end
    return tonumber(val)
end

local function getGameYen()
    local yen, src = nil, "none"
    pcall(function()
        local gps = peek(Dependencies.GamePlayerState)
        if typeof(gps) == "table" and gps.Yen ~= nil then
            yen = unwrapYen(gps.Yen)
            src = "GamePlayerState"
        end
    end)
    if yen == nil then
        pcall(function()
            local rep = getGamePlayerReplica()
            local data = rep and (rep.Data or rep.data)
            if typeof(data) == "table" and data.Yen ~= nil then
                yen = unwrapYen(data.Yen)
                src = "GamePlayerReplica"
            end
        end)
    end
    return yen, src
end

local function getSlotPlacementCost(slot)
    local entry = getSlotEntry(slot)
    if typeof(entry) == "table" then
        local cost = unwrapYen(entry.PlacementCost or entry.Cost)
        if cost and cost > 0 then return cost end
    end

    local asset = getSlotAsset(slot)
    local cost = 0
    pcall(function()
        local info = Dependencies.Information and Dependencies.Information:GetAsset(asset)
        local ups = info and info.UpgradeInfo
        if typeof(ups) == "table" then
            local up = ups[0] or ups["0"] or ups[1]
            cost = tonumber(up and up.Cost) or 0
        end
    end)
    return cost
end

local function canAffordSlot(slot)
    local cost = getSlotPlacementCost(slot)
    local yen = getGameYen()
    if yen == nil then return true, -1, cost end
    return yen >= cost, yen, cost
end

local function getHotbarSlots()
    local list = {}
    for i = 1, 6 do
        if isSlotUsable(i) then
            local asset = getSlotAsset(i)
            if asset and asset ~= "" then
                table.insert(list, i)
            end
        end
    end
    return list
end

-- ------------------------------------------------------------------------
-- Magical Unit Detection & Front-most Enemy Targeting
-- ------------------------------------------------------------------------
local function isMagicalUnit(asset)
    if not asset or asset == "" then return false end
    local isMagical = false
    pcall(function()
        local UnitUtils = getCachedUnitUtils()
        if UnitUtils then
            local stats = UnitUtils:GetUpgradeStats(asset, 0)
            if typeof(stats) == "table" then
                if stats.Archetype == "Magical" or stats.DamageType == "Magical" or stats.Type == "Magical" then
                    isMagical = true
                    return
                end
            end
        end
    end)
    pcall(function()
        local info = Dependencies.Information and Dependencies.Information:GetAsset(asset)
        if typeof(info) == "table" then
            if info.Archetype == "Magical" or info.DamageType == "Magical" or info.Type == "Magical" then
                isMagical = true
                return
            end
            local stats = info.UpgradeInfo and (info.UpgradeInfo[0] or info.UpgradeInfo["0"] or info.UpgradeInfo[1])
            if typeof(stats) == "table" and (stats.Archetype == "Magical" or stats.DamageType == "Magical") then
                isMagical = true
                return
            end
        end
    end)
    return isMagical
end

local FARM_ASSET_FALLBACK = {
    Ichiraku = true,
}

local function isFarmUnit(asset)
    if not asset or asset == "" then return false end
    if FARM_ASSET_FALLBACK[asset] then return true end
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
                if stats.HitboxType == "Farm" or (tonumber(stats.Farm) and tonumber(stats.Farm) > 0) then
                    farm = true
                end
            end
        end
    end)
    return farm
end

-- ลำดับการวางยูนิต: 1) เน้นตัวที่เป็น Magical ก่อน -> 2) เรียงจากราคาแพงที่สุด -> น้อยสุด
local function getAffordableSlotsOrdered()
    local slots = getHotbarSlots()
    local affordable = {}
    for _, slot in ipairs(slots) do
        local afford, yen, cost = canAffordSlot(slot)
        if afford then
            table.insert(affordable, slot)
        end
    end

    table.sort(affordable, function(a, b)
        local assetA = getSlotAsset(a)
        local assetB = getSlotAsset(b)
        local magA = isMagicalUnit(assetA) and 1 or 0
        local magB = isMagicalUnit(assetB) and 1 or 0

        if magA ~= magB then
            return magA > magB -- Magical ก่อนเสมอ
        end

        local costA = getSlotPlacementCost(a)
        local costB = getSlotPlacementCost(b)
        if costA ~= costB then
            return costA > costB -- แพงที่สุด -> น้อยสุด
        end

        return a < b
    end)

    return affordable
end

-- ------------------------------------------------------------------------
-- CFrame Math & Pathing Distance
-- ------------------------------------------------------------------------
local function getPlaceableParts()
    local parts = {}
    local placeFolder = workspace:FindFirstChild("GroundPlacement") or workspace:FindFirstChild("HillPlacement") or workspace:FindFirstChild("Map")
    if placeFolder then
        for _, inst in ipairs(placeFolder:GetDescendants()) do
            if inst:IsA("BasePart") then
                table.insert(parts, inst)
            end
        end
    end
    return parts
end

local function getPathPoints()
    local points = {}
    local pathFolder = workspace:FindFirstChild("Path") or workspace:FindFirstChild("Paths") or workspace:FindFirstChild("Waypoints")
    if pathFolder then
        for _, inst in ipairs(pathFolder:GetDescendants()) do
            if inst:IsA("BasePart") then
                table.insert(points, inst.Position)
            end
        end
    end
    return points
end

local function getPathEndPositions(points)
    if #points == 0 then return {} end
    return { points[#points] }
end

local function getEnemyPositions()
    local list = {}
    local enemyFolder = workspace:FindFirstChild("Enemies") or workspace:FindFirstChild("Mobs")
    if enemyFolder then
        for _, inst in ipairs(enemyFolder:GetChildren()) do
            local hrp = inst:FindFirstChild("HumanoidRootPart") or inst:FindFirstChild("PrimaryPart")
            if hrp then
                table.insert(list, hrp.Position)
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

local function distToNearestPath(pos, pathPoints)
    return minDistToPoints(pos, pathPoints)
end

-- ค้นหามอนสเตอร์ที่อยู่ "หน้าสุด" (Front-most Enemy) ใกล้ฐานที่สุด
local function getFrontmostEnemy(enemies, pathEnds)
    if typeof(enemies) ~= "table" or #enemies == 0 then
        return nil
    end
    if typeof(pathEnds) ~= "table" or #pathEnds == 0 then
        return enemies[1]
    end

    local frontmost = nil
    local minDist = math.huge

    for _, enemyPos in ipairs(enemies) do
        local d = minDistToPoints(enemyPos, pathEnds)
        if d < minDist then
            minDist = d
            frontmost = enemyPos
        end
    end

    return frontmost
end

-- คะแนนจุดวาง: วางชิดใกล้ "มอนที่อยู่หน้าสุด" (Front-most Enemy) ก่อนเสมอ
local function scorePlacePosition(pos, enemies, pathPoints, pathEnds)
    local frontmost = getFrontmostEnemy(enemies, pathEnds)
    local pDist = (#pathPoints > 0) and distToNearestPath(pos, pathPoints) or 9999
    local endDist = (pathEnds and #pathEnds > 0) and minDistToPoints(pos, pathEnds) or 9999

    if frontmost then
        local fDist = distFlat(pos, frontmost)
        return fDist * 10 + pDist * 2 + endDist * 0.5
    end

    if #pathPoints > 0 then
        return endDist * 3 + pDist * 2
    end

    return endDist + pDist
end

local function getPlacementLimit(asset)
    local limit = 4
    pcall(function()
        local UnitUtils = getCachedUnitUtils()
        if UnitUtils then
            local lim = UnitUtils:GetPlacementLimit(asset)
            if tonumber(lim) and tonumber(lim) > 0 then
                limit = tonumber(lim)
            end
        end
    end)
    return limit
end

local function countOwnPlacedByAsset(asset)
    local count = 0
    pcall(function()
        local units = peek(Dependencies.GameUnits)
        if typeof(units) == "table" then
            for _, state in pairs(units) do
                local data = peek(state)
                if typeof(data) == "table" and isOwnGameUnit(data) then
                    local name = unwrapField(data.Asset) or unwrapField(data.UnitName)
                    if tostring(name) == tostring(asset) then
                        count += 1
                    end
                end
            end
        end
    end)
    return count
end

local function countOwnPlacedUnits()
    local count = 0
    pcall(function()
        local units = peek(Dependencies.GameUnits)
        if typeof(units) == "table" then
            for _, state in pairs(units) do
                local data = peek(state)
                if typeof(data) == "table" and isOwnGameUnit(data) then
                    count += 1
                end
            end
        end
    end)
    return count
end

local function getTotalPlacementCap()
    local cap = 20
    pcall(function()
        local gps = peek(Dependencies.GamePlayerState)
        if typeof(gps) == "table" and gps.TotalUnitPlacementCap then
            cap = unwrapYen(gps.TotalUnitPlacementCap) or 20
        end
    end)
    return cap
end

local function isAtTotalPlacementCap(owned, totalCap)
    return typeof(totalCap) == "number" and totalCap > 0 and owned >= totalCap
end

local function canPlaceMoreOfAsset(asset)
    local placed = countOwnPlacedByAsset(asset)
    local limit = getPlacementLimit(asset)
    return placed < limit, placed, limit
end

local function snapToPlaceableGround(pos)
    local ray = Ray.new(pos + Vector3.new(0, 15, 0), Vector3.new(0, -50, 0))
    local hitInst, hitPos = workspace:FindPartOnRay(ray)
    if hitInst then
        return CFrame.new(hitPos)
    end
    return CFrame.new(pos)
end

local function buildAAStylePlaceCFrames(asset, need)
    need = need or 4
    local parts = getPlaceableParts()
    local enemies = getEnemyPositions()
    local pathPoints = getPathPoints()
    local pathEnds = getPathEndPositions(pathPoints)

    local candidates = {}
    for _, part in ipairs(parts) do
        local cf = snapToPlaceableGround(part.Position)
        local score = scorePlacePosition(cf.Position, enemies, pathPoints, pathEnds)
        table.insert(candidates, { cf = cf, score = score })
    end

    table.sort(candidates, function(a, b)
        return a.score < b.score
    end)

    local result = {}
    for i = 1, math.min(need, #candidates) do
        table.insert(result, candidates[i].cf)
    end
    return result
end

local function canPlaceAt(asset, cframe)
    if not cframe then return false end
    return true
end

-- Exports
PlacementEngine.isMagicalUnit = isMagicalUnit
PlacementEngine.getFrontmostEnemy = getFrontmostEnemy
PlacementEngine.scorePlacePosition = scorePlacePosition
PlacementEngine.getAffordableSlotsOrdered = getAffordableSlotsOrdered
PlacementEngine.buildAAStylePlaceCFrames = buildAAStylePlaceCFrames
PlacementEngine.canPlaceAt = canPlaceAt
PlacementEngine.canPlaceMoreOfAsset = canPlaceMoreOfAsset
PlacementEngine.getPlacementLimit = getPlacementLimit
PlacementEngine.countOwnPlacedByAsset = countOwnPlacedByAsset
PlacementEngine.countOwnPlacedUnits = countOwnPlacedUnits
PlacementEngine.getTotalPlacementCap = getTotalPlacementCap
PlacementEngine.isAtTotalPlacementCap = isAtTotalPlacementCap
PlacementEngine.getSlotAsset = getSlotAsset
PlacementEngine.getSlotPlacementCost = getSlotPlacementCost
PlacementEngine.canAffordSlot = canAffordSlot
PlacementEngine.getHotbarSlots = getHotbarSlots
PlacementEngine.isFarmUnit = isFarmUnit
PlacementEngine.getEnemyPositions = getEnemyPositions
PlacementEngine.getPathEndPositions = getPathEndPositions
PlacementEngine.getPathPoints = getPathPoints
PlacementEngine.distToNearestPath = distToNearestPath
PlacementEngine.getGameYen = getGameYen

return PlacementEngine
