-- --     AE Kaitun — Quests & Rewards Module

local Rewards = {}

local Core = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Core.lua") or loadstring(readfile("expidition/src/Core.lua"))()
local Replicas = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Replicas.lua") or loadstring(readfile("expidition/src/Replicas.lua"))()

local Nodes = Core.Nodes
local Dependencies = Core.Dependencies
local Actions = Core.Actions
local peek = Core.peek

local isInGame = Replicas.isInGame
local getPlayerData = Replicas.getPlayerData

-- รายชื่อยืนยันตรงกับ ModuleScript จริงในเกม (Achievement_Collector/Story/Raid/Secret/Expeditions)
-- เดิมพยายามสแกน children แบบไดนามิกจาก Shared.Information.Quests แต่ path นั้นชี้ผิด (Shared คือโฟลเดอร์
-- ReplicatedStorage.Shared ไม่ใช่ FusionPackage.Shared ที่มี state จริง) และ Information ต้อง require() ก่อนใช้
-- อยู่แล้ว — ใช้ลิสต์ที่ยืนยันแล้วตรงๆ ชัดเจนกว่าและไม่มีจุดพัง
local function getAchievementCategories()
    return {
        "Achievement_Collector",
        "Achievement_Story",
        "Achievement_Raid",
        "Achievement_Secret",
        "Achievement_Expeditions",
    }
end

local function claimAllRewards()
    if not _G.Settings["Auto Claim Rewards"] then
        return
    end
    if isInGame() then
        print("[AE Kaitun] อยู่ในแมตช์ — ข้าม Claim (ทำที่ lobby)")
        return
    end

    print("[AE Kaitun] Claim All Quests + Achievements + Level Milestones + Calendar...")

    -- Quests แท็บ All
    pcall(function()
        Nodes.QUEST_CLAIM_ALL:FireServer()
    end)
    task.wait(0.55)

    -- Quests รายหมวด
    for _, cat in ipairs({ "Daily", "Weekly", "Unit", "All" }) do
        pcall(function()
            Nodes.QUEST_CLAIM_ALL_CATEGORY:FireServer(cat)
        end)
        task.wait(0.35)
    end
    pcall(function()
        Nodes.QUEST_CLAIM_ALL_CATEGORIES:FireServer({ "Daily", "Weekly", "Unit" })
    end)
    task.wait(0.45)

    -- Achievements ทุกหมวด (Claim All ต่อหมวด + ของขวัญหมวด)
    for _, cat in ipairs(getAchievementCategories()) do
        print("[AE Kaitun] Claim achievement:", cat)
        pcall(function()
            Nodes.QUEST_CLAIM_ALL_CATEGORY:FireServer(cat)
        end)
        task.wait(0.3)
        pcall(function()
            Nodes.QUEST_CLAIM_CATEGORY:FireServer(cat)
        end)
        task.wait(0.3)
    end

    -- Level Milestones (Claim All = FireServer ไม่ส่ง level)
    print("[AE Kaitun] Claim Level Milestones...")
    pcall(function()
        Nodes.CLAIM_LEVEL_MILESTONE:FireServer()
    end)
    task.wait(0.45)
    -- เผื่อเซิร์ฟอยากได้ทีละเลเวล: เคลมทุก 5 ที่ปลดแล้ว
    local playerLevel = 1
    pcall(function()
        local data = peek(Dependencies.PlayerData) or getPlayerData()
        playerLevel = tonumber(data and data.Level) or 1
    end)
    for lv = 5, playerLevel, 5 do
        pcall(function()
            Nodes.CLAIM_LEVEL_MILESTONE:FireServer(lv)
        end)
        task.wait(0.25)
    end

    -- Daily Calendar / Reward Calendar (claimable = Rewards[day] == false)
    print("[AE Kaitun] Claim Daily Calendar...")
    pcall(function()
        local data = peek(Dependencies.PlayerData) or getPlayerData()
        local calendars = data and data.CalendarData
        if type(calendars) ~= "table" then
            return
        end
        for calKey, calData in pairs(calendars) do
            if type(calData) == "table" and type(calData.Rewards) == "table" then
                for dayStr, claimed in pairs(calData.Rewards) do
                    -- false = พร้อมรับ, true = รับแล้ว, nil = ยังล็อก
                    if claimed == false then
                        local day = tonumber(dayStr) or dayStr
                        print("[AE Kaitun] Claim calendar:", calKey, "Day", day)
                        pcall(function()
                            if Actions and Actions.ClaimCalendarReward then
                                Actions.ClaimCalendarReward(calKey, day)
                            end
                        end)
                        pcall(function()
                            Nodes.CLAIM_CALENDAR:FireServer(calKey, day)
                        end)
                        task.wait(0.35)
                    end
                end
            end
        end
    end)
    task.wait(0.4)

    -- Index / Battlepass ถ้ามีของค้าง
    pcall(function()
        Nodes.INDEX_CLAIM_ALL:FireServer()
    end)
    task.wait(0.35)
    pcall(function()
        Nodes.CLAIM_ALL_BATTLEPASS_REWARDS:FireServer()
    end)
    task.wait(0.5)

    print("[AE Kaitun] Claim All เสร็จแล้ว")
end

-- รายการยูนิตในกระเป๋าตาม Rarity (ขายได้)


Rewards.getAchievementCategories = getAchievementCategories
Rewards.claimAllRewards = claimAllRewards

return Rewards
