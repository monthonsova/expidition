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
        "100mvisits",
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
    -- เพชร (ItemData["Gem"]) ไม่พอ → ข้ามการสุ่มเลย ไม่ยิงรัวเสียเวลา
    ["Skip Summon If No Gems"] = true,
    ["Summon Cost Per Pull"] = nil, -- nil = auto อ่านจาก BannerData (ใส่ตัวเลขเองได้ถ้าอ่านไม่เจอ)
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
    ["Auto Evolve To Secret"] = true,

    -- ระบบ Auto-Evolve & Challenge Farming
    ["Auto Evolve Mythic/Secret"] = true,
    ["Auto Quick Craft Ingredients"] = true,
    ["Auto Farm Challenge For Evolution"] = true,
    ["Challenge Mode Type"] = "Regular",
    ["Challenge Mode Index"] = 1,

    -- ระบบเช็ค Gem ขั้นต่ำ 8 รอบสำหรับการสุ่มตัวละคร
    ["Min Summon Rounds Required"] = 8,

    -- Auto Equip: ใส่ไอเทมเสริม/อาวุธที่ดีที่สุด → ยูนิตแข็งสุดไล่ทั้งทีม
    -- ยืนยันจาก decompile (expidition_lobby.rbxlx:1791706):
    --   Actions.EquipEquipment(equipmentId, unitId, slotIndex)
    --   → Nodes.EQUIPMENT_EQUIP:FireServer(equipmentId, unitId, slotIndex)
    -- container = EquipmentData | UnitData[unitId].Equipment = { ["1"] = equipmentId }
    ["Auto Equip Items"] = true,
    ["Auto Equip"] = {
        Enabled = true,
        OnlyEquippedUnits = true, -- true = เฉพาะยูนิตในทีม | false = ทั้งกระเป๋า (เรียงแข็งสุดก่อน)
        ItemsPerUnit = 1,         -- จำนวน equipment ต่อ 1 ยูนิต (ปรับตามช่องของเกม)
        PreferRarity = true,      -- เรียง item ตาม rarity ก่อน
        PreferHighLevel = true,   -- rarity เท่ากันดู level/enhance
        Delay = 0.4,
        -- equip ผ่าน Fusion Actions (หลัก) — ปล่อย nil = auto หา EquipEquipment
        EquipAction = "EquipEquipment",   -- Actions.EquipEquipment(equipmentId, unitId, slotIndex)
        UnequipAction = "UnequipEquipment",
        ContainerKey = "EquipmentData",
        -- item_unit_slot = (equipmentId, unitId, slotIndex) ← ลำดับจริงจาก decompile
        ArgOrder = "item_unit_slot",   -- "item_unit_slot" | "unit_item" | "item_unit" | "table"
        -- fallback ผ่าน Nodes (ถ้าเกมเปลี่ยนไปใช้ remote — ปกติไม่ใช้)
        EquipNode = nil,
        UnequipNode = nil,
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
            Map = "SchoolGrounds",
            Act = "Act 1",
            Difficulty = "Hard",
        },

        -- แพ้ติดกันกี่ครั้งแล้ว soft-reset (กลับ lobby คิวเดิมบนเซิร์ฟใหม่) - 0 = ปิด
        FailSoftReset = 3,
    },

    -- alias ระดับบน (อ่านได้ทั้งสองที่)
    ["Fail Soft Reset"] = 3,

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
    -- เน้นเลือกวางยูนิตสาย Magical (เวท) ก่อนในเฟสดาเมจ
    ["Place Magical First"] = true,
    ["Max Place Per Slot"] = 4,
    ["Max Farm Place"] = 1,
    ["Place Farm After Combat"] = true,
    ["Min Combat Before Farm"] = 2,
    ["Auto Skip Waves"] = true,
    ["Auto Upgrade"] = true,
    -- ยูนิตร่ายสกิล/อัลติอัตโนมัติ = burst damage หลักที่ใช้ตีบอส (ปิดไว้ = ตีบอสไม่ไหว)
    ["Auto Abilities"] = true,

    -- Smart Targeting: ทุก unit เลือกเป้า Boss ถ้ามีบอสในสนาม ไม่งั้น Closest
    -- ยิงผ่าน ChangeGameUnitPriority (decompile ยืนยัน) — บอส = enemy Info.Type มี "Boss"
    ["Smart Targeting"] = true,
    ["Targeting Boss Priority"] = "Boss",       -- เมื่อมีบอส
    ["Targeting Default Priority"] = "Closest",  -- เมื่อไม่มีบอส
    ["Targeting Interval"] = 1.5,                -- วินาที ต่อการเช็ค/อัปเดตเป้า

    -- Feed เชิงรุก: level ยูนิตในทีมที่ยังต่ำ (เช่น carry Mythic Lvl 1) ทุกรอบกลับ lobby
    -- ไม่ต้องรอแพ้ติด — permanent level ต่ำ = base stat ต่ำ = ตีบอสไม่ออก
    ["Auto Feed Team"] = true,
    ["Feed Team Below Level"] = 10, -- feed เฉพาะตัวที่ Level ต่ำกว่านี้ (สูงกว่า=ข้าม กันเปลืองอาหาร)
    ["Feed Team Food Per Unit"] = 100, -- อาหารต่อตัวต่อรอบ (มากกว่า SmartPlay recovery เพราะดัน carry)

    -- Placement strategy แบบ Kaitun.lua (กระจายตามทาง+ใกล้มอน) + เน้นวาง Magical ก่อน
    ["Smart Placement"] = {
        Enabled = true,
        CarryFirst = true,    -- เฟสดาเมจ: จัดลำดับวาง (Magical ก่อน → DPS สูง → ถูกสุด)
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
