# AE Kaitun — บันทึกโครงสร้างเกมจริง (จาก decompile .rbxlx)

เอกสารนี้สรุปข้อมูลที่ขุดได้จริงจากไฟล์:
- `expidition_lobby.rbxlx` (~71MB) — สแนปช็อตรวม LocalScript/ModuleScript ฝั่ง lobby (decompiled ด้วย "Potassium's decompiler")
- `expidition_playmap_easy_story1.rbxlx` (~63MB) — สแนปช็อตตอนอยู่ในด่าน (Story 1, Easy)

ใช้ยืนยัน/แก้ path, ชื่อ remote, ชื่อ field ที่สคริปต์ AFK farm (`src/*.lua`) เรียกใช้ ว่าตรงกับเกมจริง 100% หรือไม่ — ไม่ใช่การเดาอีกต่อไป

---

## 1. โครงสร้าง ReplicatedStorage (สำคัญที่สุด — เคยเดาผิด)

```
ReplicatedStorage
├── Nodes                 -- ModuleScript ต้อง require() ก่อนใช้! (คืนตาราง Node แต่ละตัวมี :FireServer/:Request/:InvokeSelf/:Connect/:Fire/:FireSelf)
├── Shared                -- Folder (ใช้ตรงๆ ไม่ต้อง require ตัวมันเอง) มีลูก:
│   ├── Utils             -- require(Shared.Utils)
│   ├── Information       -- require(Shared.Information)  -- asset registry, :GetAsset(name), .Quests, .Settings, .PlayerLevelInfo ฯลฯ
│   ├── UnitUtils         -- require(Shared.UnitUtils)     -- :IsPlacementAllowed, :GetUnitBoundingBoxSize, :GetPlacementIgnoreList, :IsUnitNameFarm, :GetUpgradeStats
│   ├── ReplicaClient     -- require(Shared.ReplicaClient) -- .OnNew("StateName", handler)
│   └── Maid
└── FusionPackage         -- Folder
    ├── Fusion            -- require(FusionPackage.Fusion) -- Fusion.peek, Fusion.scoped, ...
    ├── State             -- require(FusionPackage.State)
    ├── Dependencies      -- require(FusionPackage.Dependencies) -- ตัวรวม state ทั้งหมด (ดูหัวข้อ 2)
    ├── Actions           -- require(FusionPackage.Actions)      -- .IsPlacementAllowed(asset, cframe), .LoadUnitTeam(idx, withEq), .SaveUnitTeam(idx, confirm)
    └── Components/...    -- Fusion UI components
```

**บั๊กที่เจอและแก้แล้วใน `src/Core.lua`:**
- ของเดิม (จากตอนที่ผมเขียน Core.lua ครั้งก่อนโดยไม่มีไฟล์เกมจริงให้เทียบ) เดาว่ามี `ReplicatedStorage.Replica.Dependencies` และ `ReplicatedStorage.Replica.Actions` — **ไม่มีโฟลเดอร์ `Replica` อยู่จริงในเกมเลย** ทำให้ `Dependencies` และ `Actions` เป็น `nil` เสมอ (แค่ warn เงียบๆ ไม่ error ให้เห็น) ⇒ ทุกฟังก์ชันที่อ่าน state ผ่าน `Dependencies.*` (Hotbar, PlayerData, GamePlayerState, GameUnits, GameEnemies, MapState) และการเช็ค `Actions.IsPlacementAllowed` **ใช้ไม่ได้เลยทั้งระบบ** มาตลอด
- ของเดิมใช้ `Nodes = ReplicatedStorage:WaitForChild("Nodes")` เป็น **Instance ดิบ** (ModuleScript) โดยไม่ `require()` — `Nodes.XXX:FireServer()` จะพังเพราะ ModuleScript ไม่มีเมธอด `FireServer` ต้อง `require()` ก่อนถึงจะได้ตาราง Node จริง
- `peek()` เดิมเป็น heuristic เขียนเอง (เดาว่าเป็น `.Value`/`:get()`/`:Get()`) — ตอนนี้เปลี่ยนไปใช้ `Fusion.peek` จริงจาก `FusionPackage.Fusion` เป็นค่าเริ่มต้น (รองรับ Value/Computed/ForPairs/ForKeys/ForValues ถูกต้องตาม Fusion API) แล้ว fallback เป็น heuristic เดิมถ้า require Fusion ไม่ได้

**แก้แล้ว** — `Core.lua` ตอนนี้ resolve ตามโครงสร้างจริงข้างบน (Nodes ผ่าน require, Dependencies/Actions ผ่าน `FusionPackage`, peek ผ่าน `Fusion.peek` จริง)

---

## 2. `Dependencies` (จาก `FusionPackage.Dependencies`, require แล้วได้ตารางนี้)

ยืนยันจาก source จริง (`local u3 = { scope = v2, Information = Information, ... }`):

| Key | ชนิด | หมายเหตุ |
|---|---|---|
| `scope` | Fusion scope (`Fusion.scoped(...)`) | มีเมธอด `:KeyOf(state, ...)`, `:Fallback(a, b)`, `:Value()`, `:Computed()` ฯลฯ |
| `Information` | table (module เดียวกับ `Shared.Information`) | `:GetAsset(name)`, `.Quests`, `.Settings`, `.PlayerLevelInfo` |
| `PlayerData` | Fusion Value | `peek()` แล้วได้ table: `.UnitData[id]`, `.HotbarData[slot]`, `.CompletedMaps`, `.Level`, `.Settings`, `.ItemData`, `.EquipmentData`, `.QuestData` ฯลฯ |
| `HotbarState` | Fusion Value | `peek()` แล้วได้ table: `.Slots[tostring(i)] = {AssetType="Unit", ID=uuid}` หรือ `{Data={Asset=...}}`, `.MaxSlots` (base 3, +1 ที่ lv10/15/20 → สูงสุด **6**), `.SlotLevels[i]`, `.PlacementAllowed`, `.UnitManagement` |
| `GameState` | Fusion Value | `.GlobalUnitPlacementCap`, `.Parameters.Gamemode`, `.GameTime`, `.EndTime` |
| `GamePlayerState` | Fusion Value | `.Yen`, `.TotalUnitPlacementCap`, `.PlacementLimits[asset]`, `.PlacementCounts[asset]` |
| `MapState` | Fusion Value | `.Paths` (array ของ path arrays), `.DisabledPaths`, `.MapID` |
| `GameUnits` | Fusion Value (table keyed by model/id) | แต่ละ entry (ต้อง peek ซ้อน) มี `.Owner`, `.Asset`/`.Data.Asset`, `.IsPhantom`, `.IsClone` |
| `GameEnemies` | Fusion Value (table keyed by Model instance) | ใช้ `model.PrimaryPart.Position` |
| `SelectedInstance`, `HoveringInstance` | Fusion Value | ใช้กับ `scope:KeyOf(Dependencies.GameUnits, SelectedInstance)` |
| `SessionData`, `PartyData`, `BannerData`, `Codes`, `Titles`, ... | Fusion Value อื่นๆ ที่ยังไม่ได้ใช้ในสคริปต์นี้ |

**ผลตรวจ:** ทุก key ที่สคริปต์ `PlacementEngine.lua` / `Replicas.lua` ใช้อยู่ (`HotbarState`, `PlayerData`, `GameState`, `GamePlayerState`, `MapState`, `GameUnits`, `GameEnemies`, field ย่อยทั้งหมดรวมถึง `Yen`, `TotalUnitPlacementCap`, `GlobalUnitPlacementCap`, `PlacementLimits`, `PlacementCounts`, `Slots`, `SlotLevels`) **ตรงกับเกมจริง 100%** — ไม่ต้องแก้ชื่อ field ใดๆ

**MaxSlots ยืนยัน = สูงสุด 6 ช่อง** (`SlotLevels = {[4]=10, [5]=15, [6]=20}`, base 3) → hardcode `for i = 1, 6` ในสคริปต์ **ถูกต้องแล้ว ไม่ใช่บั๊ก**

**บั๊ก Fallback แก้แล้ว:** เกมจริงใช้ `Fallback(GamePlayerState.TotalUnitPlacementCap, GameState.GlobalUnitPlacementCap)` คือ "ใช้ค่า per-player ก่อนถ้ามี ไม่ใช่เอา max" — ของเดิมใน `getTotalPlacementCap()` เอาค่ามากสุดระหว่างสองตัว ซึ่งผิดความหมายถ้า Global > Total (จะเข้าใจว่าวางได้เกินจำกัดจริง) → แก้เป็น priority แบบ Fallback จริงแล้ว (`src/PlacementEngine.lua`)

---

## 3. `Actions` (จาก `FusionPackage.Actions`)

ยืนยันแล้วว่ามีอย่างน้อย:
- `Actions.IsPlacementAllowed(asset, cframe, extra?)` → เรียกผ่าน `UnitUtils:IsPlacementAllowed(...)` จริง ตรงกับที่ `PlacementEngine.lua` เรียกอยู่เป๊ะๆ (Blockcast บน `CollectionService:GetTagged("GroundPlacement")`/`"HillPlacement"`, เช็คชนกับ `Nodes.GET_ALL_UNIT_MODELS:InvokeSelf()` ฝั่ง client)
- `Actions.LoadUnitTeam(idx, withEquipment: boolean)`
- `Actions.SaveUnitTeam(idx, confirm: boolean)`

---

## 4. `Nodes` (require แล้วได้ตาราง Node, เรียกด้วย `:FireServer`/`:Request`/`:InvokeSelf`/`:Connect`/`:Fire`/`:FireSelf`)

ยืนยันตรงกับสคริปต์ทุกตัวที่ใช้อยู่ (ไม่มีชื่อผิดเลยสักตัว):

| Node | วิธีเรียกจริงในเกม | ใช้ในไฟล์ |
|---|---|---|
| `PARTY_CREATE` | `:Request(data):Timeout(5):Once(fn)` | `Lobby.lua` |
| `WAIT_FOR_PARTY_REPLICA` | `:InvokeSelf()` | `Lobby.lua` |
| `REQUEST_ENTER_MATCHMAKING` | `:Request(data)` | `Lobby.lua` |
| `GET_PARTY_DATA_REPLICA`, `GET_GAME_PLAYER_REPLICA`, `GET_GAME_REPLICA` | `:InvokeSelf()` | `Replicas.lua`, `AutoFarmManager.lua` |
| `CHOOSE_STARTER_UNIT` | `:FireServer(assetName)` (ตอบสนอง `PROMPT_CHOOSE_STARTER_UNIT`) | `StarterUnit.lua` |
| `CLAIM_CODE` | `:Request(code):Timeout(5)` | `Codes.lua` |
| `BANNER_SUMMON` | `:FireServer(bannerName, amount)` | `Summon.lua` |
| `ASSET_SELL_TABLE` | `:FireServer("Unit", idMap)` | `Summon.lua` |
| `UNIT_SELL_TABLE` | `:FireServer(idMap)` | `Summon.lua` |
| `UNIT_SELL` | `:FireServer(id)` | `Summon.lua` |
| `UNIT_EQUIP` | `:FireServer(unitId, slotString)` | `Team.lua` |
| `UNIT_UNEQUIP_ALL` | `:FireServer()` | `Team.lua` |
| `UNIT_LOAD_TEAM` | `:FireServer(idx, withEquipment)` | `Team.lua` |
| `QUEST_CLAIM_ALL`, `QUEST_CLAIM_ALL_CATEGORY`, `QUEST_CLAIM_ALL_CATEGORIES`, `QUEST_CLAIM_CATEGORY` | `:FireServer(...)` | `Rewards.lua` |
| `CLAIM_LEVEL_MILESTONE` | `:FireServer(level?)` | `Rewards.lua` |
| `CLAIM_CALENDAR` | `:FireServer(calendarKey, day)` | `Rewards.lua` |
| `INDEX_CLAIM_ALL`, `CLAIM_ALL_BATTLEPASS_REWARDS` | `:FireServer(...)` | `Rewards.lua` |
| `GET_ALL_UNIT_MODELS` | `:InvokeSelf()` (client-side, มี handler `:Connect` แยกจดทะเบียนไว้แล้วในเกม) | `PlacementEngine.lua` |
| `CLIENT_CHANGE_SETTING` | `:FireServer(key, value)` | `InGame.lua` |
| `CLIENT_TOGGLE_AUTO_SKIP_WAVES` | `:FireServer()` | `InGame.lua` |
| `PROMPT_CLOSE`, `PROMPT_CLOSE_ALL`, `PROMPT_CLOSED`, `PROMPT_OBTAINED_REWARD_SLOTS`, `PROMPT_OBTAINED_REWARDS` | ต่างๆ | `Summon.lua` |

---

## 5. CollectionService tags (ยืนยันจากแมพจริง Story 1 Easy)

- `"GroundPlacement"`, `"HillPlacement"` — จุดวางยูนิต (ตรงกับ `PlacementEngine.lua`)
- `"Path"` — จุดทางเดินมอน (ตรงกับ fallback ใน `getPathPoints`)
- `"IgnoreRaycast"`, `"IgnoreRays"`, `"UnitFollower"`, `"HighlightGroup_UnitPlacement"` — อยู่ใน ignore list ของ `UnitUtils:GetPlacementIgnoreList()` จริง ตรงกับที่ `canPlaceAt` ใช้

---

## 6. สรุปผลตรวจ (ทำไปแล้ว)

1. **แก้ `src/Core.lua`** — เปลี่ยน path resolve ของ `Nodes` (ต้อง require), `Dependencies`/`Actions` (อยู่ใน `FusionPackage` ไม่ใช่ `Replica` ที่ไม่มีจริง), `peek` (ใช้ `Fusion.peek` จริงเป็นหลัก) — **นี่คือบั๊กร้ายแรงที่สุดที่เจอ เพราะทำให้ทั้งระบบอ่าน state (Hotbar/PlayerData/GamePlayerState/GameUnits/GameEnemies/MapState) และเช็ค `Actions.IsPlacementAllowed` ใช้ไม่ได้มาตลอดตั้งแต่ Core.lua ถูกสร้างขึ้น**
2. **แก้ `src/PlacementEngine.lua`** — `getTotalPlacementCap()` เปลี่ยนจาก "เอาค่ามากสุด" เป็น Fallback แบบเกมจริง (priority: per-player Total ก่อน Global)
3. ตรวจสอบ remote/field name ที่ใช้อยู่ทั้งหมดเทียบกับซอร์สจริง (Nodes.*, Dependencies.*, Actions.*, CollectionService tags) — **ตรงกันทั้งหมด ไม่มีชื่อผิด**
4. ยืนยัน MaxSlots สูงสุด = 6 → ไม่ต้องแก้ loop hardcode

## 6b. อัปเดตรอบตรวจซ้ำ — เจอ `Shared` ชื่อซ้อนกัน 2 ตัว (บั๊กจริง แก้แล้ว)

ยืนยันจาก decompile ว่าในเกมมีตัวแปรชื่อ `Shared` อยู่ **2 ตัวคนละที่คนละหน้าที่**:

1. `ReplicatedStorage.Shared` — **Folder** ใช้ตรงๆ ไม่ต้อง require ตัวมันเอง (มีลูกให้ require รายตัว: `Utils`, `Information`, `UnitUtils`, `ReplicaClient`, `Maid`) — นี่คือตัวที่ `Core.Shared` ชี้ไปถูกแล้ว
2. `require(FusionPackage.Shared)` — **ModuleScript** คืนตาราง Fusion state ของทั้งเกม มี field เช่น `IsInGame = IsFilled(Dependencies.GameState)`, `IsGameActive = KeyOf(Dependencies.GameState, "Active")`, `IsInParty = IsValid(Dependencies.PartyData)`, `SelectedHotbarIndex = GetState("SelectedHotbarIndex")`

**บั๊กที่เจอ:** โค้ดเดิมใช้ `Shared.IsInGame` / `Shared.IsGameActive` / `Shared.SelectedHotbarIndex` โดยอ้างถึง `Core.Shared` (ตัวที่ 1 — Folder) ซึ่ง**ไม่มี field เหล่านี้เลย** ต้องเป็นตัวที่ 2 (โมดูล FusionPackage.Shared) — อาการ: `isInGame()` จะพังทุกครั้งที่เรียก (index nil/error) และการวางยูนิตอัตโนมัติจะ error แฝงตอนพยายามเคลียร์ ghost-placement selection

**แก้แล้ว** (ไม่ต้อง require โมดูลที่สองเพิ่มเลย เพราะทั้ง 2 field แปลงกลับมาอ่านจาก `Dependencies` ตรงๆ ได้):
- `Replicas.lua: isInGame()` → เช็ค `peek(Dependencies.GameState) ~= nil` ตรงๆ (เทียบเท่า `IsFilled`)
- `InGame.lua: isGameActive()` → อ่าน `peek(Dependencies.GameState).Active` ตรงๆ (เทียบเท่า `KeyOf(GameState, "Active")`)
- `InGame.lua: clearHotbarSelection()` → ใช้ `Dependencies.scope:GetState("SelectedHotbarIndex"):set(nil)` (named-state ของ Fusion "State" extension เรียกจาก scope ไหนก็ได้ค่าเดียวกัน ยืนยันจาก UI หลายที่ในเกมเรียกชื่อนี้แล้วได้ตัวเดียวกัน)

**บั๊กเดียวกันอีกจุด:** `Rewards.lua: getAchievementCategories()` เดิมพยายาม `Shared.Information.Quests:GetChildren()` — ผิดทั้ง path (`Shared` โฟลเดอร์ไม่มี `.Quests`) และ `Information` ต้อง `require()` ก่อนด้วย → แก้เป็นคืนลิสต์ชื่อ 5 หมวดตรงๆ (ยืนยันแล้วว่าตรงกับ ModuleScript จริงในเกมทั้ง 5 ชื่อ: `Achievement_Collector/Story/Raid/Secret/Expeditions`) ตัดการสแกน children ที่เสี่ยงพังออก

## 7. จุดที่ยังเป็นข้อสังเกต (ความเสี่ยงต่ำ ไม่ได้แก้เพราะมี fallback ครอบอยู่แล้ว)

- `StarterUnit.lua` ยิง `CHOOSE_STARTER_UNIT:FireServer(asset)` ตรงๆ โดยไม่รอ `Nodes.PROMPT_CHOOSE_STARTER_UNIT:Connect` ก่อน (เกมจริงยิง prompt นี้ให้ UI แสดงตัวเลือกก่อน) — ถ้าเซิร์ฟเวอร์เช็คแค่ "ผู้เล่นยังไม่มียูนิต" ก็ยิงตรงได้ปกติ (ตามที่ออกแบบไว้เดิม) แต่ถ้าเซิร์ฟเวอร์บังคับต้องมี prompt state ก่อนอาจถูกเซิร์ฟเวอร์เมิน — ให้สังเกตว่าไอดีใหม่ได้ยูนิตจริงไหมหลังรันสคริปต์ ถ้าไม่ได้ให้แจ้งกลับมาแก้เพิ่ม (ต่อ `Nodes.PROMPT_CHOOSE_STARTER_UNIT:Connect` ก่อนยิง)
