-- --     AE Kaitun — In-Game Combat & Unit Placement Module

local InGame = {}

local Core = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Core.lua") or loadstring(readfile("expidition/src/Core.lua"))()
local Utils = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Utils.lua") or loadstring(readfile("expidition/src/Utils.lua"))()
local Replicas = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Replicas.lua") or loadstring(readfile("expidition/src/Replicas.lua"))()
local PlacementEngine = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/PlacementEngine.lua") or loadstring(readfile("expidition/src/PlacementEngine.lua"))()
local AutoFarmManager = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/AutoFarmManager.lua") or loadstring(readfile("expidition/src/AutoFarmManager.lua"))()

local Services = Core.Services
local LocalPlayer = Core.LocalPlayer
local Nodes = Core.Nodes
local Dependencies = Core.Dependencies
local peek = Core.peek
local ReplicaClient = Core.ReplicaClient

local boostFPS = Utils.boostFPS

local isInGame = Replicas.isInGame
local getGamePlayerReplica = Replicas.getGamePlayerReplica

local getAffordableSlotsOrdered = PlacementEngine.getAffordableSlotsOrdered
local canPlaceMoreOfAsset = PlacementEngine.canPlaceMoreOfAsset
local getPlacementLimit = PlacementEngine.getPlacementLimit
local countOwnPlacedByAsset = PlacementEngine.countOwnPlacedByAsset
local countOwnPlacedUnits = PlacementEngine.countOwnPlacedUnits
local getTotalPlacementCap = PlacementEngine.getTotalPlacementCap
local isAtTotalPlacementCap = PlacementEngine.isAtTotalPlacementCap
local getSlotAsset = PlacementEngine.getSlotAsset
local getSlotPlacementCost = PlacementEngine.getSlotPlacementCost
local canAffordSlot = PlacementEngine.canAffordSlot
local getHotbarSlots = PlacementEngine.getHotbarSlots
local isFarmUnit = PlacementEngine.isFarmUnit
local getEnemyPositions = PlacementEngine.getEnemyPositions
local getPathEndPositions = PlacementEngine.getPathEndPositions
local getPathPoints = PlacementEngine.getPathPoints
local getThreatEnemies = PlacementEngine.getThreatEnemies
local minDistToPoints = PlacementEngine.minDistToPoints
local getGameYen = PlacementEngine.getGameYen
local buildAAStylePlaceCFrames = PlacementEngine.buildAAStylePlaceCFrames
local canPlaceAt = PlacementEngine.canPlaceAt
local getUnitCombatStats = PlacementEngine.getUnitCombatStats
local isMagicalUnit = PlacementEngine.isMagicalUnit

local getAutoFarm = AutoFarmManager.getAutoFarm
local getGrindStage = AutoFarmManager.getGrindStage
local getFarmState = AutoFarmManager.getFarmState
local isInGrindMode = AutoFarmManager.isInGrindMode
local refreshFarmTargetForLevel = AutoFarmManager.refreshFarmTargetForLevel
local tryEnterGrindAfterMapClear = AutoFarmManager.tryEnterGrindAfterMapClear
local shouldLockAutoNextForGrind = AutoFarmManager.shouldLockAutoNextForGrind
local getActiveStoryMap = AutoFarmManager.getActiveStoryMap
local returnToLobbyFromMatch = AutoFarmManager.returnToLobbyFromMatch
local markMatchResult = AutoFarmManager.markMatchResult
local restartCurrentMatch = AutoFarmManager.restartCurrentMatch
local nextStageFromMatch = AutoFarmManager.nextStageFromMatch
local syncFarmStateFromProgress = AutoFarmManager.syncFarmStateFromProgress

local placeRunning = false
local lastPlaceAt = 0

local function placeUnit(hotbarSlot, cframe)
    local rep = getGamePlayerReplica()
    if not rep then
        warn("[AE Kaitun] ไม่มี GamePlayerReplica — วางไม่ได้")
        return false
    end
    -- cooldown กันสแปม "Please wait before doing that again!"
    local now = os.clock()
    local gap = now - lastPlaceAt
    if gap < 0.85 then
        task.wait(0.85 - gap)
    end
    local slotNum = tonumber(hotbarSlot) or hotbarSlot
    lastPlaceAt = os.clock()
    local ok, err = pcall(function()
        rep:FireServer("PlaceGameUnit", slotNum, cframe)
    end)
    if not ok then
        warn("[AE Kaitun] Place error:", err)
        return false
    end
    return true
end

local function sellAllUnits()
    local rep = getGamePlayerReplica()
    if rep then
        rep:FireServer("SellAllGameUnits")
    end
end

local function enableAutoSkip()
    pcall(function()
        Nodes.CLIENT_TOGGLE_AUTO_SKIP_WAVES:FireServer()
    end)
end

local settingsApplied = false
local unitSettingsApplied = false
local lastStoryProgressMode = nil -- "grind" | "farm" | nil

local function applyStoryProgressSettings(force)
    if not getAutoFarm().Enabled then
        return
    end
    -- ตรวจเลเวล/แมพ Clear ใหม่ทุกครั้ง (สำคัญตอน Grind+AutoRetry ค้างในแมตช์)
    refreshFarmTargetForLevel()

    local st = getFarmState()
    if st.needProgressSettings then
        force = true
        st.needProgressSettings = false
    end

    -- เข้า grind ถ้ารอบนี้ CompletedMaps ครบแล้ว
    tryEnterGrindAfterMapClear()

    local lockNext = shouldLockAutoNextForGrind()
    local mode = isInGrindMode() and "grind" or (lockNext and "farm_last" or "farm")
    if not force and lastStoryProgressMode == mode then
        return
    end
    lastStoryProgressMode = mode

    if mode == "grind" then
        pcall(function()
            Nodes.CLIENT_CHANGE_SETTING:FireServer("AutoNext", false)
        end)
        task.wait(0.35)
        pcall(function()
            Nodes.CLIENT_CHANGE_SETTING:FireServer("AutoRetry", true)
        end)
        print("[AE Kaitun] AutoRetry = on | AutoNext = off (ล็อก",
            getGrindStage().ActName, getGrindStage().MapName, ")")
    elseif mode == "farm_last" then
        -- Act สุดท้าย — ห้าม AutoNext ไปแมพอื่น
        -- AutoRetry ปิด: แพ้จะให้ SHOW_END_SCREEN handler ของเรา Restart เอง
        -- ชนะ → handler / CompletedMaps poll ส่งกลับ lobby เข้า Grind
        pcall(function()
            Nodes.CLIENT_CHANGE_SETTING:FireServer("AutoRetry", false)
        end)
        task.wait(0.35)
        pcall(function()
            Nodes.CLIENT_CHANGE_SETTING:FireServer("AutoNext", false)
        end)
        print("[AE Kaitun] AutoNext = off | AutoRetry = off (ด่านสุดท้าย — Defeat เรา Restart เอง)")
    else
        -- Clear Act 1-N: AutoNext ตอนชนะไปด่านถัดไป
        -- AutoRetry ปิดกันเกม Restart ทับตอนชนะ — แพ้ให้ handler ของเรา Restart แทน
        pcall(function()
            Nodes.CLIENT_CHANGE_SETTING:FireServer("AutoRetry", false)
        end)
        task.wait(0.35)
        pcall(function()
            Nodes.CLIENT_CHANGE_SETTING:FireServer("AutoNext", true)
        end)
        print("[AE Kaitun] AutoNext = on | AutoRetry = off (Clear — Defeat เรา Restart เอง)")
    end
end

-- เมนู Units + กราฟิกเบา: ยิงทีละอันมีหน่วง (กัน Please wait)
local function applyUnitSettings()
    if unitSettingsApplied then
        return
    end
    if _G.Settings["Apply Unit Settings"] == false then
        return
    end
    unitSettingsApplied = true

    local autoUpgrade = _G.Settings["Auto Upgrade"] ~= false
    local autoAbilities = _G.Settings["Auto Abilities"] ~= false

    local opts = {
        -- กราฟิก / ศัตรูเบา
        LowDetailMode = true,
        CameraShakeEnabled = false,
        DepthOfFieldEnabled = false,
        DisplayEnemyEffects = false,
        DisplayEnemyStatusEffects = false,
        DisplayHealthBars = false,
        OtherCosmeticEnabled = false,
        OtherEmoteSFXEnabled = false,
        NightTimeEnabled = false,
        DisplayStageCutscenes = false,
        PathVisualizerEnabled = false,
        AreaHelpersEnabled = false,
        -- Units: ปิดหมด เปิดแค่ Auto-Upgrade
        OtherUnitsEnabled = false,
        OtherUnitVFXEnabled = false,
        OwnUnitVFXEnabled = false,
        AbilityVFXEnabled = false,
        UnitAuraEnabled = false,
        TraitAuraEnabled = false,
        BuffIndicatorsEnabled = false,
        DamageIndicatorsEnabled = false,
        DisplayPlacementHitboxes = false,
        DisplayUnitCircles = false,
        AutoPlacePhantoms = false,
        StrictAutoUpgrade = false,
        StrictPhantomPlacement = false,
        PrioritizePhantomPlacement = false,
        AutoUpgradeOnPlacement = autoUpgrade,
        AutoAbilitiesOnPlacement = autoAbilities,
        LockFarmsOnPlacement = false,
    }

    print("[AE Kaitun] Units/GFX settings → ยิงช้าๆ | AutoUpgrade =", autoUpgrade, "| AutoAbilities =", autoAbilities)
    for key, val in pairs(opts) do
        pcall(function()
            Nodes.CLIENT_CHANGE_SETTING:FireServer(key, val)
        end)
        task.wait(0.22) -- กัน Please wait
    end
end

local function enableAutoVoteSetting()
    -- Vote/Skip ยิงครั้งเดียว | AutoNext/Retry ปรับตามโหมด grind ได้ใหม่
    if not settingsApplied then
        settingsApplied = true
        pcall(function()
            Nodes.CLIENT_CHANGE_SETTING:FireServer("AutoVoteStart", true)
        end)
        task.wait(0.5)
        pcall(function()
            Nodes.CLIENT_CHANGE_SETTING:FireServer("AutoSkipWaves", true)
        end)
        task.wait(0.5)
    end
    applyStoryProgressSettings(false)
    task.spawn(applyUnitSettings)
end

-- หน้าต่าง "Start Game?" = VotePrompt → FireServer("Response", true)
local votedReplicas = setmetatable({}, { __mode = "k" })
local voteHooked = false

local function acceptVoteReplica(replica, reason)
    if not replica or votedReplicas[replica] then
        return
    end
    votedReplicas[replica] = true
    -- ไม่ print Vote Accept — สแปมจอตอนโหวตซ้ำ
    pcall(function()
        replica:FireServer("Response", true)
    end)
end

local function setupAutoVoteStart()
    if not _G.Settings["Auto Vote Start"] then
        return
    end

    enableAutoVoteSetting()

    if voteHooked then
        return
    end
    voteHooked = true

    pcall(function()
        ReplicaClient.OnNew("VotePrompt", function(replica)
            task.defer(function()
                for _ = 1, 20 do
                    local data = replica.Data
                    local params = data and (data.Parameters or data)
                    local title = params and tostring(params.Title or "")
                    local text = params and tostring(params.Text or "")
                    if title ~= "" or text ~= "" then
                        acceptVoteReplica(replica, title ~= "" and title or text)
                        return
                    end
                    task.wait(0.1)
                end
                acceptVoteReplica(replica, "VotePrompt(no title)")
            end)
        end)
    end)
end

-- Shared.IsGameActive จริงคือ FusionPackage.Shared (คนละตัวกับ ReplicatedStorage.Shared folder ที่เราใช้)
-- นิยาม = KeyOf(Dependencies.GameState, "Active") → อ่าน field ตรงจาก GameState เองได้เลย ไม่ต้อง require โมดูลเพิ่ม
local function isGameActive()
    local ok, gs = pcall(peek, Dependencies.GameState)
    if ok and typeof(gs) == "table" then
        return gs.Active == true
    end
    return false
end

-- SelectedHotbarIndex จริงคือ named-state จาก Fusion "State" extension (v4:GetState("SelectedHotbarIndex"))
-- ตัวเดียวกันทุกที่ที่เรียกชื่อนี้ (คีย์ตามชื่อ ไม่ผูกกับ scope ที่สร้าง) — ใช้ Dependencies.scope เรียกได้เลย
local function clearHotbarSelection()
    pcall(function()
        local scope = Dependencies.scope
        if scope and typeof(scope.GetState) == "function" then
            local state = scope:GetState("SelectedHotbarIndex")
            if state and typeof(state.set) == "function" then
                state:set(nil)
            end
        end
    end)
end

local function waitForPlacementReady(timeout)
    timeout = timeout or 45
    local t0 = os.clock()
    while os.clock() - t0 < timeout do
        local hotbar = peek(Dependencies.HotbarState)
        local allowed = hotbar and hotbar.PlacementAllowed
        local active = isGameActive()
        local rep = getGamePlayerReplica()
        if rep and (allowed == true or active == true) then
            return true
        end
        task.wait(0.25)
    end
    return getGamePlayerReplica() ~= nil
end

local function autoPlaceUnits()
    if not _G.Settings["Auto Place Units"] then
        return
    end
    if placeRunning then
        return
    end
    placeRunning = true

    waitForPlacementReady(6)

    local delaySec = math.clamp(tonumber(_G.Settings["Place Delay"]) or 0.85, 0.75, 2.5)
    local maxPerSlot = tonumber(_G.Settings["Max Place Per Slot"]) or 4

    task.spawn(function()
        local attempts = 0
        local everPlaced = false

        while placeRunning and isInGame() do
            attempts += 1

            local owned = countOwnPlacedUnits()
            local totalCap = getTotalPlacementCap()

            if isAtTotalPlacementCap(owned, totalCap) then
                print("[AE Kaitun] Reach TotalPlacementCap", owned, "/", totalCap, "-> Stop Placing")
                break
            end

            -- Fetch slots ordered by: 1) Magical units first -> 2) Expensive to Cheap
            local affordableSlots = getAffordableSlotsOrdered()

            if #affordableSlots == 0 then
                task.wait(0.7)
            else
                local placedThisRound = false

                for _, slot in ipairs(affordableSlots) do
                    if not placeRunning or not isInGame() then break end

                    local asset = getSlotAsset(slot)
                    if asset and asset ~= "" then
                        local canMore, placedN, limit = canPlaceMoreOfAsset(asset)
                        local cap = math.min(maxPerSlot, limit)

                        if placedN < cap then
                            -- Build placement CFrames (targeted near front-most enemy)
                            local cframes = buildAAStylePlaceCFrames(asset, cap - placedN)
                            local cf = cframes and cframes[1]

                            if cf and canPlaceAt(asset, cf) then
                                local yenNow = getGameYen()
                                print(("[AE Kaitun] Placing %s (Magical=%s, Slot=%d) %d/%d Yen=%s"):format(
                                    tostring(asset), tostring(isMagicalUnit(asset)), slot, placedN + 1, cap, tostring(yenNow)
                                ))

                                local beforeOwned = countOwnPlacedUnits()
                                local beforeAsset = countOwnPlacedByAsset(asset)

                                placeUnit(slot, cf)

                                task.wait(0.3)
                                local afterAsset = countOwnPlacedByAsset(asset)
                                local afterOwned = countOwnPlacedUnits()

                                if afterAsset > beforeAsset or afterOwned > beforeOwned then
                                    placedThisRound = true
                                    everPlaced = true
                                    task.wait(delaySec)
                                    break
                                end
                            end
                        end
                    end
                end

                if not placedThisRound then
                    task.wait(0.6)
                end
            end

            if attempts >= 300 then
                break
            end
        end

        placeRunning = false
    end)
end

local function setupAutoVoteStart()
    if not _G.Settings["Auto Vote Start"] then
        return
    end

    enableAutoVoteSetting()

    if voteHooked then
        return
    end
    voteHooked = true

    pcall(function()
        ReplicaClient.OnNew("VotePrompt", function(replica)
            task.defer(function()
                for _ = 1, 20 do
                    local data = replica.Data
                    local params = data and (data.Parameters or data)
                    local title = params and tostring(params.Title or "")
                    local text = params and tostring(params.Text or "")
                    if title ~= "" or text ~= "" then
                        acceptVoteReplica(replica, title ~= "" and title or text)
                        return
                    end
                    task.wait(0.1)
                end
                acceptVoteReplica(replica, "VotePrompt(no title)")
            end)
        end)
    end)
end

-- Shared.IsGameActive จริงคือ FusionPackage.Shared (คนละตัวกับ ReplicatedStorage.Shared folder ที่เราใช้)
-- นิยาม = KeyOf(Dependencies.GameState, "Active") → อ่าน field ตรงจาก GameState เองได้เลย ไม่ต้อง require โมดูลเพิ่ม
local function isGameActive()
    local ok, gs = pcall(peek, Dependencies.GameState)
    if ok and typeof(gs) == "table" then
        return gs.Active == true
    end
    return false
end

-- SelectedHotbarIndex จริงคือ named-state จาก Fusion "State" extension (v4:GetState("SelectedHotbarIndex"))
-- ตัวเดียวกันทุกที่ที่เรียกชื่อนี้ (คีย์ตามชื่อ ไม่ผูกกับ scope ที่สร้าง) — ใช้ Dependencies.scope เรียกได้เลย
local function clearHotbarSelection()
    pcall(function()
        local scope = Dependencies.scope
        if scope and typeof(scope.GetState) == "function" then
            local state = scope:GetState("SelectedHotbarIndex")
            if state and typeof(state.set) == "function" then
                state:set(nil)
            end
        end
    end)
end

local function waitForPlacementReady(timeout)
    timeout = timeout or 45
    local t0 = os.clock()
    while os.clock() - t0 < timeout do
        local hotbar = peek(Dependencies.HotbarState)
        local allowed = hotbar and hotbar.PlacementAllowed
        local active = isGameActive()
        local rep = getGamePlayerReplica()
        if rep and (allowed == true or active == true) then
            return true
        end
        task.wait(0.25)
    end
    return getGamePlayerReplica() ~= nil
end

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
    clearHotbarSelection()

    local delaySec = math.clamp(tonumber(_G.Settings["Place Delay"]) or 0.85, 0.75, 2.5)
    local maxPerSlot = tonumber(_G.Settings["Max Place Per Slot"]) or 4
    local smartPlaceCfg = _G.Settings["Smart Placement"]
    local smartPlaceOn = (typeof(smartPlaceCfg) ~= "table") or smartPlaceCfg.Enabled ~= false
    local carryFirst = smartPlaceOn and ((typeof(smartPlaceCfg) ~= "table") or smartPlaceCfg.CarryFirst ~= false)
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

            clearHotbarSelection()

            local slots = getAffordableSlotsOrdered()
            local owned = countOwnPlacedUnits()
            local totalCap = getTotalPlacementCap()
            local yenNow, yenSrc = getGameYen()

            local cheapestNeed = nil
            local underLimit = 0
            for _, slot in ipairs(slots) do
                local asset = getSlotAsset(slot)
                if asset then
                    local placed = countOwnPlacedByAsset(asset)
                    local lim = math.min(maxPerSlot, getPlacementLimit(asset))
                    if placed < lim then
                        underLimit += 1
                        skipAsset[asset] = nil
                        local cost = getSlotPlacementCost(slot)
                        if cost > 0 then
                            cheapestNeed = cheapestNeed and math.min(cheapestNeed, cost) or cost
                        end
                    else
                        skipAsset[asset] = true
                    end
                end
            end

            if attempts == 1 or attempts % 8 == 0 then
                print("[AE Kaitun] Place", attempts, "| owned=", owned, "/", totalCap or "?",
                    "| left=", underLimit, "| Yen=", yenNow, "(", yenSrc, ")",
                    "| slots=", #slots, "| need>=", cheapestNeed)
            end

            -- เต็มลิมิต: อั้นเฉพาะเมื่อไม่เหลือช่องที่จะวาง (กัน cap อ่านผิดแล้วหยุดทั้งที่ยังวางได้)
            if isAtTotalPlacementCap(owned, totalCap) and underLimit <= 0 then
                if attempts % 16 == 1 then
                    print("[AE Kaitun] เต็ม TotalPlacementCap", owned, "/", totalCap, "— หยุดวาง")
                end
                task.wait(2.5)
                continue
            end
            if isAtTotalPlacementCap(owned, totalCap) and underLimit > 0 then
                if attempts % 12 == 1 then
                    print("[AE Kaitun] cap=", totalCap, "owned=", owned,
                        "แต่ left=", underLimit, "— ลองวางต่อ (cap อาจอ่านต่ำเกิน)")
                end
            end

            if underLimit <= 0 or allAssetsAtLimit(slots) then
                task.wait(2.5)
                continue
            end

            -- เงินไม่พอจริงๆ เท่านั้น (nil = อ่านไม่ได้ → ลองวางต่อ)
            local seemBroke = (typeof(yenNow) == "number" and cheapestNeed ~= nil and yenNow < cheapestNeed)

            if seemBroke then
                if attempts == 1 or attempts % 6 == 0 then
                    print("[AE Kaitun] เงินไม่พอวาง | Yen=", yenNow, "(", yenSrc, ")",
                        "| ต้องการอย่างน้อย=", cheapestNeed, "— รอเวฟถัดไป")
                end
                if attempts % 4 == 0 then
                    pointCache = {}
                end
                task.wait(1.0)
                continue
            end

            -- เฟสวาง: 1) ดาเมจครบ Min → 2) ฟาร์มเงิน 1 ตัว → 3) ดาเมจต่อ
            local farmPhaseOn = _G.Settings["Place Farm After Combat"] ~= false
                or _G.Settings["Place Farm Last"] ~= false
            local minCombat = math.max(1, tonumber(_G.Settings["Min Combat Before Farm"]) or 2)
            local maxFarm = math.max(1, tonumber(_G.Settings["Max Farm Place"]) or 1)
            local combatOnField = 0
            local farmOnField = 0
            local hasFarmSlot = false
            for _, slot in ipairs(slots) do
                local asset = getSlotAsset(slot)
                if asset then
                    if isFarmUnit(asset) then
                        hasFarmSlot = true
                        farmOnField += countOwnPlacedByAsset(asset)
                    else
                        combatOnField += countOwnPlacedByAsset(asset)
                    end
                end
            end
            local phase = 3
            if farmPhaseOn then
                if combatOnField < minCombat then
                    phase = 1
                elseif hasFarmSlot and farmOnField < maxFarm then
                    phase = 2
                else
                    phase = 3
                end
            end
            if attempts == 1 or attempts % 10 == 0 then
                print("[AE Kaitun] PlacePhase=", phase,
                    "| combat=", combatOnField, "/", minCombat,
                    "| farm=", farmOnField, "/", maxFarm)
            end

            if phase == 2 then
                table.sort(slots, function(a, b)
                    local af = isFarmUnit(getSlotAsset(a)) and 0 or 1
                    local bf = isFarmUnit(getSlotAsset(b)) and 0 or 1
                    if af ~= bf then
                        return af < bf
                    end
                    return getSlotPlacementCost(a) < getSlotPlacementCost(b)
                end)
            elseif phase == 3 and carryFirst then
                -- เฟสดาเมจ (strategy Kaitun.lua): ฟาร์มไปท้าย → เน้นวาง Magical ก่อน → ถูกสุดก่อน
                local magicalFirst = _G.Settings["Place Magical First"] ~= false
                table.sort(slots, function(a, b)
                    local aa, ba = getSlotAsset(a), getSlotAsset(b)
                    local af = isFarmUnit(aa) and 1 or 0
                    local bf = isFarmUnit(ba) and 1 or 0
                    if af ~= bf then
                        return af < bf
                    end
                    -- เน้นเลือกวาง Magical ก่อน
                    if magicalFirst then
                        local am = isMagicalUnit(aa) and 1 or 0
                        local bm = isMagicalUnit(ba) and 1 or 0
                        if am ~= bm then
                            return am > bm
                        end
                    end
                    -- ตัวแรงกว่า (DPS) ก่อน แล้วค่อยถูกสุด
                    local ad = getUnitCombatStats(aa).dps
                    local bd = getUnitCombatStats(ba).dps
                    if ad ~= bd then
                        return ad > bd
                    end
                    return getSlotPlacementCost(a) < getSlotPlacementCost(b)
                end)
            end

            local placedThisRound = false
            local noPoint = 0
            local tried = 0

            for _, slot in ipairs(slots) do
                if not isInGame() then
                    placeRunning = false
                    return
                end

                if isAtTotalPlacementCap(countOwnPlacedUnits(), totalCap) and underLimit <= 0 then
                    break
                end

                local asset = getSlotAsset(slot)
                if not asset or asset == "" then
                    continue
                end
                if skipAsset[asset] then
                    continue
                end
                local placedN = countOwnPlacedByAsset(asset)
                local limit = getPlacementLimit(asset)
                local cap = math.min(maxPerSlot, limit)
                if isFarmUnit(asset) then
                    cap = math.min(cap, maxFarm)
                end
                if placedN >= cap then
                    skipAsset[asset] = true
                    continue
                end

                -- phase1: ข้ามฟาร์ม | phase2: วางแค่ฟาร์ม | phase3: ข้ามฟาร์ม วางดาเมจ
                if farmPhaseOn then
                    local farm = isFarmUnit(asset)
                    if phase == 1 and farm then
                        continue
                    end
                    if phase == 2 and not farm then
                        continue
                    end
                    if phase == 3 and farm then
                        continue
                    end
                end

                local afford = canAffordSlot(slot)
                if not afford then
                    continue
                end

                local cf = nextPlaceCFrame(asset)
                if not cf then
                    noPoint += 1
                    continue
                end

                if not canPlaceAt(asset, cf) then
                    dropPoint(asset, cf)
                    noPoint += 1
                    continue
                end

                local beforeOwned = countOwnPlacedUnits()
                local beforeAsset = placedN
                if attempts <= 3 or placedThisRound == false then
                    print(("[AE Kaitun] Place %s %d/%d Yen=%s phase=%d"):format(
                        tostring(asset), beforeAsset, cap, tostring(yenNow), phase
                    ))
                end
                tried += 1
                local fired = placeUnit(slot, cf)

                local startWait = os.clock()
                local spawned = false
                local waitCap = math.clamp(delaySec + 0.35, 0.7, 1.4)
                while os.clock() - startWait < waitCap do
                    if countOwnPlacedByAsset(asset) > beforeAsset or countOwnPlacedUnits() > beforeOwned then
                        spawned = true
                        break
                    end
                    task.wait(0.08)
                end
                local elapsed = os.clock() - startWait
                if elapsed < delaySec then
                    task.wait(delaySec - elapsed)
                end

                local afterAsset = countOwnPlacedByAsset(asset)
                local afterOwned = countOwnPlacedUnits()
                if spawned or afterAsset > beforeAsset or afterOwned > beforeOwned then
                    placedThisRound = true
                    everPlaced = true
                    failStreak = 0
                    pointCache = {}
                    local gained = math.max(0, afterAsset - beforeAsset)
                    if isFarmUnit(asset) then
                        farmOnField += gained
                        if farmOnField >= maxFarm then
                            phase = 3
                        end
                    else
                        combatOnField += gained
                        if phase == 1 and combatOnField >= minCombat then
                            if hasFarmSlot and farmOnField < maxFarm then
                                phase = 2
                                break
                            else
                                phase = 3
                            end
                        end
                    end
                    if afterAsset >= cap then
                        skipAsset[asset] = true
                    end
                else
                    dropPoint(asset, cf)
                    if fired then
                        failStreak += 1
                    end
                    if failStreak >= 4 then
                        skipAsset[asset] = true
                    end
                    if isAtTotalPlacementCap(afterOwned, totalCap) or failStreak >= 5 then
                        pointCache = {}
                        break
                    end
                end
            end

            if noPoint >= underLimit and underLimit > 0 and not placedThisRound then
                local now = os.clock()
                if now - lastRebuildWarn > 5 then
                    lastRebuildWarn = now
                    print("[AE Kaitun] เงินพอแต่หาจุดวางไม่ได้ | Yen=", yenNow,
                        "| slots=", #slots, "| left=", underLimit, "— รีบิลด์จุด")
                end
                pointCache = {}
                task.wait(1.0)
            elseif tried > 0 and not placedThisRound then
                -- ยิงแล้วไม่ติด → ชะลอแรง กันสแปม
                pointCache = {}
                task.wait(math.clamp(0.8 + failStreak * 0.25, 0.8, 2.5))
            elseif not placedThisRound then
                task.wait(0.55)
            else
                task.wait(0.15)
            end
        end
        placeRunning = false
    end)
end

------------------------------------------------------------------------
-- Defeat / Victory recovery (SHOW_END_SCREEN)
-- ปัญหาเดิม: Clear mode ปิด AutoRetry → แพ้แล้วค้างหน้า Defeat จน AFK ตาย
-- ทางออก: ฟัง SHOW_END_SCREEN เอง
--   Defeat  → Restart ด่านเดิม (ไม่ขยับคิว)
--   Victory → ปล่อย AutoNext / หรือกลับ lobby ถ้าด่านสุดท้ายก่อน Grind
-- Soft-reset: แพ้ติดกันหลายครั้ง → กลับ lobby แล้วเข้าคิวใหม่ (เซิร์ฟใหม่)
------------------------------------------------------------------------
local endScreenHooked = false
local endScreenHandling = false

local function getFailSoftResetThreshold()
    local n = tonumber(_G.Settings["Fail Soft Reset"])
    if n == nil then
        local af = _G.Settings["Auto Farm"]
        if typeof(af) == "table" then
            n = tonumber(af.FailSoftReset)
        end
    end
    if n == nil or n < 0 then
        n = 8 -- 0 = ปิด soft reset
    end
    return n
end

local function setupEndScreenHandler()
    if endScreenHooked then
        return
    end
    if not Nodes or not Nodes.SHOW_END_SCREEN then
        warn("[AE Kaitun] ไม่พบ Nodes.SHOW_END_SCREEN — Defeat recovery ใช้ไม่ได้")
        return
    end
    endScreenHooked = true

    pcall(function()
        Nodes.SHOW_END_SCREEN:Connect(function(result)
            if typeof(result) ~= "table" then
                return
            end
            if endScreenHandling then
                return
            end
            endScreenHandling = true

            task.spawn(function()
                local okHandle, errHandle = pcall(function()
                    local victory = result.Victory == true
                    local restartDisabled = result.RestartDisabled == true
                    local hasNext = result.HasNextStage == true
                    local st = markMatchResult(victory)

                    if victory then
                        print(("[AE Kaitun] ★ Victory | wins=%d fails=%d | HasNext=%s"):format(
                            st.totalWins or 0, st.totalFails or 0, tostring(hasNext)
                        ))
                        if getAutoFarm().Enabled then
                            task.wait(1.2)
                            applyStoryProgressSettings(true)
                            -- เคลียร์แมพครบแล้ว → กลับ lobby เข้า Grind (ห้าม Next ไปแมพอื่น)
                            if tryEnterGrindAfterMapClear() then
                                print("[AE Kaitun] Victory ครบแมพ Clear — กลับ lobby → Grind")
                                returnToLobbyFromMatch("victory→grind")
                                return
                            end
                            -- ไม่มีด่านถัดไปในแมตช์นี้ → กลับ lobby sync แมพถัดไป (FlowerForest ฯลฯ)
                            if not hasNext then
                                print("[AE Kaitun] Victory ไม่มี Next ในแมตช์ — กลับ lobby sync คิว")
                                task.wait(0.8)
                                syncFarmStateFromProgress()
                                if tryEnterGrindAfterMapClear() then
                                    returnToLobbyFromMatch("victory→grind")
                                else
                                    returnToLobbyFromMatch("victory→next-map")
                                end
                                return
                            end
                            -- Mid-clear: รอ AutoNext ของเกม; ค้างหน้าผลนาน → Next เอง
                            if not isInGrindMode() and not shouldLockAutoNextForGrind() then
                                task.wait(4.5)
                                local stillEnded = false
                                pcall(function()
                                    local gs = peek(Dependencies.GameState)
                                    if typeof(gs) == "table" and gs.Active == false then
                                        stillEnded = true
                                    end
                                end)
                                if stillEnded and isInGame() then
                                    print("[AE Kaitun] AutoNext ค้าง — บังคับ Next เอง")
                                    nextStageFromMatch("victory fallback")
                                    placeRunning = false
                                end
                            elseif shouldLockAutoNextForGrind() and isInGame() then
                                -- Act สุดท้ายของแมพ / ด่านสุดท้ายทั้งลิสต์ → กลับ lobby คิวต่อ (ห้ามปล่อย AutoNext วน Act1)
                                task.wait(1.2)
                                syncFarmStateFromProgress()
                                if tryEnterGrindAfterMapClear() then
                                    returnToLobbyFromMatch("victory last-act→grind")
                                else
                                    returnToLobbyFromMatch("victory last-act→next-map")
                                end
                                return
                            end
                        end
                    else
                        print(("[AE Kaitun] ✗ Defeat | failStreak=%d totalFails=%d | RestartDisabled=%s"):format(
                            st.failStreak or 0, st.totalFails or 0, tostring(restartDisabled)
                        ))

                        local softN = getFailSoftResetThreshold()
                        -- Soft reset: แพ้ติดกันเยอะ → กลับ lobby + SmartPlay (สุ่ม/ทีม/ฟีด/evolve)
                        if softN > 0 and (st.failStreak or 0) >= softN and getAutoFarm().Enabled then
                            print(("[AE Kaitun] แพ้ติดกัน %d ครั้ง → Soft Reset + SmartPlay"):format(st.failStreak))
                            st.needSmartPlay = true
                            st.failStreak = 0
                            syncFarmStateFromProgress()
                            task.wait(0.6)
                            returnToLobbyFromMatch("soft-reset after fails")
                            return
                        end

                        if restartDisabled then
                            print("[AE Kaitun] RestartDisabled — กลับ lobby + SmartPlay แล้วเข้าคิวด่านเดิมใหม่")
                            st.needSmartPlay = true
                            syncFarmStateFromProgress()
                            task.wait(0.5)
                            returnToLobbyFromMatch("restart disabled")
                            return
                        end

                        -- Restart ด่านเดิม (ไม่ขยับคิว — CompletedMaps ยังไม่เคลียร์)
                        task.wait(1.4)
                        if not isInGame() then
                            return
                        end
                        placeRunning = false
                        restartCurrentMatch(("defeat streak=%d"):format(st.failStreak or 0))
                        -- กัน Intermission signal ซ้ำค่าเดิมแล้วไม่วางใหม่ → บังคับ Place หลังรีสตาร์ท
                        task.delay(3.5, function()
                            if isInGame() and not placeRunning then
                                print("[AE Kaitun] หลัง Restart — บังคับ Place ใหม่")
                                autoPlaceUnits()
                            end
                        end)
                    end
                end)
                if not okHandle then
                    warn("[AE Kaitun] EndScreen handler error:", errHandle)
                end
                task.wait(0.5)
                endScreenHandling = false
            end)
        end)
    end)
    print("[AE Kaitun] EndScreen handler = on (Defeat→Restart / SoftReset)")
end

local inGameStarted = false
local function runInGame()
    if inGameStarted then
        print("[AE Kaitun] In-game เริ่มไปแล้ว — ข้าม")
        return
    end
    inGameStarted = true

    print("[AE Kaitun] In-game mode")
    -- Boost รันพื้นหลัง — ไม่บล็อควางยูนิต
    task.spawn(boostFPS)
    task.spawn(applyUnitSettings)
    setupAutoVoteStart()
    setupEndScreenHandler()
    -- ตรวจ CompletedMaps ทุกครั้งที่เข้าแมตช์ (กัน AutoNext ไปแมพอื่นหลัง Act 5)
    if getAutoFarm().Enabled then
        applyStoryProgressSettings(true)
    end

    if _G.Settings["Auto Skip Waves"] then
        enableAutoSkip()
    end

    task.wait(0.25)
    autoPlaceUnits()

    -- AutoUpgrade ตั้งใน applyUnitSettings แล้ว — อย่ายิงซ้ำที่นี่

    -- เฝ้าวางต่อเนื่อง: ถ้าลูปตายแต่ยังเงินพอ/ยังไม่ครบลิมิต → เริ่มใหม่
    task.spawn(function()
        while isInGame() do
            task.wait(6)
            if not isInGame() then
                break
            end
            if placeRunning then
                continue
            end
            local owned = countOwnPlacedUnits()
            local totalCap = getTotalPlacementCap()
            -- ไม่ข้ามแค่เพราะ cap — ถ้ายังมีชนิดที่วางไม่ครบ ให้สตาร์ทต่อ
            local slots = getHotbarSlots()
            local need = false
            for _, slot in ipairs(slots) do
                local asset = getSlotAsset(slot)
                if asset and select(1, canPlaceMoreOfAsset(asset)) then
                    need = true
                    break
                end
            end
            if need and not isAtTotalPlacementCap(owned, totalCap) then
                print("[AE Kaitun] ยังวางไม่ครบ — สตาร์ท Place ใหม่ (", owned, "/", totalCap or "?", ")")
                autoPlaceUnits()
            elseif need and isAtTotalPlacementCap(owned, totalCap) then
                -- cap บอกเต็ม แต่ยัง left ตาม per-slot — ลองต่อ (cap อาจผิด)
                print("[AE Kaitun] cap บอกเต็มแต่ยังมีโควต้าต่อช่อง — ลองวางต่อ (", owned, "/", totalCap, ")")
                autoPlaceUnits()
            end
        end
    end)

    -- ตรวจ grind / ปิด AutoNext ก่อนด่านสุดท้าย | Intermission → วางใหม่
    -- + ออก Grind เมื่อเลเวลปลดแมพ Clear ใหม่ (กัน AutoRetry ค้าง Hard Act 1)
    task.spawn(function()
        local lastIntermission = peek(Dependencies.IntermissionStart)
        local lastCheck = 0
        local returnedForGrind = false
        local returnedForClear = false
        while isInGame() do
            if getAutoFarm().Enabled and (os.clock() - lastCheck) >= 5 then
                lastCheck = os.clock()
                local wasGrind = isInGrindMode()
                applyStoryProgressSettings(false)

                -- Lv ถึง MapsByLevel ใหม่ / แมพ Clear ยังไม่ครบ → ออก Grind กลับ lobby
                if wasGrind and not isInGrindMode() and not returnedForClear then
                    returnedForClear = true
                    lastStoryProgressMode = nil
                    print(("[AE Kaitun] ต้อง Clear %s — ปิด AutoRetry แล้วกลับ lobby"):format(
                        getActiveStoryMap()
                    ))
                    pcall(function()
                        Nodes.CLIENT_CHANGE_SETTING:FireServer("AutoRetry", false)
                    end)
                    pcall(function()
                        Nodes.CLIENT_CHANGE_SETTING:FireServer("AutoNext", false)
                    end)
                    task.wait(0.5)
                    returnToLobbyFromMatch()
                -- เคลียร์แมพปัจจุบันครบแล้วแต่ยังอยู่ในแมตช์ → กลับ lobby เข้า Grind
                elseif not wasGrind and tryEnterGrindAfterMapClear() and not returnedForGrind then
                    returnedForGrind = true
                    print("[AE Kaitun] Story เคลียร์ครบทุกแมพ — กลับ lobby เข้า Grind")
                    task.wait(0.5)
                    returnToLobbyFromMatch("poll→grind")
                elseif not isInGrindMode() then
                    -- ย้ำปิด AutoRetry ระหว่างฟาร์ม Act 1-5 กันวนด่านเดิม
                    pcall(function()
                        Nodes.CLIENT_CHANGE_SETTING:FireServer("AutoRetry", false)
                    end)
                    if shouldLockAutoNextForGrind() then
                        pcall(function()
                            Nodes.CLIENT_CHANGE_SETTING:FireServer("AutoNext", false)
                        end)
                    else
                        pcall(function()
                            Nodes.CLIENT_CHANGE_SETTING:FireServer("AutoNext", true)
                        end)
                    end
                end
            end

            local cur = peek(Dependencies.IntermissionStart)
            if cur ~= nil and cur ~= lastIntermission then
                lastIntermission = cur
                if getAutoFarm().Enabled then
                    local wasGrind = isInGrindMode()
                    applyStoryProgressSettings(true)
                    if wasGrind and not isInGrindMode() and not returnedForClear then
                        returnedForClear = true
                        lastStoryProgressMode = nil
                        print(("[AE Kaitun] Intermission: ต้อง Clear %s — กลับ lobby"):format(
                            getActiveStoryMap()
                        ))
                        pcall(function()
                            Nodes.CLIENT_CHANGE_SETTING:FireServer("AutoRetry", false)
                        end)
                        task.wait(0.4)
                        returnToLobbyFromMatch()
                    elseif isInGrindMode() then
                        print("[AE Kaitun] Intermission (Grind) — ย้ำล็อกด่าน")
                    else
                        print("[AE Kaitun] Intermission ใหม่ — วางยูนิตอีกครั้ง")
                        placeRunning = false
                        task.wait(0.5)
                        if isInGame() then
                            autoPlaceUnits()
                        end
                    end
                else
                    print("[AE Kaitun] Intermission ใหม่ — วางยูนิตอีกครั้ง")
                    placeRunning = false
                    task.wait(0.5)
                    if isInGame() then
                        autoPlaceUnits()
                    end
                end
            end
            task.wait(0.35)
        end
        inGameStarted = false
        placeRunning = false
    end)
end



InGame.placeUnit = placeUnit
InGame.sellAllUnits = sellAllUnits
InGame.enableAutoSkip = enableAutoSkip
InGame.applyStoryProgressSettings = applyStoryProgressSettings
InGame.applyUnitSettings = applyUnitSettings
InGame.enableAutoVoteSetting = enableAutoVoteSetting
InGame.acceptVoteReplica = acceptVoteReplica
InGame.setupAutoVoteStart = setupAutoVoteStart
InGame.setupEndScreenHandler = setupEndScreenHandler
InGame.autoPlaceUnits = autoPlaceUnits
InGame.runInGame = runInGame

return InGame
