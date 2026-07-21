-- [[
--     AE Kaitun — Starter Unit Module
-- ]]

local StarterUnit = {}
local Replicas = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Replicas.lua") or loadstring(readfile("expidition/src/Replicas.lua"))()

local function hasAnyUnit()
    local data = getPlayerData()
    if not data then
        return false
    end
    local unitData = data.UnitData
    if typeof(unitData) ~= "table" then
        return false
    end
    return next(unitData) ~= nil
end

local function chooseStarterUnit()
    if not _G.Settings["Auto Choose Starter"] then
        return
    end

    -- มียูนิตอยู่แล้ว = เลือก starter ไปแล้ว
    if hasAnyUnit() then
        print("[AE Kaitun] มียูนิตแล้ว — ข้าม Starter")
        return
    end

    local asset = _G.Settings["Starter Unit"] or "Goku"
    print("[AE Kaitun] เลือก Starter =", asset, "(UI: Carrot ถ้าเป็น Goku)")
    pcall(function()
        Nodes.CHOOSE_STARTER_UNIT:FireServer(asset)
    end)
    task.wait(1.5)
end



StarterUnit.hasAnyUnit = hasAnyUnit
StarterUnit.chooseStarterUnit = chooseStarterUnit

return StarterUnit
