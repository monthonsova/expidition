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
| `UNIT_FEED` | `:FireServer(unitId, { [foodItem]=amount })` | `SmartPlay.lua` |
| `TRY_EVOLVING_UNIT` | `:Request(unitId, evolvedAsset):Timeout(5):Wait()` | `SmartPlay.lua` |
| `SHOW_END_SCREEN` | `:Connect(result)` — Defeat/Victory recovery | `InGame.lua` |

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

**ระดับความรุนแรง:** `isInGame()` (`Replicas.lua`) ถูกเรียกเป็นจุดแรกสุดใน `init.lua` (บรรทัด `if Replicas.isInGame() then ... else ...`) และเป็นแกนของ `FarmLoop.lua` ทั้งไฟล์ (`waitUntilInGame`, `waitUntilBackToLobby`, เงื่อนไขหลักของลูป) โดย**ไม่มี `pcall` ครอบ** — ตอน `Shared.IsInGame` ชี้ผิด (ไม่มี field นี้บน Folder) การ index แบบนี้จะ **throw error ทันทีที่เรียกครั้งแรก** ("IsInGame is not a valid member of Folder") ทำให้ทั้ง `task.spawn` หลักใน `init.lua` ตายตั้งแต่บรรทัดแรกๆ — เท่ากับสคริปต์ทั้งชุด **ไม่ทำงานอะไรเลยตั้งแต่ต้น** ไม่ใช่แค่ auto-farm พังเฉยๆ — ถือเป็นบั๊กที่ร้ายแรงที่สุดที่เจอในรอบตรวจนี้ (คู่กับบั๊ก `Replica` folder ผิดจากรอบก่อน)

**บั๊กเดียวกันอีกจุด:** `Rewards.lua: getAchievementCategories()` เดิมพยายาม `Shared.Information.Quests:GetChildren()` — ผิดทั้ง path (`Shared` โฟลเดอร์ไม่มี `.Quests`) และ `Information` ต้อง `require()` ก่อนด้วย → แก้เป็นคืนลิสต์ชื่อ 5 หมวดตรงๆ (ยืนยันแล้วว่าตรงกับ ModuleScript จริงในเกมทั้ง 5 ชื่อ: `Achievement_Collector/Story/Raid/Secret/Expeditions`) ตัดการสแกน children ที่เสี่ยงพังออก

## 6c. Defeat / ไม่ผ่านด่าน — วิเคราะห์ + ทางออก (อัปเดตแล้วในโค้ด)

### พฤติกรรมเกมจริง (จาก GameResults + settings)
- จบแมตช์ → `Nodes.SHOW_END_SCREEN` ส่ง `ResultData` มีอย่างน้อย: `Victory`, `HasNextStage`, `RestartDisabled`, `Rewards`, …
- ปุ่ม UI: **Next** = `Actions.GameNext` → `GameReplica:FireServer("Next")` (โชว์เฉพาะตอน `Victory` + `HasNextStage`)
- ปุ่ม **Repeat** = `Actions.GameRestart(true)` → `FireServer("Restart")` (ข้าม confirmation ถ้าส่ง `true`)
- ปุ่ม **Lobby** = `Actions.GameReturnLobby` → **เปิด confirmation เสมอ** (ห้ามเรียกจาก AFK) ต้อง `FireServer("Lobby")` ตรงๆ
- Settings: `AutoRetry` = "Automatically restart the game", `AutoNext` = "Automatically start the next stage" (น่าจะฝั่งเซิร์ฟอ่านตอนจบ — client มีแค่ toggle)

### บั๊ก AFK เดิม
Clear mode ตั้ง `AutoNext=on` + `AutoRetry=off` → **ชนะไปต่อได้ แต่แพ้แล้วค้างหน้า Defeat** จน `waitUntilBackToLobby` timeout 30 นาที

### ทางออกที่ลงโค้ดแล้ว
1. `InGame.setupEndScreenHandler` ฟัง `SHOW_END_SCREEN`
   - **Defeat** → `markMatchResult(false)` → `restartCurrentMatch()` (FireServer Restart) คิวไม่ขยับ
   - **Victory + เคลียร์แมพครบ** → กลับ lobby เข้า Grind
   - **Victory + AutoNext ค้าง** → บังคับ `Next` เองหลัง ~4.5 วิ
   - **แพ้ติดกัน ≥ FailSoftReset (default 8)** → กลับ lobby คิวเดิม (เซิร์ฟใหม่)
2. `consumeFarmMatchReturn` / `syncFarmStateFromProgress` อิง `CompletedMaps` อย่างเดียว → แพ้แล้วไม่ข้ามด่าน
3. `returnToLobbyFromMatch` ตัด fallback `Actions.GameReturnLobby` ทิ้ง (มันเด้ง confirm)

### Config
- `Auto Farm.FailSoftReset` / `Settings["Fail Soft Reset"]` = 8 (ตั้ง 0 เพื่อปิด)

## 6d. SmartPlay — แพ้ติด → สุ่มทีมใหม่ / ฟีด / evolve / กระเป๋าเต็ม (อัปเดตแล้ว)

### APIs จากเกมจริง
| เรื่อง | หลักฐาน |
|---|---|
| กระเป๋ายูนิต base **100** / max **500** | `Information.UnitInventoryLimit` + `AssetTypes.Unit.InventoryLimit` |
| ขยายช่อง | `PlayerData.InventoryExpansions.Unit` บวกเข้า base |
| ขาย | `ASSET_SELL_TABLE("Unit", idMap)` / `UNIT_SELL_TABLE` |
| ฟีด EXP | `UNIT_FEED:FireServer(unitId, { [foodItem]=amount })` — อาหาร = item ที่มี `.EXP` (เช่น FoodItem1) |
| Evolve | `TRY_EVOLVING_UNIT:Request(unitId, evolvedAsset):Timeout(5):Wait()` — recipe จาก `Information.Evolutions` |

### Flow หลังแพ้ติด ≥ FailSoftReset
1. `InGame` ตั้ง `needSmartPlay=true` → `Lobby`
2. `FarmLoop` เรียก `SmartPlay.consumeIfNeeded`
3. `SmartPlay.runRecovery`: ขาย Rare/Epic ถ้า free slots น้อย → สุ่ม 3 รอบ → จัดทีมตาม Team Mode → ฟีดยูนิตในทีม → `evolveTowardSecrets` (Mythic→Secret/Exclusive) → evolve ทั่วไป → ใส่ทีมอีกรอบ
4. คิวด่านเดิมจาก `CompletedMaps` (ไม่ข้าม)

### 6d-1. Rarity & ทีม Secret
- ลำดับความหายากจริงในเกม (สูง→ต่ำ): **Secret > Exclusive > Mythic > Legendary > Epic > Rare** (`RARITY_RANK` ใน `Team.lua`/`SmartPlay.lua`)
- **แก้ความเข้าใจผิด (สำคัญ):** banner pool คือ `BannerData[banner].CurrentPool[rarity]` แยกตาม rarity → **บางแบนเนอร์มี `CurrentPool["Secret"]`/`["Exclusive"]` = สุ่มได้ Secret/Exclusive ตรงๆ** ไม่ใช่ได้จาก evolve อย่างเดียว
- ดังนั้น "ทีม Secret" ได้ Secret 2 ทาง: (1) ซัมมอนติดตรงๆ ถ้าแบนเนอร์มีพูล (2) evolve Mythic→Secret (SmartPlay)
- `Summon.shouldStopSummonMythicFirst()` โหมด Secret นับ **unique Secret + Exclusive + Mythic** เทียบเป้า (ติด Secret ตรงๆ = เข้าเป้าเร็วขึ้น) — helper: `Summon.countUniqueByRarityInBag(rarity)`, `Summon.getUnitsByRarityInBag(rarity)`
- Debug: `AEKaitun.CountSecrets()` (คืน secret, exclusive), `AEKaitun.GetBannerSecrets()` (พูล Secret ของแบนเนอร์ปัจจุบัน)
- `Team Mode = "Secret"` → `Team.ensureSecretTeam` → `buildSecretTeam` (เรียง Secret→Exclusive→Mythic→Legendary; getBestUnitsForTeam เรียงตาม RARITY_RANK อยู่แล้ว)
- `SmartPlay.evolveTowardSecrets(cfg)`: สแกนยูนิตในทีม + Mythic ในกระเป๋า → หา `Evolutions:GetEvolvedUnit(asset)` ที่ผลลัพธ์เป็น Secret/Exclusive → เช็ควัตถุดิบ (`GetFilteredRecipe`) + เลเวล ≥ min(maxLv,50) → `TRY_EVOLVING_UNIT` (เปิด/ปิดด้วย `["Auto Evolve To Secret"]`)
- Debug: `AEKaitun.EnsureSecretTeam()`, `AEKaitun.BuildSecretTeam()`, `AEKaitun.EvolveToSecret()`

### Config
```lua
["Smart Play"] = {
  Enabled = true,
  SellWhenFreeSlotsBelow = 15,
  SummonRounds = 3,
  FeedEquipped = true,
  TryEvolve = true,
  PreferBestUnits = true,
  SellDuplicateLegendaries = false,
}
```
Debug: `AEKaitun.SmartPlay()`, `AEKaitun.SmartPlayBag()`, `AEKaitun.RemakeBestTeam()`

## 6e. Clear ครบทุก Story แล้วทำอะไร (อัปเดต)

ลำดับแมพ Story จริง (ProgressionIndex):
1. SchoolGrounds → 2. FlowerForest → 3. Dressrosa → 4. FairyKingForest → 5. KingsTomb

**ของเดิม (บั๊ก):** `ByLevel` คืนแมพเดียว + เข้า Grind ทันทีหลังเคลียร์แมพนั้น + มีโค้ด `"ไม่ไปแมพอื่น"` → ไม่เคยไป FairyKing/KingsTomb

**ตอนนี้:**
- Clear ไล่ทุกแมพที่ปลดแล้ว (ปลดจาก `HasMapUnlocked` / แมพก่อนหน้าเคลียร์ครบ + MinLevel)
- เข้า **Grind** (Hard Act 1 วนฟาร์มเพชร) **เมื่อเคลียร์ครบทุกแมพที่ปลดแล้วเท่านั้น**
- ถ้าเลเวลขึ้นแล้วปลดแมพใหม่ระหว่าง Grind → ออก Grind แล้ว Clear ต่อ

### Config MapsByLevel
```
Lv1 SchoolGrounds → Lv15 FlowerForest → Lv30 Dressrosa → Lv45 FairyKingForest → Lv60 KingsTomb
```
(MinLevel เป็นเกณฑ์เสริม — ปลดจริงหลักคือ progression ของเกม)

## 6f. Auto Equip — ไอเทมเสริม/อาวุธที่ดีที่สุด → ยูนิตแข็งสุดไล่ทั้งทีม (`src/AutoEquip.lua`)

### ปัญหา: decompile ไม่ระบุ node สำหรับ equip item
- `PlayerData` มี `.ItemData` (consumable = `{[name]={Amount=n}}`) และ `.EquipmentData` (ยืนยันใน §2) แต่ **ตาราง Nodes ที่ decompile ไว้ (§4) ไม่มี node ชื่อ equip-item** (มีแค่ `UNIT_LOAD_TEAM(idx, withEquipment)` = โหลดทีมพร้อม equipment ที่ save ไว้)
- แก้ด้วย **auto-discovery ตอนรันจริง** (Nodes เป็น table หลัง require → iterate ได้):
  - **container**: peek `PlayerData` แล้วหา key แรกที่เป็น table ของ entry ที่มี `.Asset`/`.Name` — ลองตามลำดับ `EquipmentData, RelicData, GearData, AccessoryData, TrinketData, ArtifactData, WeaponData, ...` (ItemData ถูกกรองออกเองเพราะไม่มี `.Asset`)
  - **node**: สแกน `Nodes` หา key ที่มี `EQUIP` + คำใบ้ item (`ITEM/RELIC/GEAR/ACCESSOR/TRINKET/ARTIFACT/WEAPON/EQUIPMENT/...`) ตัด `UNIT_EQUIP`/`UNIT_UNEQUIP_ALL`/`*LOAD_TEAM` ออก แล้วให้คะแนน `EQUIPMENT>ITEM>RELIC/GEAR>...`

### Flow
1. rank equipment ในกระเป๋า (rarity → level/enhance → worthiness) ดีสุดก่อน
2. rank ยูนิตในทีม (rarity → level → worthiness) แข็งสุดก่อน
3. จ่าย item ดีสุด `ItemsPerUnit` ชิ้น/ยูนิต ไล่จากยูนิตแข็งสุด → ครบทั้งทีม (item ที่ติดถูกตัวอยู่แล้ว = ข้าม)
4. ยิงผ่าน `Actions.EquipEquipment(...)` (หลัก) / fallback `Nodes.EQUIPMENT_EQUIP:FireServer(...)` ตาม `ArgOrder`

### API จริง (ยืนยันจาก decompile `expidition_lobby.rbxlx`)
- **equip**: `Actions.EquipEquipment(equipmentId, unitId, slotIndex)` → `Nodes.EQUIPMENT_EQUIP:FireServer(equipmentId, unitId, slotIndex)` (บรรทัด 437587, 1791706)
- **container**: `PlayerData.EquipmentData` — entry `{ Asset="Kunai", Stats={...}, ... }` keyed by equipmentId
- **ยูนิตอ้าง equipment**: `UnitData[unitId].Equipment = { ["1"] = equipmentId }` → `buildEquippedMap()` map equipmentId→unitId (ใช้เช็ค "ติดตัวไหนอยู่")
- **ArgOrder default = `item_unit_slot`** = `(equipmentId, unitId, slotIndex)` ← ลำดับจริง (เดิมตั้ง `unit_item` = สลับ+ขาด slot → kunai ไม่ติด, แก้แล้ว)

### ความปลอดภัย
- ถ้า discover ไม่เจอ action/container → **ไม่ยิง remote มั่ว** แค่ log บอกให้รัน `AEKaitun.DumpEquip()`
- ยิงเฉพาะ node ที่ชื่อ match equipment เท่านั้น (ไม่แตะ remote อื่น)

### เรียกใช้
- อัตโนมัติ: `init.lua` (หลัง summon/claim/sell ตอนเข้า lobby) + ท้าย `SmartPlay.runRecovery`
- Debug/ตั้งค่าเอง: `AEKaitun.DumpEquip()` (พิมพ์ชื่อ node/คีย์/ตัวอย่าง entry จริง), `AEKaitun.AutoEquip()`
- override ใน Config: `["Auto Equip"] = { EquipAction="EquipEquipment", ContainerKey="EquipmentData", ArgOrder="item_unit_slot", ItemsPerUnit=... }`

## 6g. Placement strategy (`PlacementEngine.lua` + `InGame.lua`)

**สำคัญ (แก้บั๊กใหญ่ 2026-07):** `PlacementEngine.lua` เคยถูก rewrite เป็นเวอร์ชันย่อที่ใช้ API ผิด (`workspace:FindFirstChild("GroundPlacement"/"Path"/"Enemies")` แทน `CollectionService:GetTagged` / `Dependencies.MapState.Paths` / `Dependencies.GameEnemies`, `canPlaceAt` คืน `true` เสมอ, และ **ขาด `getThreatEnemies`** ทั้งที่ `InGame.lua` import+เรียกอยู่ → `attempt to call a nil value` ทุกครั้งที่วาง = วางไม่ได้เลย). แก้แล้วโดย **port geometry ทั้งชุดจาก `Kaitun.lua` ของจริง** กลับเข้ามา:
- `getPlaceableParts(asset)` = `CollectionService:GetTagged("GroundPlacement"/"HillPlacement")` ตาม `Information:GetAsset(asset).PlacementType`
- `getPathPoints` / `getPathEndPositions` = `Dependencies.MapState.Paths` (fallback tag `"Path"`)
- `getEnemyPositions` = `Dependencies.GameEnemies` (fallback `workspace.Enemies`)
- `canPlaceAt` = `Actions.IsPlacementAllowed` ก่อน → fallback Blockcast จริง (เช็ค tag + ชนยูนิตผ่าน `Nodes.GET_ALL_UNIT_MODELS:InvokeSelf()`)
- `getTotalPlacementCap` = Fallback(per-player Total → Global) คืน `nil` ถ้าอ่านไม่ได้ (ไม่บล็อกด้วยเลขปลอม)

**strategy ปัจจุบัน (2026-07 อัปเดต): วางตามจุดที่ศัตรูเดินผ่าน — เลิกวางดักหน้าฐาน**
- `buildAAStylePlaceCFrames` = หว่าน seed รอบ**มอนทุกตัวที่กำลังเดิน** (cap 8 anchor) → snap ground → เลือกจุดที่ **ชิดเส้นทาง (path) ที่สุด** (`distToNearestPath`) → dedup `minSep=4` → เอา top `count`. ไม่มีมอน → คืน `{}`
- `scorePlacePosition(pos,e,pp,pe)` = ระยะถึง path ที่ใกล้สุด (ยิ่งชิดยิ่งดี) — **ไม่เจาะจง frontmost/มอนใกล้ฐาน** อีกต่อไป
- `getThreatEnemies`/`getFrontmostEnemy` ยัง export ไว้ (ใช้แค่ปรับ TTL cache ใน `InGame.getPoints`) แต่ไม่ใช้ชี้จุดวางแล้ว
- เรียงช่องด้วย `getAffordableSlotsOrdered` (**Magical ก่อน → แพง → ถูก**) — ไม่มีเฟส econ/cluster/anchor/coverage

**Magical detection (แก้ 2026-07):** `Archetype` อยู่ระดับ **top-level ของ unit info** (ไม่ใช่ใน `UpgradeStats`)
- `getAssetInfo(asset)` = ลอง `Dependencies.Information:GetAsset` → `getCachedInformation():GetAsset` → `UnitUtils:GetUnitInfo` (= `Information:GetAsset`)
- `getUnitArchetype(asset)` = `info.Archetype or info.DamageType or info.Type` ; `isMagicalUnit` = `== "Magical"` (cache)
- debug: `getAffordableSlotsOrdered` print `SlotOrder` (asset/cost/arche/magic/ลำดับ) ทุก ~8 วิ + `AEKaitun.DumpUnitType("<asset>")`

**Smart Targeting (ใหม่ 2026-07):** ทุก unit เลือกเป้า Boss ถ้ามีบอส ไม่งั้น Closest
- `PlacementEngine.isBossPresent()` = `Nodes.GET_ENEMY_INFOS:InvokeSelf(models)` → enemy `Info.Type` มี `"Boss"` (fallback ชื่อโมเดล)
- `InGame.manageUnitTargeting()` = วน `GameUnits[modelInstance]` → `peek().ID` + `.TargetPriority` → ยิง `replica:FireServer("ChangeGameUnitPriority", gameUnitId, priority)` เฉพาะตัวที่ไม่ตรง (กัน Please wait)
- loop ทุก `Targeting Interval` (1.5 วิ) ตอนอยู่ในแมตช์ ; reset cache ตอนออก

Config:
```lua
["Place Magical First"] = true
["Smart Placement"] = { Enabled=true, CarryFirst=true }
["Smart Targeting"] = true
["Targeting Boss Priority"] = "Boss"
["Targeting Default Priority"] = "Closest"
["Targeting Interval"] = 1.5
```

## 7. จุดที่ยังเป็นข้อสังเกต (ความเสี่ยงต่ำ ไม่ได้แก้เพราะมี fallback ครอบอยู่แล้ว)

- `StarterUnit.lua` ยิง `CHOOSE_STARTER_UNIT:FireServer(asset)` ตรงๆ โดยไม่รอ `Nodes.PROMPT_CHOOSE_STARTER_UNIT:Connect` ก่อน (เกมจริงยิง prompt นี้ให้ UI แสดงตัวเลือกก่อน) — ถ้าเซิร์ฟเวอร์เช็คแค่ "ผู้เล่นยังไม่มียูนิต" ก็ยิงตรงได้ปกติ (ตามที่ออกแบบไว้เดิม) แต่ถ้าเซิร์ฟเวอร์บังคับต้องมี prompt state ก่อนอาจถูกเซิร์ฟเวอร์เมิน — ให้สังเกตว่าไอดีใหม่ได้ยูนิตจริงไหมหลังรันสคริปต์ ถ้าไม่ได้ให้แจ้งกลับมาแก้เพิ่ม (ต่อ `Nodes.PROMPT_CHOOSE_STARTER_UNIT:Connect` ก่อนยิง)
