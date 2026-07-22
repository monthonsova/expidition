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
-- Scan Mythic & Secret Units that CAN be Evolved & are NOT Yet Evolved
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
                local hasRecipe = false
                local isAlreadyEvolved = false

                pcall(function()
                    if Evolutions then
                        if Evolutions.GetEvolvedUnit then
                            local target = Evolutions:GetEvolvedUnit(unit.Asset)
                            if target and target ~= "" then
                                hasRecipe = true
                            end
                        end
                        if Evolutions.GetRecipe and Evolutions:GetRecipe(unit.Asset) ~= nil then
                            hasRecipe = true
                        end
                        if Evolutions.GetUnevolvedUnit and Evolutions:GetUnevolvedUnit(unit.Asset) ~= nil then
                            isAlreadyEvolved = true
                        end
                    end
                end)

                if tostring(unit.Asset):find("Evolved") or unit.Evolved == true then
                    isAlreadyEvolved = true
                end

                -- Fallback: If unit is Mythic/Secret and not marked evolved, assume evolvable
                if not isAlreadyEvolved then
                    hasRecipe = true
                end

                if hasRecipe and not isAlreadyEvolved then
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
-- Targeted Challenge Selection & Matchmaking for Missing Materials
-- ------------------------------------------------------------------------
local function findChallengeStageDroppingItem(missingItemName)
    if not missingItemName or missingItemName == "" then
        return nil, nil
    end

    local targetType, targetIndex = nil, nil

    pcall(function()
        local challengeData = peek(Dependencies.ChallengeData)
        if typeof(challengeData) == "table" then
            for cType, stages in pairs(challengeData) do
                if typeof(stages) == "table" then
                    for idx, stage in pairs(stages) do
                        if typeof(stage) == "table" then
                            local rewards = stage.Rewards or stage.Drops or stage.Items
                            if typeof(rewards) == "table" then
                                for _, r in pairs(rewards) do
                                    local rName = typeof(r) == "table" and (r.Asset or r.Item or r.Name) or tostring(r)
                                    if rName == missingItemName then
                                        targetType = tostring(cType)
                                        targetIndex = tonumber(idx) or 1
                                        return
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end)

    return targetType, targetIndex
end

local function startChallengeMatchmaking(missingItemName)
    if _G.Settings["Auto Farm Challenge For Evolution"] == false then
        return false
    end

    if isInGame() then return false end

    -- 1. Try finding a specific Challenge stage that drops the requested item
    local targetType, targetIndex = findChallengeStageDroppingItem(missingItemName)

    if targetType and targetIndex then
        print(("[AE Kaitun AutoEvolve] Target Challenge Found for %s -> Type=%s Index=%d"):format(
            tostring(missingItemName), targetType, targetIndex
        ))
    else
        -- 2. Fallback: If no stage currently shows the drop, cycle/randomly select available Challenge stages
        targetType = _G.Settings["Challenge Mode Type"] or "Regular"
        targetIndex = math.random(1, 3)
        print(("[AE Kaitun AutoEvolve] No specific stage drops %s in current view -> Cycling Challenge Type=%s Index=%d"):format(
            tostring(missingItemName), targetType, targetIndex
        ))
    end

    local matchTable = {
        Gamemode = "Challenge",
        ChallengeType = targetType,
        ChallengeIndex = targetIndex,
        Difficulty = "Normal",
    }

    local ok = pcall(function()
        if Nodes.REQUEST_ENTER_MATCHMAKING then
            return Nodes.REQUEST_ENTER_MATCHMAKING:Request(matchTable)
        end
        if Core.Actions and Core.Actions.StartMatchmaking then
            return Core.Actions.StartMatchmaking(matchTable)
        end
    end)

    print(("[AE Kaitun AutoEvolve] Challenge Matchmaking Request Sent (Ok=%s)"):format(tostring(ok)))
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
        print("[AE Kaitun AutoEvolve] No unevolved Mythic/Secret units in inventory.")
        return
    end

    print(("[AE Kaitun AutoEvolve] Found %d unevolved Mythic/Secret unit(s)"):format(#targets))

    for _, entry in ipairs(targets) do
        if isInGame() then break end

        local reqs = checkEvolutionRequirements(entry.Asset)
        local allMet = true
        local firstMissingItem = nil

        if #reqs > 0 then
            for _, req in ipairs(reqs) do
                if req.Missing > 0 then
                    allMet = false
                    if not firstMissingItem then
                        firstMissingItem = req.Asset
                    end
                    print(("[AE Kaitun AutoEvolve] %s needs %s (%d/%d, missing %d)"):format(
                        entry.Asset, req.Asset, req.Have, req.Required, req.Missing
                    ))
                end
            end
        else
            -- If recipe requirements list is empty (e.g. general evolution requirement), assign default missing item
            allMet = false
            firstMissingItem = "EvolveItem"
        end

        if allMet then
            -- Requirements met -> Evolve now!
            tryEvolveUnit(entry.ID, entry.Asset, entry.TargetEvolved)
        else
            -- Try Quick Crafting missing ingredients first
            local crafted = quickCraftIngredients(reqs)
            if crafted then
                task.wait(1.5)
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
            print(("[AE Kaitun AutoEvolve] Missing material (%s) for %s -> Entering Challenge Matchmaking"):format(
                tostring(firstMissingItem), entry.Asset
            ))
            startChallengeMatchmaking(firstMissingItem)
            break
        end
    end
end

-- Export helper functions
AutoEvolve.getUnEvolvedMythicsAndSecrets = getUnEvolvedMythicsAndSecrets
AutoEvolve.checkEvolutionRequirements = checkEvolutionRequirements
AutoEvolve.tryEvolveUnit = tryEvolveUnit
AutoEvolve.findChallengeStageDroppingItem = findChallengeStageDroppingItem
AutoEvolve.startChallengeMatchmaking = startChallengeMatchmaking
AutoEvolve.runAutoEvolveLoop = runAutoEvolveLoop

return AutoEvolve
