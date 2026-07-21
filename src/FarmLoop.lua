--[[
--     AE Kaitun — Main Farm Loop Orchestrator (Optimized for 24/7 AFK)
-- ]]

local FarmLoop = {}

local Replicas = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Replicas.lua") or loadstring(readfile("expidition/src/Replicas.lua"))()
local AutoFarmManager = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/AutoFarmManager.lua") or loadstring(readfile("expidition/src/AutoFarmManager.lua"))()
local Lobby = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Lobby.lua") or loadstring(readfile("expidition/src/Lobby.lua"))()
local InGame = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/InGame.lua") or loadstring(readfile("expidition/src/InGame.lua"))()
local SmartPlay = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/SmartPlay.lua") or loadstring(readfile("expidition/src/SmartPlay.lua"))()

local isInGame = Replicas.isInGame
local getAccountLevel = Replicas.getAccountLevel
local getAutoFarm = AutoFarmManager.getAutoFarm
local getGrindStage = AutoFarmManager.getGrindStage
local getActiveStoryMap = AutoFarmManager.getActiveStoryMap
local refreshFarmTargetForLevel = AutoFarmManager.refreshFarmTargetForLevel
local buildStoryStageList = AutoFarmManager.buildStoryStageList
local isInGrindMode = AutoFarmManager.isInGrindMode
local syncFarmStateFromProgress = AutoFarmManager.syncFarmStateFromProgress
local applyFarmStageToSettings = AutoFarmManager.applyFarmStageToSettings
local getCurrentFarmStage = AutoFarmManager.getCurrentFarmStage
local markFarmEnteredMatch = AutoFarmManager.markFarmEnteredMatch
local consumeFarmMatchReturn = AutoFarmManager.consumeFarmMatchReturn
local getFarmState = AutoFarmManager.getFarmState
local getStoryMaps = AutoFarmManager.getStoryMaps
local getStoryActs = AutoFarmManager.getStoryActs
local getStoryDifficulties = AutoFarmManager.getStoryDifficulties
local tryEnterGrindAfterMapClear = AutoFarmManager.tryEnterGrindAfterMapClear
local startGame = Lobby.startGame
local runInGame = InGame.runInGame

local function waitUntilInGame(timeout)
    timeout = timeout or 90
    local t0 = os.clock()
    while os.clock() - t0 < timeout do
        if isInGame() then
            return true
        end
        task.wait(0.5)
    end
    return false
end

local function waitUntilBackToLobby(timeout)
    timeout = timeout or 1800
    local t0 = os.clock()
    while os.clock() - t0 < 120 and not isInGame() do
        task.wait(0.5)
    end
    if not isInGame() then
        return false
    end
    while os.clock() - t0 < timeout do
        if not isInGame() then
            return true
        end
        task.wait(1)
    end
    return not isInGame()
end

local function runStoryFarmLoop()
    if not getAutoFarm().Enabled then
        startGame()
        if waitUntilInGame(90) then
            runInGame()
        end
        return
    end

    if not isInGame() then
        if not consumeFarmMatchReturn() then
            print("[AE Kaitun] Farm All Story เสร็จแล้ว")
            return
        end
    else
        syncFarmStateFromProgress()
    end

    print("[AE Kaitun] Farm All Story — Clear ตามเลเวล / Grind หลังครบ")
    -- หลัง teleport soft-reset flag ค้างใน getgenv → รัน SmartPlay ก่อนคิวด่านแรก
    pcall(function()
        SmartPlay.consumeIfNeeded("farm-loop-start")
    end)
    -- กัน grind ค้างจากบั๊กรอบก่อน (School Act1 Hard วน)
    pcall(function()
        local st = getFarmState()
        if st.grindMode and not AutoFarmManager.canEnterGrindMode() then
            st.grindMode = false
            print("[AE Kaitun] เคลียร์ grindMode ค้าง — กลับไป Clear Story ต่อ")
        end
        if AutoFarmManager.debugProgressSnapshot then
            AutoFarmManager.debugProgressSnapshot("loop-start")
        end
    end)
    refreshFarmTargetForLevel()
    do
        local af = getAutoFarm()
        local g = getGrindStage()
        if af.ClearEnabled then
            print(("[AE Kaitun] Lv %d → Clear %s | Acts Normal | Grind หลังครบ = %s"):format(
                getAccountLevel(), getActiveStoryMap(),
                af.LoopHardAct1AfterClear and "เปิด" or "ปิด"
            ))
        else
            print("[AE Kaitun] Clear ปิด — ข้ามไป Grind (ถ้าเปิด)")
        end
        if af.LoopHardAct1AfterClear then
            print(("[AE Kaitun] Grind เป้า → %s | %s | %s (AfterClear=%s)"):format(
                g.MapName, g.ActName, g.Difficulty,
                tostring(af.GrindAfterClear)
            ))
        end
    end
    local safety = 0
    local maxStages = #buildStoryStageList() + 5

    while true do
        safety += 1
        if not isInGrindMode() and safety > maxStages then
            print("[AE Kaitun] Farm All Story ครบลิสต์แล้ว")
            break
        end
        if isInGrindMode() and safety > 9999 then
            warn("[AE Kaitun] Grind หยุดที่เพดานรอบ — รีสตาร์ทสคริปต์เพื่อวนต่อ")
            break
        end

        if not syncFarmStateFromProgress() then
            print("[AE Kaitun] Farm All Story เสร็จแล้ว")
            break
        end
        applyFarmStageToSettings()
        if isInGrindMode() then
            print(("[AE Kaitun] === Grind round %d ==="):format(safety))
        else
            local _, idx, total = getCurrentFarmStage()
            print(("[AE Kaitun] === เริ่มด่าน %d/%d ==="):format(idx or safety, total or maxStages))
        end

        if isInGame() then
            markFarmEnteredMatch()
            runInGame()
        else
            startGame()
            if waitUntilInGame(90) then
                markFarmEnteredMatch()
                runInGame()
            else
                warn("[AE Kaitun] เข้าแมตช์ไม่สำเร็จ — บังคับขยับด่านถัดไป")
                getFarmState().inMatch = false
                if isInGrindMode() then
                    task.wait(2)
                    continue
                end
                local st = getFarmState()
                local maps = getStoryMaps()
                local acts = getStoryActs()
                local diffs = getStoryDifficulties()
                st.actIndex = (st.actIndex or 1) + 1
                if st.actIndex > #acts then
                    st.actIndex = 1
                    st.mapIndex = (st.mapIndex or 1) + 1
                    if st.mapIndex > #maps then
                        st.mapIndex = 1
                        st.diffIndex = (st.diffIndex or 1) + 1
                        if st.diffIndex > #diffs then
                            if tryEnterGrindAfterMapClear() then
                                task.wait(2)
                                continue
                            end
                            break
                        end
                    end
                end
                task.wait(2)
                continue
            end
        end

        print("[AE Kaitun] รอจบแมตช์แล้วกลับ lobby...")
        local back = waitUntilBackToLobby(1800)
        task.wait(2)

        if back or not isInGame() then
            -- Soft-reset / แพ้ติด → SmartPlay ก่อนคิวใหม่
            pcall(function()
                SmartPlay.consumeIfNeeded("lobby-return")
            end)
            if not consumeFarmMatchReturn() then
                print("[AE Kaitun] Farm All Story เสร็จแล้ว")
                break
            end
        end

        applyFarmStageToSettings()
        task.wait(1.5)
    end
end

FarmLoop.waitUntilInGame = waitUntilInGame
FarmLoop.waitUntilBackToLobby = waitUntilBackToLobby
FarmLoop.runStoryFarmLoop = runStoryFarmLoop

return FarmLoop
