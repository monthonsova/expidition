-- [[
    AE Kaitun — Anti-AFK, Auto-Rejoin & Duplicate Execution Guard
]]

local AntiAFK = {}

local Services = {
    Players = game:GetService("Players"),
    VirtualUser = game:GetService("VirtualUser"),
    TeleportService = game:GetService("TeleportService"),
    GuiService = game:GetService("GuiService"),
    CoreGui = game:GetService("CoreGui"),
}

local LocalPlayer = Services.Players.LocalPlayer
local LOBBY_PLACE_ID = 84515722934860

-- ------------------------------------------------------------------------
-- 1. Anti-AFK System (VirtualUser + Loop Nudge)
-- ------------------------------------------------------------------------
local function setupAntiAFK()
    -- Signal 1: Listen to Idled event
    pcall(function()
        LocalPlayer.Idled:Connect(function()
            Services.VirtualUser:CaptureController()
            Services.VirtualUser:ClickButton2(Vector2.new(0, 0))
            print("[AE Kaitun Anti-AFK] Prevented 20-min idle kick!")
        end)
    end)

    -- Signal 2: Periodic background click nudge every 120 seconds
    task.spawn(function()
        while true do
            task.wait(120)
            pcall(function()
                Services.VirtualUser:CaptureController()
                Services.VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
                task.wait(0.1)
                Services.VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
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

    while true do
        pcall(function()
            if game.PlaceId == LOBBY_PLACE_ID then
                Services.TeleportService:Teleport(LOBBY_PLACE_ID, LocalPlayer)
            else
                Services.TeleportService:Teleport(LOBBY_PLACE_ID, LocalPlayer)
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

    -- Event 2: Monitor CoreGui promptOverlay for disconnect dialogs
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
-- 3. Auto-Exec Saver (Saves launcher to autoexec folder if supported)
-- ------------------------------------------------------------------------
local function installAutoExec(baseUrl)
    pcall(function()
        if writefile and isfolder and isfolder("autoexec") then
            local scriptContent = string.format([[
-- AE Kaitun AutoExec Launcher
if not getgenv()._AEKaitunLoaded then
    _G.AEKaitun_BaseUrl = "%s"
    loadstring(game:HttpGet(_G.AEKaitun_BaseUrl .. "init.lua"))()
end
]], baseUrl or "https://raw.githubusercontent.com/monthonsova/expidition/main/")

            writefile("autoexec/AEKaitun_Expedition.lua", scriptContent)
            print("[AE Kaitun] Auto-Exec script saved to autoexec/AEKaitun_Expedition.lua")
        end
    end)
end

AntiAFK.setupAntiAFK = setupAntiAFK
AntiAFK.setupAutoRejoin = setupAutoRejoin
AntiAFK.triggerRejoin = triggerRejoin
AntiAFK.installAutoExec = installAutoExec

return AntiAFK
