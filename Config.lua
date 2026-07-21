--[[
    AE Kaitun — Anime Expeditions Configuration
]]

if not _G.Settings then
    _G.Settings = {}
end

local defaultSettings = {
    -- หน้า Pick a Starter Unit! (บัญชีใหม่)
    ["Auto Choose Starter"] = true,
    ["Starter Unit"] = "Goku", -- Carrot ในเกม = Asset "Goku"

    -- ใส่โค้ดอัตโนมัติ (Nodes.CLAIM_CODE)
    ["Auto Redeem Codes"] = true,
    ["Codes"] = {
        "100K!",
        "30KLIKES!",
        "EXPEDITIONS",
        "SorryForBugs",
        "AE#1",
        "EA+",
        "EA",
        "RELEASE",
        "sorryforguilds",
        "SorryForRestart",
        "200KCCU",
    },

    -- สุ่มหลังใส่โค้ด: Standard ×10
    ["Auto Summon"] = true,
    ["Summon Banner"] = "Standard",
    ["Summon Amount"] = 10,
    ["Summon Rounds"] = 8,
    ["Summon Delay"] = 4,
    ["Summon Unique Legendary"] = {
        { MinLevel = 1,  Count = 4 },
        { MinLevel = 15, Count = 5 },
    },

    -- ขายยูนิตในกระเป๋า (lobby) ตาม Rarity
    ["Auto Sell Bag"] = true,
    ["Sell Bag Rarities"] = { "Rare", "Epic" },

    -- ทีม
    ["Use Load Team"] = false,
    ["Force Reload Team"] = false,
    ["Team Index"] = 1,
    ["Include Equipment"] = true,

    ["Units"] = {
        "Ichiraku", -- UI: Ramen Guy
        "Riyo",     -- UI: Scissor
    },

    -- คิวเริ่มเกม
    ["Queue"] = {
        ["Gamemode"] = "Story",
        ["MapName"] = "SchoolGrounds",
        ["ActName"] = "Act 1",
        ["Difficulty"] = "Normal",
    },

    -- ฟาร์ม Story อัตโนมัติ
    ["Auto Farm"] = {
        Enabled = true,

        Clear = {
            Enabled = true,
            ByLevel = true,
            MapsByLevel = {
                { MinLevel = 1,  Map = "SchoolGrounds" },
                { MinLevel = 15, Map = "FlowerForest" },
                { MinLevel = 30, Map = "Dressrosa" },
            },
            Maps = {
                "SchoolGrounds",
                "FlowerForest",
                "Dressrosa",
                "KingsTomb",
                "FairyKingForest",
            },
            Acts = { "Act 1", "Act 2", "Act 3", "Act 4", "Act 5" },
            Difficulties = { "Normal" },
            SkipCleared = true,
            Loop = false,
        },

        Grind = {
            Enabled = true,
            AfterClear = true,
            Map = "SchoolGrounds",
            Act = "Act 1",
            Difficulty = "Hard",
        },
    },

    ["Use Matchmaking"] = false,
    ["Boost FPS"] = true,

    -- In-game
    ["Auto Vote Start"] = true,
    ["Auto Place Units"] = true,
    ["Place Delay"] = 0.85,
    ["Place Near Path"] = true,
    ["Place Near Enemies"] = true,
    ["Max Place Per Slot"] = 4,
    ["Max Farm Place"] = 1,
    ["Place Farm After Combat"] = true,
    ["Min Combat Before Farm"] = 2,
    ["Auto Sell At Wave"] = true,
    ["Sell Wave"] = 30,
    ["Auto Skip Waves"] = true,
    ["Auto Upgrade"] = true,

    -- UI & Rewards
    ["Show Stats UI"] = true,
    ["Auto Claim Rewards"] = true,
    ["Apply Unit Settings"] = true,
}

for k, v in pairs(defaultSettings) do
    if _G.Settings[k] == nil then
        _G.Settings[k] = v
    end
end

return _G.Settings
