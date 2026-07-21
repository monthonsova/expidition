-- AE Kaitun - Anime Expeditions Configuration

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

    -- Mythic = จัดทีม Mythic อัตโนมัติ (แนะนำ) | Units = ตามลิสต์ | Best = rarity+เลเวลสูงสุด
    ["Team Mode"] = "Mythic",
    ["Smart Mythic Team"] = {
        Enabled = true,
        PreferMythic = true,
        FillWithLegendary = true, -- ช่องเหลือเติม Legendary คนละตัว
        ReplaceWeakUnits = true, -- มี Mythic แล้วถอดตัวอ่อนในลิสต์ Units ออก
        PreferShiny = true,
        PreferHighWorthiness = true,
    },

    -- ใช้ตอน Team Mode = "Units" หรือเป็น fallback ถ้ายังไม่มี Mythic/Leg
    ["Units"] = {
        "Ichiraku", -- UI: Ramen Guy
        "Riyo",     -- UI: Scissor
    },

    -- เป้าสุ่ม Mythic คนละตัว (หยุดเมื่อครบ หรือครบ Legendary ตามด้านบน)
    ["Summon Unique Mythic"] = {
        { MinLevel = 1,  Count = 1 },
        { MinLevel = 15, Count = 2 },
        { MinLevel = 30, Count = 3 },
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
            -- ProgressionIndex เกมจริง: 1 School -> 2 Flower -> 3 Dressrosa -> 4 FairyKing -> 5 KingsTomb
            -- MinLevel = เกณฑ์เสริม (ปลดจริงดู CompletedMaps / HasMapUnlocked)
            MapsByLevel = {
                { MinLevel = 1,  Map = "SchoolGrounds" },
                { MinLevel = 15, Map = "FlowerForest" },
                { MinLevel = 30, Map = "Dressrosa" },
                { MinLevel = 45, Map = "FairyKingForest" },
                { MinLevel = 60, Map = "KingsTomb" },
            },
            Maps = {
                "SchoolGrounds",
                "FlowerForest",
                "Dressrosa",
                "FairyKingForest",
                "KingsTomb",
            },
            Acts = { "Act 1", "Act 2", "Act 3", "Act 4", "Act 5" },
            Difficulties = { "Normal" },
            SkipCleared = true,
            Loop = false,
        },

        Grind = {
            Enabled = true,
            AfterClear = true,
            -- nil = ใช้แมพ Story สุดท้ายที่เคลียร์แล้ว (อย่า hardcode School Act1)
            Map = nil,
            Act = "Act 1",
            Difficulty = "Hard",
        },

        -- แพ้ติดกันกี่ครั้งแล้ว soft-reset (กลับ lobby คิวเดิมบนเซิร์ฟใหม่) - 0 = ปิด
        FailSoftReset = 8,
    },

    -- alias ระดับบน (อ่านได้ทั้งสองที่)
    ["Fail Soft Reset"] = 8,

    -- แพ้ติด / soft-reset -> SmartPlay: เคลียร์กระเป๋า -> สุ่ม -> ฟีด/evolve -> ทีมใหม่
    ["Smart Play Enabled"] = true,
    ["Smart Play"] = {
        Enabled = true,
        OnFailSoftReset = true,
        OnLobbyReturnAfterFail = true,
        SellWhenFreeSlotsBelow = 15, -- ว่างน้อยกว่านี้ -> ขาย Rare/Epic
        SellDuplicateLegendaries = true, -- true = ขาย Legendary ซ้ำ Asset (เก็บเลเวลสูงสุด)
        SummonRounds = 3,
        SummonAmount = 10,
        FeedEquipped = true,
        FeedFoodPerUnit = 25,
        TryEvolve = true,
        RemakeTeam = true,
        PreferBestUnits = true, -- ใส่ Mythic/Legendary เลเวลสูงสุดแทนลิสต์ Units เดิม
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
