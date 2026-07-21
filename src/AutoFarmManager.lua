-- [[
--     AE Kaitun — Auto Farm Progression Module
-- ]]

local AutoFarmManager = {}

local Replicas = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Replicas.lua") or loadstring(readfile("expidition/src/Replicas.lua"))()

local function getFarmState()
    local g = getgenv()
    if typeof(g.AE_FarmState) ~= "table" then
        g.AE_FarmState = {
            mapIndex = 1,
            actIndex = 1,
            diffIndex = 1,
            inMatch = false,
            grindMode = false,
            activeMap = nil,
        }
    end
    return g.AE_FarmState
end

local function isInGrindMode()
    return getFarmState().grindMode == true
end

-- เลเวลบัญชี (ใช้เลือกแมพอัตโนมัติ)

local function getAutoFarm()
    local af = _G.Settings["Auto Farm"]
    if typeof(af) ~= "table" then
        af = {}
    end
    local clear = typeof(af.Clear) == "table" and af.Clear or af
    local grind = typeof(af.Grind) == "table" and af.Grind or {}

    local function pickFrom(t, key, legacyKey, default)
        local v = t[key]
        if v == nil and legacyKey then
            v = af[legacyKey]
        end
        if v == nil and legacyKey then
            v = _G.Settings[legacyKey]
        end
        if v == nil then
            return default
        end
        return v
    end

    local mapsByLevel = clear.MapsByLevel
    if typeof(mapsByLevel) ~= "table" then
        mapsByLevel = af.MapsByLevel
    end
    if typeof(mapsByLevel) ~= "table" then
        mapsByLevel = {
            { MinLevel = 1,                                                        Map = "SchoolGrounds" },
            { MinLevel = tonumber(_G.Settings["FlowerForest Unlock Level"]) or 15, Map = "FlowerForest" },
        }
    end

    local grindEnabled = grind.Enabled
    if grindEnabled == nil then
        grindEnabled = af.LoopHardAct1AfterClear
    end
    if grindEnabled == nil then
        grindEnabled = af.ClearHardFirstLatest
    end
    if grindEnabled == nil then
        grindEnabled = af.GrindAfterClear
    end
    if grindEnabled == nil then
        grindEnabled = _G.Settings["Grind After Clear"]
    end
    if grindEnabled == nil then
        grindEnabled = true
    end

    local clearEnabled = clear.Enabled
    if clearEnabled == nil then
        clearEnabled = true
    end

    local afterClear = grind.AfterClear
    if afterClear == nil then
        afterClear = true
    end

    local grindMap = grind.Map or grind.MapName
    if grindMap ~= nil then
        grindMap = tostring(grindMap)
        if grindMap == "" then
            grindMap = nil
        end
    end

    return {
        Enabled = (function()
            if af.Enabled ~= nil then
                return af.Enabled ~= false
            end
            if _G.Settings["Farm All Story"] ~= nil then
                return _G.Settings["Farm All Story"] ~= false
            end
            return true
        end)(),
        -- Clear stage
        ClearEnabled = clearEnabled ~= false,
        ByLevel = pickFrom(clear, "ByLevel", "Auto Story By Level", true) ~= false,
        MapsByLevel = mapsByLevel,
        Maps = (typeof(clear.Maps) == "table" and clear.Maps)
            or (typeof(af.Maps) == "table" and af.Maps)
            or _G.Settings["Story Maps"]
            or { "SchoolGrounds", "FlowerForest", "Dressrosa", "KingsTomb", "FairyKingForest" },
        Acts = (typeof(clear.Acts) == "table" and clear.Acts)
            or (typeof(af.Acts) == "table" and af.Acts)
            or _G.Settings["Story Acts"]
            or { "Act 1", "Act 2", "Act 3", "Act 4", "Act 5" },
        Difficulties = (typeof(clear.Difficulties) == "table" and clear.Difficulties)
            or (typeof(af.Difficulties) == "table" and af.Difficulties)
            or _G.Settings["Story Difficulties"]
            or { "Normal" },
        Loop = pickFrom(clear, "Loop", "Farm Loop", false) == true,
        SkipCleared = pickFrom(clear, "SkipCleared", "Skip Cleared Stages", true) ~= false,
        -- Grind loop
        LoopHardAct1AfterClear = grindEnabled ~= false,
        GrindAfterClear = afterClear ~= false,
        GrindMap = grindMap,
        GrindAct = tostring(grind.Act or "Act 1"),
        GrindDifficulty = tostring(grind.Difficulty or "Hard"),
    }
end

-- คิวมือ: Settings.Queue (fallback คีย์แบนเดิมบน Settings)
local function getQueueSettings()
    local s = _G.Settings
    local q = typeof(s["Queue"]) == "table" and s["Queue"] or nil
    if not q then
        q = {}
        s["Queue"] = q
    end
    -- ย้ายจากคีย์แบนเดิมครั้งเดียว
    if q["Gamemode"] == nil and s["Gamemode"] ~= nil then
        q["Gamemode"] = s["Gamemode"]
    end
    if q["MapName"] == nil and s["MapName"] ~= nil then
        q["MapName"] = s["MapName"]
    end
    if q["ActName"] == nil and s["ActName"] ~= nil then
        q["ActName"] = s["ActName"]
    end
    if q["Difficulty"] == nil and s["Difficulty"] ~= nil then
        q["Difficulty"] = s["Difficulty"]
    end
    return q
end

-- forward declare: getActiveStoryMap เรียกตอนรันหลังฟังก์ชันนี้ถูกกำหนด
local isMapFullyCleared

-- แมพ Clear เป้าหมาย: ในแมพที่ปลดตามเลเวล เลือกตัวที่ยังไม่เคลียร์ครบก่อน (MinLevel น้อย→มาก)
-- ถ้าเคลียร์ครบทุกแมพที่ปลดแล้ว → ใช้แมพเลเวลสูงสุด (สำหรับ Grind fallback)
local function getActiveStoryMap()
    local af = getAutoFarm()
    if not af.ByLevel then
        for _, map in ipairs(af.Maps) do
            if isMapFullyCleared and not isMapFullyCleared(map) then
                return map
            elseif not isMapFullyCleared then
                return af.Maps[1] or "SchoolGrounds"
            end
        end
        return af.Maps[1] or "SchoolGrounds"
    end
    local lvl = getAccountLevel()
    local bestAny = "SchoolGrounds"
    local bestAnyMin = -1
    local bestUncleared = nil
    local bestUnclearedMin = math.huge
    for _, row in ipairs(af.MapsByLevel) do
        if typeof(row) == "table" then
            local minLv = tonumber(row.MinLevel) or 1
            local map = row.Map or row.MapName
            if map and lvl >= minLv then
                if minLv >= bestAnyMin then
                    bestAnyMin = minLv
                    bestAny = tostring(map)
                end
                local uncleared = true
                if isMapFullyCleared then
                    uncleared = not isMapFullyCleared(tostring(map))
                end
                if uncleared and minLv < bestUnclearedMin then
                    bestUnclearedMin = minLv
                    bestUncleared = tostring(map)
                end
            end
        end
    end
    return bestUncleared or bestAny
end

-- แมพ Grind (ตั้งเองได้ — ว่าง = ตาม Clear / เลเวล)
local function getGrindMap()
    local af = getAutoFarm()
    if af.GrindMap then
        return af.GrindMap
    end
    return getActiveStoryMap()
end

local function getStoryMaps()
    local af = getAutoFarm()
    if not af.ClearEnabled then
        return {}
    end
    if af.ByLevel then
        return { getActiveStoryMap() }
    end
    return af.Maps
end

local function getStoryActs()
    return getAutoFarm().Acts
end

local function getStoryDifficulties()
    return getAutoFarm().Difficulties
end

-- ฟาร์มเรื่อย = Grind.Map (หรือแมพ Clear) + Grind.Act + Grind.Difficulty
local function getGrindStage()
    local af = getAutoFarm()
    return {
        MapName = getGrindMap(),
        ActName = af.GrindAct or "Act 1",
        Difficulty = af.GrindDifficulty or "Hard",
        Gamemode = "Story",
    }
end

local function buildStoryStageList()
    local maps = getStoryMaps()
    local acts = getStoryActs()
    local diffs = getStoryDifficulties()
    local list = {}
    for _, diff in ipairs(diffs) do
        for _, map in ipairs(maps) do
            for _, act in ipairs(acts) do
                table.insert(list, {
                    MapName = map,
                    ActName = act,
                    Difficulty = diff,
                    Gamemode = "Story",
                })
            end
        end
    end
    return list
end

local function getCurrentFarmStage()
    if isInGrindMode() then
        return getGrindStage(), 0, 0
    end
    local list = buildStoryStageList()
    if #list == 0 then
        return nil
    end
    local st = getFarmState()
    local maps = getStoryMaps()
    local acts = getStoryActs()
    local diffs = getStoryDifficulties()
    local mi = math.clamp(st.mapIndex or 1, 1, math.max(#maps, 1))
    local ai = math.clamp(st.actIndex or 1, 1, math.max(#acts, 1))
    local di = math.clamp(st.diffIndex or 1, 1, math.max(#diffs, 1))
    local idx = ((di - 1) * #maps * #acts) + ((mi - 1) * #acts) + ai
    return list[idx] or list[1], idx, #list
end

-- CompletedMaps.Story.SchoolGrounds["Act 1"].Normal = { ClearCount = ... }
local function isActCleared(mapName, actName, difficulty)
    local data = peek(Dependencies.PlayerData)
    local cm = data and data.CompletedMaps
    if typeof(cm) ~= "table" then
        return false
    end
    local story = cm.Story
    local mapT = story and story[mapName]
    local actT = mapT and mapT[actName]
    if actT == nil then
        return false
    end
    if actT == true then
        return true
    end
    if typeof(actT) ~= "table" then
        return false
    end

    -- ถ้าระบุ Difficulty แล้ว → ดูเฉพาะช่องนั้น (อย่าเอา Hard มาถือว่าเคลียร์ Normal)
    if difficulty then
        local diffT = actT[difficulty]
        if diffT == true then
            return true
        end
        if typeof(diffT) == "table" then
            return (tonumber(diffT.ClearCount) or 0) > 0
        end
        -- รูปแบบเก่าไม่มีแยก Normal/Hard
        if typeof(actT.ClearCount) == "number" then
            return actT.ClearCount > 0
        end
        return false
    end

    if typeof(actT.ClearCount) == "number" then
        return actT.ClearCount > 0
    end
    for _, v in pairs(actT) do
        if v == true then
            return true
        end
        if typeof(v) == "table" and (tonumber(v.ClearCount) or 0) > 0 then
            return true
        end
    end
    return false
end

isMapFullyCleared = function(mapName, acts, diffs)
    acts = acts or getStoryActs()
    diffs = diffs or getStoryDifficulties()
    if not mapName or mapName == "" then
        return false
    end
    for _, diff in ipairs(diffs) do
        for _, act in ipairs(acts) do
            if not isActCleared(mapName, act, diff) then
                return false
            end
        end
    end
    return true
end

-- พร้อมเข้า Grind หรือยัง (ตาม Clear.Enabled / Grind.AfterClear)
local function canEnterGrindMode()
    local af = getAutoFarm()
    if not af.LoopHardAct1AfterClear then
        return false
    end
    if not af.ClearEnabled then
        return true
    end
    if not af.GrindAfterClear then
        return true
    end
    return isMapFullyCleared(getActiveStoryMap())
end

-- เลเวลขึ้นแล้วเปลี่ยนแมพ → ออกจาก grind เก่า เริ่ม Normal 1-5 ของแมพใหม่
local function refreshFarmTargetForLevel()
    local af = getAutoFarm()
    if not af.ByLevel or not af.ClearEnabled then
        -- ปิด Clear → ถ้าเปิด Grind ให้เข้า grind ได้เลย
        if not af.ClearEnabled and af.LoopHardAct1AfterClear then
            local st = getFarmState()
            if not st.grindMode and canEnterGrindMode() then
                st.grindMode = true
            end
        end
        return false
    end
    local map = getActiveStoryMap()
    local st = getFarmState()
    local prev = st.activeMap
    local changed = false

    -- grind ค้าง / เลเวลปลดแมพใหม่ที่ยังไม่เคลียร์ → บังคับออก Grind
    if st.grindMode and af.GrindAfterClear then
        if not isMapFullyCleared(map) then
            st.grindMode = false
            st.needProgressSettings = true
            changed = true
            print(("[AE Kaitun] ออก Grind — ต้อง Clear %s Normal 1-5 ก่อน (Lv %d)"):format(
                map, getAccountLevel()
            ))
        end
    end

    if st.activeMap ~= map then
        st.activeMap = map
        st.grindMode = false
        st.mapIndex = 1
        st.actIndex = 1
        st.diffIndex = 1
        st.needProgressSettings = true
        changed = true
        if prev ~= nil then
            print(("[AE Kaitun] เลเวล %d → เปลี่ยนแมพ Clear %s → %s (เริ่ม Normal Act 1-5)"):format(
                getAccountLevel(), tostring(prev), map
            ))
        else
            print(("[AE Kaitun] แมพ Clear อัตโนมัติ = %s (Lv %d)"):format(map, getAccountLevel()))
        end
    end

    return changed
end

local function enterGrindMode(reason)
    local st = getFarmState()
    if st.grindMode then
        return true
    end
    if not canEnterGrindMode() then
        return false
    end
    st.grindMode = true
    st.needProgressSettings = true -- ให้รอบถัดไปยิง AutoRetry / ปิด AutoNext ใหม่
    local g = getGrindStage()
    print(("[AE Kaitun] Grind mode — ล็อก %s | %s | %s (ไม่ไปด่านถัดไป)%s"):format(
        g.MapName, g.ActName, g.Difficulty,
        reason and (" | " .. tostring(reason)) or ""
    ))
    return true
end

local function tryEnterGrindAfterMapClear()
    if not getAutoFarm().LoopHardAct1AfterClear then
        return false
    end
    if isInGrindMode() then
        return true
    end
    if not canEnterGrindMode() then
        return false
    end
    local af = getAutoFarm()
    local reason
    if not af.ClearEnabled then
        reason = "Clear ปิด — Grind ทันที"
    elseif not af.GrindAfterClear then
        reason = "AfterClear ปิด — Grind ทันที"
    else
        reason = getActiveStoryMap() .. " Clear ครบทุก Act"
    end
    return enterGrindMode(reason)
end

-- นับด่านของ Clear Map ที่ยังไม่เคลียร์ (ใช้ตอน AutoNext ในแมตช์ — Settings อาจยังเป็น Act 1)
local function countUnclearedGrindActs()
    if not getAutoFarm().ClearEnabled then
        return 0
    end
    local clearMap = getActiveStoryMap()
    local acts = getStoryActs()
    local diffs = getStoryDifficulties()
    local n = 0
    for _, diff in ipairs(diffs) do
        for _, act in ipairs(acts) do
            if not isActCleared(clearMap, act, diff) then
                n += 1
            end
        end
    end
    return n
end

-- true = อย่า AutoNext (เหลือด่านสุดท้าย / เคลียร์ครบแล้ว → กลับ lobby แล้วเข้า Grind)
local function shouldLockAutoNextForGrind()
    if not getAutoFarm().LoopHardAct1AfterClear then
        return false
    end
    if isInGrindMode() then
        return true
    end
    if not getAutoFarm().ClearEnabled then
        return true
    end
    return countUnclearedGrindActs() <= 1
end

local function returnToLobbyFromMatch()
    local ok = pcall(function()
        local replica = Nodes.GET_GAME_REPLICA:InvokeSelf()
        if replica then
            replica:FireServer("Lobby")
            return true
        end
    end)
    if ok then
        print("[AE Kaitun] ส่งกลับ Lobby (รอเข้า Grind)")
        return true
    end
    ok = pcall(function()
        return Actions.GameReturnLobby(true)
    end)
    return ok == true
end

-- ตั้งด่านถัดไปจาก CompletedMaps (ข้ามด่านที่เคลียร์แล้ว)
local function syncFarmStateFromProgress()
    if not getAutoFarm().Enabled then
        return true
    end

    refreshFarmTargetForLevel()

    -- โหมด Grind / ปิด Clear / AfterClear ปิด → เข้า grind ได้
    if tryEnterGrindAfterMapClear() or isInGrindMode() then
        return true
    end

    local af = getAutoFarm()
    if not af.ClearEnabled then
        -- ไม่มี Clear → ต้องเข้า Grind หรือจบ
        if af.LoopHardAct1AfterClear then
            return enterGrindMode("ไม่มี Clear")
        end
        print("[AE Kaitun] Clear+Grind ปิดทั้งคู่ — ไม่มีด่านให้เล่น")
        return false
    end

    if not af.SkipCleared then
        return true
    end
    local maps = getStoryMaps()
    local acts = getStoryActs()
    local diffs = getStoryDifficulties()
    local st = getFarmState()
    local clearMap = getActiveStoryMap()

    for di, diff in ipairs(diffs) do
        for mi, mapName in ipairs(maps) do
            for ai, actName in ipairs(acts) do
                if not isActCleared(mapName, actName, diff) then
                    -- ถ้าเจอแมพถัดไปหลัง Clear Map เคลียร์ครบแล้ว → เข้า grind แทน
                    if mapName ~= clearMap and isMapFullyCleared(clearMap, acts, diffs) then
                        return enterGrindMode(clearMap .. " ครบแล้ว — ไม่ไปแมพอื่น")
                    end
                    local changed = st.mapIndex ~= mi or st.actIndex ~= ai or st.diffIndex ~= di
                    st.mapIndex = mi
                    st.actIndex = ai
                    st.diffIndex = di
                    if changed then
                        print(("[AE Kaitun] ข้ามด่านที่เคลียร์แล้ว → %s | %s | %s"):format(mapName, actName, diff))
                    end
                    return true
                end
            end
        end
    end

    if tryEnterGrindAfterMapClear() then
        return true
    end

    if af.Loop then
        st.mapIndex = 1
        st.actIndex = 1
        st.diffIndex = 1
        print("[AE Kaitun] เคลียร์ครบแล้ว — Farm Loop เริ่มใหม่จากต้น")
        return true
    end
    print("[AE Kaitun] เคลียร์ครบทุกด่านในลิสต์แล้ว")
    return false
end

local function applyFarmStageToSettings()
    if not getAutoFarm().Enabled then
        return
    end
    local stage, idx, total = getCurrentFarmStage()
    if not stage then
        return
    end
    local q = getQueueSettings()
    q["Gamemode"] = stage.Gamemode
    q["MapName"] = stage.MapName
    q["ActName"] = stage.ActName
    q["Difficulty"] = stage.Difficulty
    if isInGrindMode() then
        print(("[AE Kaitun] Grind → %s | %s | %s (ล็อกด่านนี้วนซ้ำ)"):format(
            stage.MapName, stage.ActName, stage.Difficulty
        ))
    else
        print(("[AE Kaitun] Farm stage %d/%d → %s | %s | %s"):format(
            idx, total, stage.MapName, stage.ActName, stage.Difficulty
        ))
    end
end

-- หลังจบแมตช์กลับ lobby: ไปด่านถัดไปในลิสต์
local function advanceFarmStage()
    if not getAutoFarm().Enabled then
        return false
    end
    refreshFarmTargetForLevel()
    if tryEnterGrindAfterMapClear() or isInGrindMode() then
        return true
    end
    -- ถ้าข้ามด่านเคลียร์ได้ → sync จากเกมตรงๆ (แม่นกว่า +1)
    if getAutoFarm().SkipCleared then
        return syncFarmStateFromProgress()
    end
    local maps = getStoryMaps()
    local acts = getStoryActs()
    local diffs = getStoryDifficulties()
    local st = getFarmState()
    st.actIndex = (st.actIndex or 1) + 1
    if st.actIndex > #acts then
        st.actIndex = 1
        st.mapIndex = (st.mapIndex or 1) + 1
        if st.mapIndex > #maps then
            st.mapIndex = 1
            st.diffIndex = (st.diffIndex or 1) + 1
            if st.diffIndex > #diffs then
                if tryEnterGrindAfterMapClear() then
                    return true
                end
                if getAutoFarm().Loop then
                    st.diffIndex = 1
                    print("[AE Kaitun] ครบทุกแมพ/ด่าน — วนใหม่ (Farm Loop)")
                    return true
                end
                st.diffIndex = #diffs
                st.mapIndex = #maps
                st.actIndex = #acts
                print("[AE Kaitun] ครบทุกแมพ × Act 1-5 แล้ว")
                return false
            end
        end
        -- จบแมพหนึ่งแล้ว ถ้าเป็น Clear Map ปัจจุบัน → เข้า grind
        local finishedMap = maps[st.mapIndex - 1]
        local clearMap = getActiveStoryMap()
        if finishedMap == clearMap and tryEnterGrindAfterMapClear() then
            return true
        end
    end
    return true
end

-- เรียกตอนเข้าแมตช์สำเร็จ / ตอนกลับ lobby (ทนเทเลพอร์ต)
local function markFarmEnteredMatch()
    local st = getFarmState()
    st.inMatch = true
end

local function consumeFarmMatchReturn()
    local st = getFarmState()
    if not st.inMatch then
        -- ยังไม่เคยเข้าแมตช์ — sync ด่านที่ยังไม่เคลียร์
        return syncFarmStateFromProgress()
    end
    st.inMatch = false
    print("[AE Kaitun] กลับจากแมตช์ → หาด่านถัดไปจาก CompletedMaps")
    return advanceFarmStage()
end

local function buildQueueData()
    if getAutoFarm().Enabled then
        applyFarmStageToSettings()
    end
    local qSet = getQueueSettings()
    local gamemode = qSet["Gamemode"] or "Story"
    local q = {
        Gamemode = gamemode,
        MapName = qSet["MapName"],
        Difficulty = qSet["Difficulty"],
    }
    -- Story / Raid / Mastery ต้องมี Act
    if gamemode ~= "Infinite" and gamemode ~= "Tournament" then
        q.ActName = qSet["ActName"]
    end
    return q
end



AutoFarmManager.getFarmState = getFarmState
AutoFarmManager.isInGrindMode = isInGrindMode
AutoFarmManager.getAutoFarm = getAutoFarm
AutoFarmManager.getQueueSettings = getQueueSettings
AutoFarmManager.getActiveStoryMap = getActiveStoryMap
AutoFarmManager.getGrindMap = getGrindMap
AutoFarmManager.getStoryMaps = getStoryMaps
AutoFarmManager.getStoryActs = getStoryActs
AutoFarmManager.getStoryDifficulties = getStoryDifficulties
AutoFarmManager.getGrindStage = getGrindStage
AutoFarmManager.buildStoryStageList = buildStoryStageList
AutoFarmManager.getCurrentFarmStage = getCurrentFarmStage
AutoFarmManager.isActCleared = isActCleared
AutoFarmManager.canEnterGrindMode = canEnterGrindMode
AutoFarmManager.refreshFarmTargetForLevel = refreshFarmTargetForLevel
AutoFarmManager.enterGrindMode = enterGrindMode
AutoFarmManager.tryEnterGrindAfterMapClear = tryEnterGrindAfterMapClear
AutoFarmManager.countUnclearedGrindActs = countUnclearedGrindActs
AutoFarmManager.shouldLockAutoNextForGrind = shouldLockAutoNextForGrind
AutoFarmManager.returnToLobbyFromMatch = returnToLobbyFromMatch
AutoFarmManager.syncFarmStateFromProgress = syncFarmStateFromProgress
AutoFarmManager.applyFarmStageToSettings = applyFarmStageToSettings
AutoFarmManager.advanceFarmStage = advanceFarmStage
AutoFarmManager.markFarmEnteredMatch = markFarmEnteredMatch
AutoFarmManager.consumeFarmMatchReturn = consumeFarmMatchReturn
AutoFarmManager.buildQueueData = buildQueueData

return AutoFarmManager
