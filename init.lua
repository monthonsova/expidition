-- AE Kaitun — Anime Expeditions Modular Loader
-- PlaceId: 84515722934860

-- ------------------------------------------------------------------------
-- Game Validation Protection (Wrong Game Guard for All Gamemodes)
-- ------------------------------------------------------------------------
local ANIME_EXPEDITIONS_LOBBY_ID = 84515722934860

local function isAnimeExpeditionsGame()
    -- 1. Lobby PlaceId check
    if game.PlaceId == ANIME_EXPEDITIONS_LOBBY_ID then
        return true
    end
    -- 2. Check ReplicatedStorage structure (Story / Challenge / Event / Raid / Infinite)
    local replicatedStorage = game:GetService("ReplicatedStorage")
    if replicatedStorage:FindFirstChild("Nodes")
       or replicatedStorage:FindFirstChild("Replica")
       or replicatedStorage:FindFirstChild("Information")
       or replicatedStorage:FindFirstChild("UnitUtils") then
        return true
    end
    -- 3. Check workspace markers in match
    if workspace:FindFirstChild("GroundPlacement") or workspace:FindFirstChild("HillPlacement") or workspace:FindFirstChild("Map") then
        return true
    end
    return false
end

if not isAnimeExpeditionsGame() then
    warn("[AE Kaitun Error] This script is ONLY for Anime Expeditions! (Current PlaceId: " .. tostring(game.PlaceId) .. ")")
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "AE Kaitun Error",
            Text = "สคริปต์นี้ใช้ได้เฉพาะเกม Anime Expeditions เท่านั้น!",
            Duration = 10,
        })
    end)
    return
end

-- ------------------------------------------------------------------------
-- Duplicate Execution Protection (Anti-Double Execution)
-- ------------------------------------------------------------------------
if getgenv()._AEKaitunLoaded then
    warn("[AE Kaitun] Script is already running! Skipping duplicate execution.")
    return _G.AEKaitun_Loader
end
getgenv()._AEKaitunLoaded = true

local Loader = {
    -- Change BaseUrl to your GitHub repository raw URL when uploaded
    BaseUrl = _G.AEKaitun_BaseUrl or "https://raw.githubusercontent.com/monthonsova/expidition/main/",
    IsLocal = (readfile and isfile and isfile("expidition/Config.lua")) or (readfile and isfile and isfile("Config.lua")) or false,
    LocalPrefix = (readfile and isfile and isfile("expidition/Config.lua")) and "expidition/" or "",
    LoadedModules = {},
}

_G.AEKaitun_Loader = Loader

function Loader.require(modulePath)
    if Loader.LoadedModules[modulePath] then
        return Loader.LoadedModules[modulePath]
    end

    local code = nil
    local localPath = Loader.LocalPrefix .. modulePath

    if Loader.IsLocal and isfile and isfile(localPath) then
        code = readfile(localPath)
    else
        local url = Loader.BaseUrl .. modulePath
        local success, result = pcall(function()
            return game:HttpGet(url)
        end)
        if success and result then
            code = result
        else
            error("[AE Kaitun Loader] Failed to fetch module: " .. tostring(modulePath) .. " from " .. url)
        end
    end

    local fn, err = loadstring(code, modulePath)
    if not fn then
        error("[AE Kaitun Loader] Syntax error in module " .. tostring(modulePath) .. ": " .. tostring(err))
    end

    local moduleResult = fn()
    Loader.LoadedModules[modulePath] = moduleResult
    return moduleResult
end

-- Load Configuration
Loader.require("Config.lua")

-- Load Core ก่อนเสมอ
local Core = Loader.require("src/Core.lua")

-- Load Anti-AFK & Auto-Rejoin Module
local AntiAFK = Loader.require("src/AntiAFK.lua")

-- Load Sub-Modules
local Utils = Loader.require("src/Utils.lua")
local Replicas = Loader.require("src/Replicas.lua")
local AutoFarmManager = Loader.require("src/AutoFarmManager.lua")
local StarterUnit = Loader.require("src/StarterUnit.lua")
local Codes = Loader.require("src/Codes.lua")
local Summon = Loader.require("src/Summon.lua")
local Rewards = Loader.require("src/Rewards.lua")
local Team = Loader.require("src/Team.lua")
local Lobby = Loader.require("src/Lobby.lua")
local PlacementEngine = Loader.require("src/PlacementEngine.lua")
local InGame = Loader.require("src/InGame.lua")
local StatsUI = Loader.require("src/StatsUI.lua")
local SmartPlay = Loader.require("src/SmartPlay.lua")
local FarmLoop = Loader.require("src/FarmLoop.lua")

-- Activate Anti-AFK, Auto-Rejoin, and Queue-On-Teleport Persistence
AntiAFK.setupAntiAFK()
AntiAFK.setupAutoRejoin()
AntiAFK.setupQueueOnTeleport(Loader.BaseUrl)

-- Print Status
print("[AE Kaitun Modular] loaded | PlaceId=", game.PlaceId)

-- Main Execution Thread
task.spawn(function()
    Utils.boostFPS()
    Replicas.getPlayerData()
    StatsUI.createStatsUI()
    task.wait(1)

    -- Units settings (ปิดหมด เปิดแค่ Auto-Upgrade)
    task.spawn(InGame.applyUnitSettings)

    -- เปิดโหวต Start ไว้ตั้งแต่ต้น
    if _G.Settings["Auto Vote Start"] then
        InGame.setupAutoVoteStart()
    end

    if Replicas.isInGame() then
        AutoFarmManager.markFarmEnteredMatch()
        InGame.runInGame()
        if AutoFarmManager.getAutoFarm().Enabled then
            FarmLoop.waitUntilBackToLobby(1800)
            task.wait(2)
            if not Replicas.isInGame() then
                FarmLoop.runStoryFarmLoop()
            end
        end
    else
        print("[AE Kaitun Modular] Lobby → Starter → Codes → Summon → Claim → ขาย → ฟาร์ม")
        StarterUnit.chooseStarterUnit()
        Codes.redeemAllCodes()
        Summon.autoSummonAfterCodes()
        Rewards.claimAllRewards()
        Summon.autoSellBagUnits()
        FarmLoop.runStoryFarmLoop()
    end
end)

-- Export Global Debug & Control API
getgenv().AEKaitun = {
    StartGame = Lobby.startGame,
    ChooseStarter = StarterUnit.chooseStarterUnit,
    RedeemCodes = Codes.redeemAllCodes,
    AutoSummon = Summon.autoSummonAfterCodes,
    Summon = Summon.summonBanner,
    GetBannerMythics = Summon.printBannerMythics,
    GetBannerMythicNames = Summon.getBannerMythicNames,
    GetBannerPool = Summon.getBannerPoolByRarity,
    EquipLegendaries = Team.equipLegendariesToHotbar,
    EnsureMythicTeam = Team.ensureMythicTeam,
    BuildMythicTeam = Team.buildMythicTeam,
    CountLegendaries = Summon.countLegendariesInBag,
    CountUniqueLegendaries = Summon.countUniqueLegendariesInBag,
    CountUniqueMythics = Summon.countUniqueMythicsInBag,
    GetSummonStop = Summon.getSummonStopUniqueLegendary,
    GetSummonStopMythic = Summon.getSummonStopUniqueMythic,
    CountMythics = function()
        return #Summon.getMythicUnitsInBag()
    end,
    GetSummonTeam = Summon.getSummonTeamUnitsInBag,
    EnsureTeam = Team.ensureTeamReady,
    IsInGame = Replicas.isInGame,
    PlaceUnit = InGame.placeUnit,
    AutoPlace = InGame.autoPlaceUnits,
    GetYen = PlacementEngine.getGameYen,
    GetSlotCost = PlacementEngine.getSlotPlacementCost,
    CanAfford = PlacementEngine.canAffordSlot,
    SetupVote = InGame.setupAutoVoteStart,
    SellAll = InGame.sellAllUnits,
    SellBag = Summon.autoSellBagUnits,
    SellBagRarities = Summon.sellBagByRarities,
    GetEquippedCount = Replicas.getEquippedCount,
    BuildQueue = AutoFarmManager.buildQueueData,
    BoostFPS = Utils.boostFPS,
    ApplyUnitSettings = InGame.applyUnitSettings,
    FarmLoop = FarmLoop.runStoryFarmLoop,
    AdvanceFarm = AutoFarmManager.advanceFarmStage,
    GetFarmStage = AutoFarmManager.getCurrentFarmStage,
    ApplyFarm = AutoFarmManager.applyFarmStageToSettings,
    SyncFarm = AutoFarmManager.syncFarmStateFromProgress,
    IsActCleared = AutoFarmManager.isActCleared,
    IsGrindMode = AutoFarmManager.isInGrindMode,
    EnterGrind = function()
        return AutoFarmManager.enterGrindMode("manual")
    end,
    GetGrindStage = AutoFarmManager.getGrindStage,
    GetAutoFarm = AutoFarmManager.getAutoFarm,
    GetActiveMap = AutoFarmManager.getActiveStoryMap,
    GetGrindMap = AutoFarmManager.getGrindMap,
    GetAccountLevel = Replicas.getAccountLevel,
    GetFarmState = AutoFarmManager.getFarmState,
    DebugProgress = AutoFarmManager.debugProgressSnapshot,
    RestartMatch = AutoFarmManager.restartCurrentMatch,
    NextStage = AutoFarmManager.nextStageFromMatch,
    SetupEndScreen = InGame.setupEndScreenHandler,
    StatsUI = StatsUI.createStatsUI,
    GetStats = StatsUI.getStatsSnapshot,
    ClaimRewards = Rewards.claimAllRewards,
    SmartPlay = SmartPlay.runRecovery,
    SmartPlayBag = function()
        return SmartPlay.countUnitBag(), SmartPlay.getUnitBagLimit(), SmartPlay.getBagFreeSlots()
    end,
    RemakeBestTeam = Team.remakeBestTeam,
    Rejoin = AntiAFK.triggerRejoin,
}

return Loader
