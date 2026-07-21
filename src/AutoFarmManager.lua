--[[
--     AE Kaitun — Auto Farm Progression Module
-- ]]

local AutoFarmManager = {}

local Core = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Core.lua") or loadstring(readfile("expidition/src/Core.lua"))()
local Replicas = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Replicas.lua") or loadstring(readfile("expidition/src/Replicas.lua"))()

local Nodes = Core.Nodes
local Dependencies = Core.Dependencies
local Actions = Core.Actions
local peek = Core.peek

local getAccountLevel = Replicas.getAccountLevel

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
            -- ผลแมตช์ล่าสุด / สถิติแพ้ (ใช้ตอน Defeat → Retry ด่านเดิม ไม่ขยับคิว)
            lastVictory = nil,
            failStreak = 0,
            needSmartPlay = false,
            smartPlayAt = 0,
            totalFails = 0,
            totalWins = 0,
            endScreenAt = 0,
        }
    end
    local st = g.AE_FarmState
    if st.failStreak == nil then
        st.failStreak = 0
    end
    if st.needSmartPlay == nil then
        st.needSmartPlay = false
    end
    if st.totalFails == nil then
        st.totalFails = 0
    end
    if st.totalWins == nil then
        st.totalWins = 0
    end
    return st
end

-- บันทึกผลจาก SHOW_END_SCREEN (Victory=true/false)
local function markMatchResult(victory)
    local st = getFarmState()
    st.lastVictory = victory == true
    st.endScreenAt = os.clock()
    if victory then
        st.failStreak = 0
        st.totalWins = (st.totalWins or 0) + 1
    else
        st.failStreak = (st.failStreak or 0) + 1
        st.totalFails = (st.totalFails or 0) + 1
    end
    return st
end

-- Restart ด่านเดิมโดยไม่ผ่าน confirmation prompt (Actions.GameRestart ต้องส่ง true)
local function restartCurrentMatch(reason)
    local ok = pcall(function()
        local replica = Nodes.GET_GAME_REPLICA:InvokeSelf()
        if replica then
            replica:FireServer("Restart")
            return true
        end
    end)
    if ok then
        print("[AE Kaitun] Restart ด่านเดิม", reason and ("| " .. tostring(reason)) or "")
        return true
    end
    ok = pcall(function()
        if Actions and Actions.GameRestart then
            return Actions.GameRestart(true)
        end
    end)
    return ok == true
end

-- Next stage (เฉพาะตอนชนะ + มีด่านถัดไป) — fallback ถ้า AutoNext ของเกมไม่ยิง
local function nextStageFromMatch(reason)
    local ok = pcall(function()
        local replica = Nodes.GET_GAME_REPLICA:InvokeSelf()
        if replica then
            replica:FireServer("Next")
            return true
        end
    end)
    if ok then
        print("[AE Kaitun] Next stage", reason and ("| " .. tostring(reason)) or "")
        return true
    end
    ok = pcall(function()
        if Actions and Actions.GameNext then
            return Actions.GameNext()
        end
    end)
    return ok == true
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
            { MinLevel = 1,  Map = "SchoolGrounds" },
            { MinLevel = 15, Map = "FlowerForest" },
            { MinLevel = 30, Map = "Dressrosa" },
            { MinLevel = 45, Map = "FairyKingForest" },
            { MinLevel = 60, Map = "KingsTomb" },
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
        if grindMap == "" or grindMap == "nil" or grindMap == "auto" then
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
            or { "SchoolGrounds", "FlowerForest", "Dressrosa", "FairyKingForest", "KingsTomb" },
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

-- forward declare
local isMapFullyCleared
local isActCleared

local DEFAULT_STORY_MAPS = {
    "SchoolGrounds",
    "FlowerForest",
    "Dressrosa",
    "FairyKingForest",
    "KingsTomb",
}

-- ดึงค่า nested จาก PlayerData แบบทน Fusion state ซ้อน
local function deepPeekValue(v)
    if v == nil then
        return nil
    end
    if typeof(v) == "table" then
        return v
    end
    local ok, peeked = pcall(peek, v)
    if ok then
        return peeked
    end
    return v
end

local function getCompletedMapsRoot()
    local data = deepPeekValue(peek(Dependencies.PlayerData))
    if typeof(data) ~= "table" then
        return nil
    end
    return deepPeekValue(data.CompletedMaps)
end

local function getStoryCompletedMaps()
    local cm = getCompletedMapsRoot()
    if typeof(cm) ~= "table" then
        return nil
    end
    local story = deepPeekValue(cm.Story)
    if typeof(story) == "table" then
        return story
    end
    -- บางที่ส่ง CompletedMaps.Story มาตรงๆ
    if cm.SchoolGrounds or cm.FlowerForest then
        return cm
    end
    return story
end

-- ลำดับแมพ Story จากเกม (ProgressionIndex) หรือ Config.Maps
local function getOrderedStoryMapList()
    local af = getAutoFarm()
    local ordered = nil
    pcall(function()
        local Maps = Dependencies.Information and Dependencies.Information.Maps
        if Maps and typeof(Maps.GetOrderedMaps) == "function" then
            ordered = Maps:GetOrderedMaps("Story")
        end
    end)
    if typeof(ordered) == "table" and #ordered > 0 then
        local want = {}
        for _, m in ipairs(af.Maps) do
            want[tostring(m)] = true
        end
        local filtered = {}
        for _, m in ipairs(ordered) do
            if want[tostring(m)] then
                table.insert(filtered, tostring(m))
            end
        end
        if #filtered > 0 then
            return filtered
        end
        return ordered
    end
    if typeof(af.Maps) == "table" and #af.Maps > 0 then
        return af.Maps
    end
    return DEFAULT_STORY_MAPS
end

-- CompletedMaps.Story.SchoolGrounds["Act 1"].Normal = { ClearCount = ... }
-- เกม HasMapUnlocked เช็คแค่มี key ของ Act (ไม่บังคับ Difficulty)
isActCleared = function(mapName, actName, difficulty)
    mapName = tostring(mapName)
    actName = tostring(actName)

    -- ทางเกม: HasMapCompleted เช็ค path มีจริง
    local cmRoot = getCompletedMapsRoot()
    if typeof(cmRoot) == "table" then
        local Maps = Dependencies.Information and Dependencies.Information.Maps
        if Maps and typeof(Maps.HasMapCompleted) == "function" then
            if difficulty then
                local okDiff, clearedDiff = pcall(function()
                    return Maps:HasMapCompleted(cmRoot, "Story", mapName, actName, tostring(difficulty))
                end)
                if okDiff and clearedDiff == true then
                    return true
                end
            end
            -- fallback: มี Act ใน CompletedMaps = เคลียร์แล้ว (ตรงกับ HasMapUnlocked ของเกม)
            local okAct, clearedAct = pcall(function()
                return Maps:HasMapCompleted(cmRoot, "Story", mapName, actName)
            end)
            if okAct and clearedAct == true then
                return true
            end
        end
    end

    local story = getStoryCompletedMaps()
    if typeof(story) ~= "table" then
        return false
    end
    local mapT = deepPeekValue(story[mapName])
    if typeof(mapT) ~= "table" then
        return false
    end
    local actT = deepPeekValue(mapT[actName])
    if actT == nil then
        return false
    end
    if actT == true then
        return true
    end
    if typeof(actT) ~= "table" then
        return false
    end

    if difficulty then
        local diffT = deepPeekValue(actT[difficulty])
        if diffT == true then
            return true
        end
        if typeof(diffT) == "table" then
            return (tonumber(diffT.ClearCount) or 0) > 0 or diffT.Cleared == true
        end
        -- รูปแบบเก่า: มี act แล้วถือว่าเคลียร์ (เกม HasMapUnlocked ใช้แบบนี้)
        if typeof(actT.ClearCount) == "number" then
            return actT.ClearCount > 0
        end
        -- ถ้ามี key ความยากอื่นหรือข้อมูลใน act → ถือว่าเคยเคลียร์ act นี้แล้ว
        for k, v in pairs(actT) do
            if k == "Normal" or k == "Hard" or k == "Nightmare" or k == "ClearCount" or k == "FastestTime" then
                if v == true then
                    return true
                end
                if typeof(v) == "table" and ((tonumber(v.ClearCount) or 0) > 0 or v.Cleared == true) then
                    return true
                end
                if typeof(v) == "number" and v > 0 then
                    return true
                end
            end
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
        if typeof(v) == "table" and ((tonumber(v.ClearCount) or 0) > 0 or v.Cleared == true) then
            return true
        end
    end
    return false
end

isMapFullyCleared = function(mapName, acts, diffs)
    acts = acts or getAutoFarm().Acts
    diffs = diffs or getAutoFarm().Difficulties
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

-- ปลดแมพ: progression ของเกม (แมพก่อนหน้าเคลียร์) — ไม่ล็อกด้วย MinLevel
-- MinLevel เป็นแค่ log/advice ไม่กันเล่นแมพถัดไป (บั๊กเดิม: School ครบ → Grind Act1 เพราะ Lv < 15)
local function isStoryMapUnlocked(mapName)
    mapName = tostring(mapName)
    local cm = getCompletedMapsRoot()

    local unlocked = nil
    pcall(function()
        local Maps = Dependencies.Information and Dependencies.Information.Maps
        if Maps and typeof(Maps.HasMapUnlocked) == "function" and typeof(cm) == "table" then
            unlocked = Maps:HasMapUnlocked(cm, "Story", mapName)
        end
    end)
    if unlocked == true then
        return true
    end

    local ordered = getOrderedStoryMapList()
    local idx = nil
    for i, m in ipairs(ordered) do
        if tostring(m) == mapName then
            idx = i
            break
        end
    end
    if not idx then
        return false
    end
    if idx == 1 then
        return true
    end
    return isMapFullyCleared(ordered[idx - 1])
end

-- แมพ Clear เป้าหมาย: ตัวแรกที่ปลดแล้วแต่ยังไม่เคลียร์ครบ
local function getActiveStoryMap()
    local ordered = getOrderedStoryMapList()
    local lastUnlocked = ordered[1] or "SchoolGrounds"
    for _, map in ipairs(ordered) do
        if isStoryMapUnlocked(map) then
            lastUnlocked = map
            if not isMapFullyCleared(map) then
                return map
            end
        end
    end
    return lastUnlocked
end

-- แมพ Grind: ตั้งเองได้ — ว่าง = แมพสุดท้ายในลิสต์ที่เคลียร์แล้ว / active
local function getGrindMap()
    local af = getAutoFarm()
    if af.GrindMap and tostring(af.GrindMap) ~= "" then
        return af.GrindMap
    end
    local ordered = getOrderedStoryMapList()
    for i = #ordered, 1, -1 do
        if isMapFullyCleared(ordered[i]) then
            return ordered[i]
        end
    end
    return getActiveStoryMap()
end

-- ลิสต์แมพ Clear: เฉพาะแมพเป้าปัจจุบัน (ตัวแรกที่ยังไม่เคลียร์)
-- อย่าใส่ทุกแมพที่ปลดแล้ว — กัน index ชี้ School Act1 หลังเคลียร์ School ครบ
local function getStoryMaps()
    local af = getAutoFarm()
    if not af.ClearEnabled then
        return {}
    end
    local active = getActiveStoryMap()
    if active and not isMapFullyCleared(active) then
        return { active }
    end
    local list = {}
    for _, map in ipairs(getOrderedStoryMapList()) do
        if isStoryMapUnlocked(map) and not isMapFullyCleared(map) then
            table.insert(list, map)
        end
    end
    if #list == 0 then
        table.insert(list, active or "SchoolGrounds")
    end
    return list
end

local function getStoryActs()
    return getAutoFarm().Acts
end

local function getStoryDifficulties()
    return getAutoFarm().Difficulties
end

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

-- เคลียร์ครบทั้งลิสต์ Story ที่ตั้งไว้ (ไม่ใช่แค่แมพที่ปลดแล้ว) — กันเข้า Grind กลางทาง
local function areAllConfiguredStoryMapsCleared()
    local maps = getOrderedStoryMapList()
    if #maps == 0 then
        return true
    end
    for _, map in ipairs(maps) do
        if not isMapFullyCleared(map) then
            return false
        end
    end
    return true
end

local function areAllUnlockedStoryMapsCleared()
    return areAllConfiguredStoryMapsCleared()
end

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
    -- สำคัญ: ต้องเคลียร์ครบทุกแมพในลิสต์ (School→…→KingsTomb) ก่อน Grind
    return areAllConfiguredStoryMapsCleared()
end

local function debugProgressSnapshot(tag)
    local maps = getOrderedStoryMapList()
    local parts = {}
    for _, map in ipairs(maps) do
        local unlocked = isStoryMapUnlocked(map)
        local cleared = isMapFullyCleared(map)
        local actBits = {}
        for _, act in ipairs(getStoryActs()) do
            local ok = isActCleared(map, act, "Normal")
            table.insert(actBits, ok and "✓" or "·")
        end
        table.insert(parts, string.format("%s[%s%s]%s", map,
            unlocked and "U" or "-",
            cleared and "C" or "-",
            table.concat(actBits, "")))
    end
    print(("[AE Kaitun] Progress%s: %s | grind=%s"):format(
        tag and (" " .. tostring(tag)) or "",
        table.concat(parts, " | "),
        tostring(isInGrindMode())
    ))
end

local function refreshFarmTargetForLevel()
    local af = getAutoFarm()
    if not af.ClearEnabled then
        if af.LoopHardAct1AfterClear then
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

    -- ยังมี Story ให้เคลียร์ → ห้ามค้าง Grind (บั๊กเดิม: School ครบ → Grind School Act1)
    if st.grindMode and af.GrindAfterClear and not areAllConfiguredStoryMapsCleared() then
        st.grindMode = false
        st.needProgressSettings = true
        changed = true
        print(("[AE Kaitun] ออก Grind — ยังมี Story ให้เคลียร์ เป้า=%s"):format(map))
    end

    if st.activeMap ~= map then
        st.activeMap = map
        if not areAllConfiguredStoryMapsCleared() then
            st.grindMode = false
        end
        -- sync index ไปแมพใหม่ — act จะถูก syncFarm ตั้งจาก CompletedMaps
        st.mapIndex = 1
        st.actIndex = 1
        st.diffIndex = 1
        st.needProgressSettings = true
        changed = true
        if prev ~= nil then
            print(("[AE Kaitun] เป้า Clear เปลี่ยน %s → %s (Lv %d)"):format(
                tostring(prev), map, getAccountLevel()
            ))
        else
            print(("[AE Kaitun] แมพ Clear ปัจจุบัน = %s (Lv %d)"):format(map, getAccountLevel()))
        end
        debugProgressSnapshot("refresh")
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
    st.needProgressSettings = true
    local g = getGrindStage()
    print(("[AE Kaitun] Grind mode — ล็อก %s | %s | %s (Story เคลียร์ครบทุกแมพ)%s"):format(
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
        -- กันค้าง grind ผิดตอนยังมีแมพให้เคลียร์
        if not canEnterGrindMode() then
            getFarmState().grindMode = false
            return false
        end
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
        reason = ("Story เคลียร์ครบ %d แมพ"):format(#getOrderedStoryMapList())
    end
    return enterGrindMode(reason)
end

-- นับด่านที่ยังไม่เคลียร์ทั้งลิสต์ Story ที่ตั้งไว้
local function countUnclearedGrindActs()
    if not getAutoFarm().ClearEnabled then
        return 0
    end
    local maps = getOrderedStoryMapList()
    local acts = getStoryActs()
    local diffs = getStoryDifficulties()
    local n = 0
    for _, mapName in ipairs(maps) do
        for _, diff in ipairs(diffs) do
            for _, act in ipairs(acts) do
                if not isActCleared(mapName, act, diff) then
                    n += 1
                end
            end
        end
    end
    return n
end

-- กำลังเล่น Act สุดท้ายของแมพปัจจุบัน (เช่น School Act 5) → ต้องกลับ lobby คิวแมพถัดไป
local function isPlayingLastActOfActiveMap()
    if isInGrindMode() then
        return false
    end
    if not getAutoFarm().ClearEnabled then
        return false
    end
    local stage = select(1, getCurrentFarmStage())
    if typeof(stage) ~= "table" or not stage.MapName then
        return false
    end
    local acts = getStoryActs()
    if #acts == 0 then
        return false
    end
    local lastAct = acts[#acts]
    if tostring(stage.ActName) ~= tostring(lastAct) then
        return false
    end
    local diff = stage.Difficulty or "Normal"
    for i = 1, #acts - 1 do
        if not isActCleared(stage.MapName, acts[i], diff) then
            return false
        end
    end
    return true
end

-- ล็อก AutoNext เมื่อ: Grind / ด่านสุดท้ายทั้งลิสต์ / Act สุดท้ายของแมพ (กันวน School Act1)
local function shouldLockAutoNextForGrind()
    if isInGrindMode() then
        return getAutoFarm().LoopHardAct1AfterClear and canEnterGrindMode()
    end
    if not getAutoFarm().ClearEnabled then
        return getAutoFarm().LoopHardAct1AfterClear == true
    end
    if isPlayingLastActOfActiveMap() then
        return true
    end
    if not getAutoFarm().LoopHardAct1AfterClear then
        return false
    end
    return countUnclearedGrindActs() <= 1
end

local function returnToLobbyFromMatch(reason)
    local ok = pcall(function()
        local replica = Nodes.GET_GAME_REPLICA:InvokeSelf()
        if replica then
            replica:FireServer("Lobby")
            return true
        end
    end)
    if ok then
        print("[AE Kaitun] ส่งกลับ Lobby", reason and ("| " .. tostring(reason)) or "")
        return true
    end
    warn("[AE Kaitun] กลับ Lobby ไม่สำเร็จ — ไม่มี GameReplica")
    return false
end

local function syncFarmStateFromProgress()
    if not getAutoFarm().Enabled then
        return true
    end

    refreshFarmTargetForLevel()

    if tryEnterGrindAfterMapClear() or isInGrindMode() then
        return true
    end

    local af = getAutoFarm()
    if not af.ClearEnabled then
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

    -- ถ้า CompletedMaps ยังไม่ sync → อย่า reset ไป Act 1 ผิด
    local story = getStoryCompletedMaps()
    if typeof(story) ~= "table" then
        warn("[AE Kaitun] CompletedMaps ยังไม่พร้อม — คงคิวเดิม รอ sync")
        debugProgressSnapshot("no-cm")
        return true
    end

    for di, diff in ipairs(diffs) do
        for mi, mapName in ipairs(maps) do
            for ai, actName in ipairs(acts) do
                if not isActCleared(mapName, actName, diff) then
                    local changed = st.mapIndex ~= mi or st.actIndex ~= ai or st.diffIndex ~= di
                    st.mapIndex = mi
                    st.actIndex = ai
                    st.diffIndex = di
                    st.activeMap = mapName
                    if changed then
                        print(("[AE Kaitun] คิว Clear → %s | %s | %s"):format(mapName, actName, diff))
                    end
                    return true
                end
            end
        end
    end

    -- แมพที่ปลดแล้วเคลียร์ครบ แต่ยังมีแมพถัดไปในลิสต์ที่ยังปลดไม่ได้? (ไม่ควรเกิดถ้า unlock=progression)
    local ordered = getOrderedStoryMapList()
    for _, mapName in ipairs(ordered) do
        if not isMapFullyCleared(mapName) then
            if isStoryMapUnlocked(mapName) then
                -- ควรเจอในลูปบนแล้ว
            else
                print(("[AE Kaitun] แมพ %s ยังไม่ปลด — รอ progression (ไม่เข้า Grind)"):format(mapName))
                debugProgressSnapshot("wait-unlock")
                return true
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
    debugProgressSnapshot("done")
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
    -- สำคัญ: ไม่ขยับคิวตาม "เคยเข้าแมตช์" — ใช้ CompletedMaps เท่านั้น
    -- ถ้าแพ้ (lastVictory=false) ด่านเดิมยังไม่เคลียร์ → sync จะชี้ด่านเดิม → เข้าใหม่
    if st.lastVictory == false then
        print(("[AE Kaitun] กลับจากแมตช์หลังแพ้ (failStreak=%d) → คิวอยู่ด่านเดิม (CompletedMaps)"):format(
            tonumber(st.failStreak) or 0
        ))
    else
        print("[AE Kaitun] กลับจากแมตช์ → หาด่านถัดไปจาก CompletedMaps")
    end
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
AutoFarmManager.getOrderedStoryMapList = getOrderedStoryMapList
AutoFarmManager.isStoryMapUnlocked = isStoryMapUnlocked
AutoFarmManager.areAllUnlockedStoryMapsCleared = areAllUnlockedStoryMapsCleared
AutoFarmManager.areAllConfiguredStoryMapsCleared = areAllConfiguredStoryMapsCleared
AutoFarmManager.debugProgressSnapshot = debugProgressSnapshot
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
AutoFarmManager.markMatchResult = markMatchResult
AutoFarmManager.restartCurrentMatch = restartCurrentMatch
AutoFarmManager.nextStageFromMatch = nextStageFromMatch

return AutoFarmManager
