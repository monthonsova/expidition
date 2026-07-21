--[[
--     AE Kaitun — Lobby & Matchmaking Module
-- ]]

local Lobby = {}
local Core = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Core.lua") or loadstring(readfile("expidition/src/Core.lua"))()
local Replicas = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Replicas.lua") or loadstring(readfile("expidition/src/Replicas.lua"))()
local AutoFarmManager = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/AutoFarmManager.lua") or loadstring(readfile("expidition/src/AutoFarmManager.lua"))()
local Team = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Team.lua") or loadstring(readfile("expidition/src/Team.lua"))()

local Nodes = Core.Nodes

local isInGame = Replicas.isInGame
local getPartyReplica = Replicas.getPartyReplica
local buildQueueData = AutoFarmManager.buildQueueData
local ensureTeamReady = Team.ensureTeamReady

local function startViaParty(queueData)
    local party = getPartyReplica(2)

    if party then
        print("[AE Kaitun] Party มีอยู่แล้ว → SetQueueData + StartGame")
        party:FireServer("SetQueueData", queueData)
        task.wait(0.3)
        party:FireServer("StartGame")
        return true
    end

    print("[AE Kaitun] สร้าง Party...", queueData and queueData.MapName, queueData and queueData.ActName)
    local req = Nodes.PARTY_CREATE:Request(queueData)
    if req and req.Timeout then
        req:Timeout(8)
    end

    local done = false
    if req and req.Once then
        req:Once(function()
            local p = Nodes.WAIT_FOR_PARTY_REPLICA:InvokeSelf()
            if p then
                print("[AE Kaitun] Party พร้อม → StartGame")
                p:FireServer("StartGame")
                done = true
            end
        end)
    end

    -- fallback: poll
    local t0 = os.clock()
    while not done and os.clock() - t0 < 10 do
        local p = getPartyReplica(1)
        if p then
            p:FireServer("StartGame")
            done = true
            break
        end
        task.wait(0.25)
    end

    return done
end

local function startViaMatchmaking(queueData)
    print("[AE Kaitun] Matchmaking...", queueData and queueData.MapName, queueData and queueData.ActName)
    local ok = Nodes.REQUEST_ENTER_MATCHMAKING:Request(queueData)
    return ok and true or false
end

local function startGame()
    if isInGame() then
        print("[AE Kaitun] อยู่ในแมตช์แล้ว — ข้าม Start")
        return
    end

    if not ensureTeamReady() then
        return
    end

    local queueData = buildQueueData()
    print("[AE Kaitun] QueueData =", queueData.Gamemode, queueData.MapName, queueData.ActName, queueData.Difficulty)

    if _G.Settings["Use Matchmaking"] then
        startViaMatchmaking(queueData)
    else
        startViaParty(queueData)
    end
end



Lobby.startViaParty = startViaParty
Lobby.startViaMatchmaking = startViaMatchmaking
Lobby.startGame = startGame

return Lobby
