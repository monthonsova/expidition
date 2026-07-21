<<<<<<< HEAD
-- AE Kaitun — Anti-AFK, Auto-Rejoin & Duplicate Execution Guard
=======
-- AE Kaitun - Anti-AFK, Auto-Rejoin & Duplicate Execution Guard
>>>>>>> f7875d3661c03c148688ef24d741a13f568c24be

local AntiAFK = {}

local Services = {
    Players = game:GetService("Players"),
    VirtualUser = game:GetService("VirtualUser"),
    TeleportService = game:GetService("TeleportService"),
    GuiService = game:GetService("GuiService"),
    CoreGui = game:GetService("CoreGui"),
}

local function getLocalPlayer()
    local player = Services.Players.LocalPlayer
    if not player then
        pcall(function()
            player = Services.Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
        end)
    end
    return player or Services.Players.LocalPlayer
end

local LOBBY_PLACE_ID = 84515722934860

-- ------------------------------------------------------------------------
-- 1. Anti-AFK System (VirtualUser + Loop Nudge)
-- ------------------------------------------------------------------------
local function setupAntiAFK()
    local player = getLocalPlayer()
    if player then
        pcall(function()
            player.Idled:Connect(function()
                pcall(function()
                    Services.VirtualUser:CaptureController()
                    Services.VirtualUser:ClickButton2(Vector2.new(0, 0))
                end)
                print("[AE Kaitun Anti-AFK] Prevented 20-min idle kick!")
            end)
        end)
    end

    -- Signal 2: Periodic background click nudge every 120 seconds
    task.spawn(function()
        while true do
            task.wait(120)
            pcall(function()
                local camCF = workspace.CurrentCamera and workspace.CurrentCamera.CFrame or CFrame.new()
                Services.VirtualUser:CaptureController()
                Services.VirtualUser:Button2Down(Vector2.new(0, 0), camCF)
                task.wait(0.1)
                Services.VirtualUser:Button2Up(Vector2.new(0, 0), camCF)
            end)
        end
    end)
    print("[AE Kaitun Anti-AFK] System active.")
end

-- ------------------------------------------------------------------------
-- 2. Auto-Rejoin System (Disconnect / Kick / Error Recovery)
-- ------------------------------------------------------------------------
local isRejoining = false

local function triggerRejoin(reason)
    if isRejoining then return end
    isRejoining = true
    warn("[AE Kaitun Auto-Rejoin] Triggered rejoin due to: " .. tostring(reason))

    local player = getLocalPlayer()
    while true do
        pcall(function()
            if player then
                Services.TeleportService:Teleport(LOBBY_PLACE_ID, player)
            else
                Services.TeleportService:Teleport(LOBBY_PLACE_ID)
            end
        end)
        task.wait(5)
    end
end

local function setupAutoRejoin()
    -- Event 1: GuiService ErrorMessageChanged
    pcall(function()
        Services.GuiService.ErrorMessageChanged:Connect(function(msg)
            if msg and msg ~= "" then
                triggerRejoin("ErrorMessageChanged: " .. tostring(msg))
            end
        end)
    end)

    -- Event 2: TeleportInitFailed error handling
    pcall(function()
        Services.TeleportService.TeleportInitFailed:Connect(function(player, result, err)
            triggerRejoin("TeleportInitFailed: " .. tostring(err))
        end)
    end)

    -- Event 3: Monitor CoreGui promptOverlay for disconnect dialogs
    task.spawn(function()
        while true do
            task.wait(3)
            pcall(function()
                local promptOverlay = Services.CoreGui:FindFirstChild("RobloxPromptGui")
                    and Services.CoreGui.RobloxPromptGui:FindFirstChild("promptOverlay")
                if promptOverlay then
                    local errorPrompt = promptOverlay:FindFirstChild("ErrorPrompt")
                    if errorPrompt and errorPrompt.Visible then
                        triggerRejoin("ErrorPrompt Dialog Visible")
                    end
                end
            end)
        end
    end)
    print("[AE Kaitun Auto-Rejoin] Monitor active.")
end

-- ------------------------------------------------------------------------
-- 3. Queue On Teleport Persistence (In-memory Teleport Persistence)
-- ------------------------------------------------------------------------
local function setupQueueOnTeleport(baseUrl)
    pcall(function()
        local queueFunc = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
        if queueFunc then
            local scriptString = string.format([[
                if not getgenv()._AEKaitunLoaded then
                    _G.AEKaitun_BaseUrl = "%s"
                    loadstring(game:HttpGet(_G.AEKaitun_BaseUrl .. "init.lua"))()
                end
            ]], baseUrl or "https://raw.githubusercontent.com/monthonsova/expidition/main/")
            queueFunc(scriptString)
            print("[AE Kaitun] queue_on_teleport registered for next teleport.")
        end
    end)
end

AntiAFK.setupAntiAFK = setupAntiAFK
AntiAFK.setupAutoRejoin = setupAutoRejoin
AntiAFK.triggerRejoin = triggerRejoin
AntiAFK.setupQueueOnTeleport = setupQueueOnTeleport

return AntiAFK
