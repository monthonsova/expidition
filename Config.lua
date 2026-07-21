-- AE Kaitun — Anime Expeditions Configuration

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
    -- ห้ามขายตัว shiny (แม้อยู่ใน Sell Bag Rarities) — shiny หายาก/สตัทดีกว่า เก็บไว้ก่อน
    -- true = กันขาย shiny ทุกตัว | false = ขาย shiny ตาม Sell Bag Rarities ปกติ
    ["Keep Shiny"] = true,
    -- ขายยูนิตซ้ำ Asset ที่ไม่ได้ใช้ (เก็บตัวดีสุด: shiny→level→worthiness) ทุกรอบ auto-sell
    ["Sell Duplicate Legendaries"] = true,
    ["Dedup Rarities"] = { "Legendary" }, -- เรตที่จะเก็บแค่ตัวเดียวต่อ Asset (Mythic+ ไม่แตะ)

    -- ทีม
    ["Use Load Team"] = false,
    ["Force Reload Team"] = false,
    ["Team Index"] = 1,
    ["Include Equipment"] = true,

    -- Secret = ดันทีม Secret (evolve Mythic→Secret ให้) | Mythic = ทีม Mythic อัตโนมัติ
    -- Units = ตามลิสต์ | Best = rarity+เลเวลสูงสุด
    -- ลำดับ rarity จริง: Secret > Exclusive > Mythic > Legendary > Epic > Rare
    ["Team Mode"] = "Mythic",
    ["Smart Mythic Team"] = {
        Enabled = true,
        PreferMythic = true,
        FillWithLegendary = true, -- ช่องเหลือเติม Legendary คนละตัว
        ReplaceWeakUnits = true, -- มี Mythic แล้วถอดตัวอ่อนในลิสต์ Units ออก
        PreferShiny = true,
        PreferHighDPS = true, -- ใช้ DPS จริง (damage/spa) จัดอันดับในเรตเดียวกัน — ฉลาดเลือกจาก stats
        PreferHighWorthiness = true,
    },
    -- ทีม Secret: Secret/Exclusive ได้จาก summon (ถ้ามีในพูล) หรือ evolution
    ["Smart Secret Team"] = {
        Enabled = true,
        FillWithMythic = true,    -- Secret ไม่พอ → เติม Mythic
        FillWithLegendary = true, -- แล้วค่อย Legendary
        ReplaceWeakUnits = true,
        PreferShiny = true,
        PreferHighDPS = true,
        PreferHighWorthiness = true,
    },
    -- SmartPlay จะ evolve Mythic → Secret/Exclusive ให้ ถ้าวัตถุดิบครบ
    -- ปิดไว้ก่อน: evolve ต้องใช้ของจาก Challenge ที่ยังไม่ได้ทำ (เปิดทีหลังพร้อม TryEvolve)
    ["Auto Evolve To Secret"] = false,

    -- Auto Equip: ใส่ไอเทมเสริม/อาวุธที่ดีที่สุด → ยูนิตแข็งสุดไล่ทั้งทีม
    -- เกม decompile ไม่ระบุชื่อ node/คีย์ equipment → โมดูล auto-discover ให้ตอนรัน
    -- ถ้า discover พลาด รัน AEKaitun.DumpEquip() ในคอนโซลแล้วเอาชื่อจริงมาใส่ override ด้านล่าง
    ["Auto Equip Items"] = true,
    ["Auto Equip"] = {
        Enabled = true,
        OnlyEquippedUnits = true, -- true = เฉพาะยูนิตในทีม | false = ทั้งกระเป๋า (เรียงแข็งสุดก่อน)
        ItemsPerUnit = 1,         -- จำนวน equipment ต่อ 1 ยูนิต (ปรับตามช่องของเกม)
        PreferRarity = true,      -- เรียง item ตาม rarity ก่อน
        PreferHighLevel = true,   -- rarity เท่ากันดู level/enhance
        Delay = 0.4,
        -- override เมื่อ auto-discover ไม่ตรง (ปล่อย nil = auto)
        EquipNode = nil,          -- ชื่อคีย์ใน Nodes เช่น "UNIT_EQUIP_ITEM"
        UnequipNode = nil,
        ContainerKey = nil,       -- คีย์ใน PlayerData เช่น "EquipmentData"
        ArgOrder = "unit_item",   -- "unit_item" | "item_unit" | "unit_item_slot"
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
        TryEvolve = false, -- ปิดไว้ก่อน: evolve ต้องใช้ของจาก Challenge (เปิดทีหลัง)
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
    ["Auto Skip Waves"] = true,
    ["Auto Upgrade"] = true,
    -- ยูนิตร่ายสกิล/อัลติอัตโนมัติ = burst damage หลักที่ใช้ตีบอส (ปิดไว้ = ตีบอสไม่ไหว)
    ["Auto Abilities"] = true,

    -- Smart Placement: วางแบบดูระยะยิง + วางตัว DPS สูงสุดก่อน
    ["Smart Placement"] = {
        Enabled = true,
        RangeCoverage = true, -- ให้คะแนนจุดที่คลุม path ในระยะยิงยูนิตได้มากสุด (ยิงโดนนาน = โหด)
        CarryFirst = true,    -- เฟสดาเมจ วางตัว DPS สูงสุดก่อน (ลงสนาม+อัปเกรดไว)
        CoverWeight = 8,      -- น้ำหนักโบนัส coverage (สูง = เน้นคลุม path มากกว่าเข้าใกล้มอน)
    },

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
