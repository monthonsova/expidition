-- --     AE Kaitun — Starter Unit Module

local StarterUnit = {}
local Core = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Core.lua") or loadstring(readfile("expidition/src/Core.lua"))()
local Replicas = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Replicas.lua") or loadstring(readfile("expidition/src/Replicas.lua"))()

local Nodes = Core.Nodes
local LocalPlayer = Core.LocalPlayer
local getPlayerData = Replicas.getPlayerData

local starterHooked = false
local starterDone = false

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

-- server ส่งลิสต์ starter ที่ให้เลือกมาใน prompt — อาจเป็น array ของ string หรือ table {Asset=...}
local function extractAssets(offered)
    local assets = {}
    if typeof(offered) ~= "table" then
        return assets
    end
    for _, v in pairs(offered) do
        if typeof(v) == "string" then
            assets[#assets + 1] = v
        elseif typeof(v) == "table" then
            local a = v.Asset or v.Unit or v.Name
            if typeof(a) == "string" then
                assets[#assets + 1] = a
            end
        end
    end
    return assets
end

-- เลือก starter: ยึด config ก่อน ถ้าไม่อยู่ในลิสต์ที่เสนอ → เอาตัวแรกที่ server เสนอ
local function pickStarter(offered)
    local want = _G.Settings["Starter Unit"] or "Goku"
    local assets = extractAssets(offered)
    if #assets == 0 then
        return want
    end
    for _, a in ipairs(assets) do
        if a == want then
            return a
        end
    end
    print("[AE Kaitun] Starter", want, "ไม่อยู่ในลิสต์ที่เสนอ — ใช้", assets[1],
        "แทน (เสนอ:", table.concat(assets, ", "), ")")
    return assets[1]
end

local function fireChoose(asset)
    print("[AE Kaitun] เลือก Starter =", asset)
    pcall(function()
        Nodes.CHOOSE_STARTER_UNIT:FireServer(asset)
    end)
end

-- ฟัง prompt จาก server (มาพร้อมลิสต์จริง) — วิธีหลัก ทนทานสุด
-- hook ตั้งแต่ตอน require กัน signal ยิงมาก่อน char โหลด
local function setupStarterListener()
    if starterHooked then
        return
    end
    if _G.Settings["Auto Choose Starter"] == false then
        return
    end
    if not (Nodes and Nodes.PROMPT_CHOOSE_STARTER_UNIT) then
        return
    end
    starterHooked = true
    pcall(function()
        Nodes.PROMPT_CHOOSE_STARTER_UNIT:Connect(function(offered)
            if starterDone or hasAnyUnit() then
                return
            end
            print("[AE Kaitun] ได้ prompt เลือก Starter จาก server")
            fireChoose(pickStarter(offered))
        end)
    end)
    pcall(function()
        if Nodes.STARTER_UNIT_CHOSEN then
            Nodes.STARTER_UNIT_CHOSEN:Connect(function()
                starterDone = true
                print("[AE Kaitun] Starter unit ได้แล้ว ✔")
            end)
        end
    end)
end

local function waitCharacterLoaded(timeout)
    timeout = timeout or 20
    if not LocalPlayer then
        return false
    end
    local t0 = os.clock()
    while os.clock() - t0 < timeout do
        local char = LocalPlayer.Character
        if char and char:GetAttribute("Loaded") then
            return true
        end
        task.wait(0.3)
    end
    return LocalPlayer.Character ~= nil
end

local function chooseStarterUnit()
    if _G.Settings["Auto Choose Starter"] == false then
        return
    end

    -- hook prompt ให้ชัวร์ (เผื่อ setup ตอน require ไม่ทัน/ถูกข้าม)
    setupStarterListener()

    -- มียูนิตอยู่แล้ว = เลือก starter ไปแล้ว (บัญชีเก่า)
    if hasAnyUnit() then
        print("[AE Kaitun] มียูนิตแล้ว — ข้าม Starter")
        starterDone = true
        return
    end

    -- server เปิด prompt หลัง character โหลดเสร็จ (เกมเช็ค attribute "Loaded")
    print("[AE Kaitun] ไอดีใหม่ยังไม่มียูนิต — รอ character โหลด + prompt เลือก Starter")
    waitCharacterLoaded(20)

    -- fallback เชิงรุก: เผื่อ prompt ยิงไปก่อนเรา hook (พลาด signal)
    -- ยิงค่า config แล้ววนเช็คว่าได้ยูนิตยัง — listener จะจัดการเคสลิสต์จริงเอง
    local want = _G.Settings["Starter Unit"] or "Goku"
    local t0 = os.clock()
    local fired = 0
    while os.clock() - t0 < 30 do
        if starterDone or hasAnyUnit() then
            print("[AE Kaitun] Starter สำเร็จ ✔")
            starterDone = true
            return
        end
        if fired < 6 then
            fireChoose(want)
            fired += 1
        end
        task.wait(2)
    end

    if not hasAnyUnit() then
        warn("[AE Kaitun] ยังไม่ได้ Starter unit — server อาจยังไม่เปิด prompt หรือ asset '"
            .. tostring(want) .. "' ไม่ถูกเสนอ (ลองเปลี่ยน Settings['Starter Unit'])")
    end
end

-- hook ทันทีตอน require — จับ prompt แม้จะยิงมาก่อน main thread เรียก chooseStarterUnit
pcall(setupStarterListener)

StarterUnit.hasAnyUnit = hasAnyUnit
StarterUnit.chooseStarterUnit = chooseStarterUnit
StarterUnit.setupStarterListener = setupStarterListener

return StarterUnit
