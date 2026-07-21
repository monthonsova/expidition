-- [[
--     AE Kaitun — In-Game Combat & Unit Placement Module
-- ]]

local InGame = {}
local Replicas = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Replicas.lua") or loadstring(readfile("expidition/src/Replicas.lua"))()
local PlacementEngine = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/PlacementEngine.lua") or loadstring(readfile("expidition/src/PlacementEngine.lua"))()
local AutoFarmManager = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/AutoFarmManager.lua") or loadstring(readfile("expidition/src/AutoFarmManager.lua"))()

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
        -- Act สุดท้าย — ห้าม AutoNext ไปแมพอื่น / ห้าม AutoRetry วนด่านเดิม
        pcall(function()
            Nodes.CLIENT_CHANGE_SETTING:FireServer("AutoRetry", false)
        end)
        task.wait(0.35)
        pcall(function()
            Nodes.CLIENT_CHANGE_SETTING:FireServer("AutoNext", false)
        end)
        print("[AE Kaitun] AutoNext = off | AutoRetry = off (ด่านสุดท้ายก่อน Grind)")
    else
        -- ฟาร์ม Act 1-5: ต้อง AutoNext ไปด่านถัดไป — ปิด AutoRetry กันวนซ้ำ
        pcall(function()
            Nodes.CLIENT_CHANGE_SETTING:FireServer("AutoRetry", false)
        end)
        task.wait(0.35)
        pcall(function()
            Nodes.CLIENT_CHANGE_SETTING:FireServer("AutoNext", true)
        end)
        print("[AE Kaitun] AutoNext = on | AutoRetry = off (Farm All Story)")
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
        AutoUpgradeOnPlacement = true,
        AutoAbilitiesOnPlacement = false,
        LockFarmsOnPlacement = false,
    }

    print("[AE Kaitun] Units/GFX settings → ยิงช้าๆ | AutoUpgradeOnPlacement = on")
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

local function waitForPlacementReady(timeout)
    timeout = timeout or 45
    local t0 = os.clock()
    while os.clock() - t0 < timeout do
        local hotbar = peek(Dependencies.HotbarState)
        local allowed = hotbar and hotbar.PlacementAllowed
        local active = peek(Shared.IsGameActive)
        local rep = getGamePlayerReplica()
        if rep and (allowed == true or active == true) then
            return true
        end
        task.wait(0.25)
    end
    return getGamePlayerReplica() ~= nil
end

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
                    print("[AE Kaitun] แมพครบแล้ว — กลับ lobby เพื่อเข้า Hard Act 1")
                    task.wait(0.5)
                    returnToLobbyFromMatch()
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
InGame.autoPlaceUnits = autoPlaceUnits
InGame.runInGame = runInGame

return InGame
