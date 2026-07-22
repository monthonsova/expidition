-- AE Kaitun - Auto Evolve, Quick Craft & Challenge Farming Module

local AutoEvolve = {}

local Core = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Core.lua") or loadstring(readfile("expidition/src/Core.lua"))()
local Replicas = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Replicas.lua") or loadstring(readfile("expidition/src/Replicas.lua"))()
local Utils = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Utils.lua") or loadstring(readfile("expidition/src/Utils.lua"))()

local Nodes = Core.Nodes
local Dependencies = Core.Dependencies
local peek = Core.peek
local getCachedInformation = Utils.getCachedInformation

local isInGame = Replicas.isInGame
local getPlayerData = Replicas.getPlayerData

-- ------------------------------------------------------------------------
-- Helper Functions
-- ------------------------------------------------------------------------
local function getItemAmount(itemName)
    local data = peek(Dependencies.PlayerData)
    if typeof(data) ~= "table" then
        data = getPlayerData()
    end
    local items = data and data.ItemData
    if typeof(items) ~= "table" then
        return 0
    end
    local entry = items[itemName]
    if typeof(entry) == "table" then
        return tonumber(entry.Amount) or 0
    end
    return tonumber(entry) or 0
end

local function getAssetRarity(asset)
    if not asset then return nil end
    local rarity = nil
    pcall(function()
        local Information = getCachedInformation()
        if Information then
            rarity = Information:GetAssetRarity(asset)
        end
    end)
    return rarity
end

-- ------------------------------------------------------------------------
-- Scan Mythic & Secret Units that are NOT yet Evolved
-- ------------------------------------------------------------------------
local function getUnEvolvedMythicsAndSecrets()
    local targets = {}
    local data = getPlayerData()
    local unitData = data and data.UnitData
    if typeof(unitData) ~= "table" then
        return targets
    end

    local Information = getCachedInformation()
    local Evolutions = Information and Information.Evolutions

    for id, unit in pairs(unitData) do
        if typeof(unit) == "table" and unit.Asset then
            local rarity = getAssetRarity(unit.Asset)
            if rarity == "Mythic" or rarity == "Secret" then
                local isEvolved = false
                pcall(function()
                    if Evolutions and Evolutions.IsEvolvedUnit then
                        isEvolved = Evolutions:IsEvolvedUnit(unit.Asset)
                    end
                end)

                if not isEvolved and unit.Evolved ~= true then
                    local targetEvolved = nil
                    pcall(function()
                        if Evolutions and Evolutions.GetEvolvedUnit then
                            targetEvolved = Evolutions:GetEvolvedUnit(unit.Asset)
                        end
                    end)

                    table.insert(targets, {
                        ID = id,
                        Asset = unit.Asset,
                        TargetEvolved = targetEvolved or (unit.Asset .. "Evolved"),
                        Rarity = rarity,
                    })
                end
            end
        end
    end

    return targets
end

-- ------------------------------------------------------------------------
-- Check Recipe Requirements & Inventory
-- ------------------------------------------------------------------------
local function checkEvolutionRequirements(unevolvedAsset)
    local requirements = {}
    local Information = getCachedInformation()
    local Evolutions = Information and Information.Evolutions

    pcall(function()
        if Evolutions then
            local recipe = nil
            if Evolutions.GetEvolvedRecipe then
                recipe = Evolutions:GetEvolvedRecipe(unevolvedAsset)
            elseif Evolutions.GetRecipe then
                recipe = Evolutions:GetRecipe(unevolvedAsset)
            end

            if typeof(recipe) == "table" and typeof(recipe.Requirements) == "table" then
                for _, req in ipairs(recipe.Requirements) do
                    if typeof(req) == "table" and req.Asset then
                        local reqAmount = tonumber(req.Amount) or 1
                        local haveAmount = getItemAmount(req.Asset)
                        table.insert(requirements, {
                            Asset = req.Asset,
                            Required = reqAmount,
                            Have = haveAmount,
                            Missing = math.max(0, reqAmount - haveAmount),
                        })
                    end
                end
            end
        end
    end)

    return requirements
end

-- ------------------------------------------------------------------------
-- Quick Craft Missing Ingredients
-- ------------------------------------------------------------------------
local function quickCraftIngredients(requirements)
    if _G.Settings["Auto Quick Craft Ingredients"] == false then
        return false
    end

    local craftedAny = false
    for _, req in ipairs(requirements) do
        if req.Missing > 0 then
            local craftOk = pcall(function()
                print(("[AE Kaitun AutoEvolve] Quick Crafting %dx %s..."):format(req.Missing, req.Asset))
                Nodes.REQUEST_CRAFT_CRAFTING_RECIPE:FireServer("Crafting", req.Asset, req.Missing)
            end)
            if craftOk then
                craftedAny = true
                task.wait(1)
            end
        end
    end
    return craftedAny
end

-- ------------------------------------------------------------------------
-- Challenge Matchmaking for Missing Materials
-- ------------------------------------------------------------------------
local function startChallengeMatchmaking()
    if _G.Settings["Auto Farm Challenge For Evolution"] == false then
        return false
    end

    if isInGame() then return false end

    print("[AE Kaitun AutoEvolve] Starting Challenge Mode Matchmaking...")
    local ok = pcall(function()
        Nodes.REQUEST_ENTER_MATCHMAKING:Request({
            Gamemode = "Challenge",
            ChallengeType = _G.Settings["Challenge Mode Type"] or "Regular",
            ChallengeIndex = tonumber(_G.Settings["Challenge Mode Index"]) or 1,
            Difficulty = "Normal",
        })
    end)
    return ok
end

-- ------------------------------------------------------------------------
-- Execute Evolution Node Call
-- ------------------------------------------------------------------------
local function tryEvolveUnit(unitId, unevolvedAsset, targetEvolvedAsset)
    print(("[AE Kaitun AutoEvolve] Attempting to Evolve %s (ID: %s) -> %s"):format(
        tostring(unevolvedAsset), tostring(unitId), tostring(targetEvolvedAsset)
    ))

    local ok, res = pcall(function()
        local req = Nodes.TRY_EVOLVING_UNIT:Request(unitId, unevolvedAsset)
        if req and req.Wait then
            return req:Wait()
        end
        return true
    end)

    if ok then
        print(("[AE Kaitun AutoEvolve] Successfully Evolved %s!"):format(tostring(unevolvedAsset)))
        task.wait(2)
        return true
    else
        warn("[AE Kaitun AutoEvolve] Evolve failed:", res)
        return false
    end
end

-- ------------------------------------------------------------------------
-- Main Auto-Evolve Loop (Run in Lobby)
-- ------------------------------------------------------------------------
local function runAutoEvolveLoop()
    if _G.Settings["Auto Evolve Mythic/Secret"] == false then
        return
    end

    if isInGame() then
        return
    end

    local targets = getUnEvolvedMythicsAndSecrets()
    if #targets == 0 then
        return
    end

    print(("[AE Kaitun AutoEvolve] Found %d unevolved Mythic/Secret unit(s)"):format(#targets))

    for _, entry in ipairs(targets) do
        if isInGame() then break end

        local reqs = checkEvolutionRequirements(entry.Asset)
        local allMet = true
        local hasMissing = false

        if #reqs > 0 then
            for _, req in ipairs(reqs) do
                if req.Missing > 0 then
                    allMet = false
                    hasMissing = true
                    print(("[AE Kaitun AutoEvolve] %s needs %s (%d/%d, missing %d)"):format(
                        entry.Asset, req.Asset, req.Have, req.Required, req.Missing
                    ))
                end
            end
        end

        if allMet then
            -- Requirements met -> Evolve now!
            tryEvolveUnit(entry.ID, entry.Asset, entry.TargetEvolved)
        else
            -- Try Quick Crafting missing ingredients first
            local crafted = quickCraftIngredients(reqs)
            if crafted then
                task.wait(1.5)
                -- Re-check requirements after crafting
                local reqsAfter = checkEvolutionRequirements(entry.Asset)
                local nowMet = true
                for _, r in ipairs(reqsAfter) do
                    if r.Missing > 0 then nowMet = false end
                end
                if nowMet then
                    tryEvolveUnit(entry.ID, entry.Asset, entry.TargetEvolved)
                    continue
                end
            end

            -- If materials still missing -> Queue Challenge mode to farm materials
            if hasMissing then
                startChallengeMatchmaking()
                break
            end
        end
    end
end

-- Export helper functions
AutoEvolve.getUnEvolvedMythicsAndSecrets = getUnEvolvedMythicsAndSecrets
AutoEvolve.checkEvolutionRequirements = checkEvolutionRequirements
AutoEvolve.tryEvolveUnit = tryEvolveUnit
AutoEvolve.startChallengeMatchmaking = startChallengeMatchmaking
AutoEvolve.runAutoEvolveLoop = runAutoEvolveLoop

return AutoEvolve
