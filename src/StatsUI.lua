-- --     AE Kaitun — Stats UI Module

local StatsUI = {}
local Core = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Core.lua") or loadstring(readfile("expidition/src/Core.lua"))()
local Summon = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Summon.lua") or loadstring(readfile("expidition/src/Summon.lua"))()

local LocalPlayer = Core.LocalPlayer

local getItemAmount = Summon.getItemAmount
local countUnitsByRarity = Summon.countUnitsByRarity
local getBannerMythicNames = Summon.getBannerMythicNames

local statsUiBuilt = false

local function getStatsSnapshot()
    return {
        gems = getItemAmount("Gem"),
        mythic = countUnitsByRarity("Mythic"),
        traitReroll = getItemAmount("TraitReroll"),
        legendary = countUnitsByRarity("Legendary"),
    }
end

-- Banner Mythic รอบปัจจุบัน (Standard หมุนตามเวลา)

local function createStatsUI()
    if not _G.Settings["Show Stats UI"] or statsUiBuilt then
        return
    end
    statsUiBuilt = true

    local pg = LocalPlayer:WaitForChild("PlayerGui")
    local old = pg:FindFirstChild("AEKaitunStats")
    if old then
        old:Destroy()
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "AEKaitunStats"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.IgnoreGuiInset = true
    gui.Parent = pg

    local card = Instance.new("Frame")
    card.Name = "Card"
    card.AnchorPoint = Vector2.new(1, 0)
    card.Position = UDim2.new(1, -16, 0, 72)
    card.Size = UDim2.fromOffset(230, 168)
    card.BackgroundColor3 = Color3.fromRGB(28, 32, 36)
    card.BackgroundTransparency = 0.18
    card.BorderSizePixel = 0
    card.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = card

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(70, 78, 86)
    stroke.Thickness = 1
    stroke.Transparency = 0.35
    stroke.Parent = card

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 10)
    pad.PaddingBottom = UDim.new(0, 10)
    pad.PaddingLeft = UDim.new(0, 12)
    pad.PaddingRight = UDim.new(0, 12)
    pad.Parent = card

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Size = UDim2.new(1, 0, 0, 18)
    title.Font = Enum.Font.GothamMedium
    title.TextSize = 13
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextColor3 = Color3.fromRGB(180, 190, 200)
    title.Text = "AE Kaitun"
    title.Parent = card

    local function makeRow(order, labelText)
        local row = Instance.new("Frame")
        row.BackgroundTransparency = 1
        row.Size = UDim2.new(1, 0, 0, 22)
        row.Position = UDim2.fromOffset(0, 22 + (order - 1) * 24)
        row.Parent = card

        local lab = Instance.new("TextLabel")
        lab.BackgroundTransparency = 1
        lab.Size = UDim2.new(0.5, 0, 1, 0)
        lab.Font = Enum.Font.Gotham
        lab.TextSize = 13
        lab.TextXAlignment = Enum.TextXAlignment.Left
        lab.TextColor3 = Color3.fromRGB(160, 168, 176)
        lab.Text = labelText
        lab.Parent = row

        local val = Instance.new("TextLabel")
        val.Name = "Value"
        val.BackgroundTransparency = 1
        val.Size = UDim2.new(0.5, 0, 1, 0)
        val.Position = UDim2.new(0.5, 0, 0, 0)
        val.Font = Enum.Font.GothamBold
        val.TextSize = 14
        val.TextXAlignment = Enum.TextXAlignment.Right
        val.TextColor3 = Color3.fromRGB(245, 248, 250)
        val.Text = "—"
        val.Parent = row
        return val
    end

    local gemVal = makeRow(1, "ALL GEM")
    gemVal.TextColor3 = Color3.fromRGB(120, 210, 255)
    local mythicVal = makeRow(2, "Mythic bag")
    mythicVal.TextColor3 = Color3.fromRGB(255, 170, 90)
    local traitVal = makeRow(3, "Trait Reroll")
    traitVal.TextColor3 = Color3.fromRGB(190, 160, 255)

    -- ชื่อ Mythic ในแบนเนอร์ (แค่ชื่อ)
    local bannerLab = Instance.new("TextLabel")
    bannerLab.BackgroundTransparency = 1
    bannerLab.Size = UDim2.new(1, 0, 0, 16)
    bannerLab.Position = UDim2.fromOffset(0, 98)
    bannerLab.Font = Enum.Font.Gotham
    bannerLab.TextSize = 12
    bannerLab.TextXAlignment = Enum.TextXAlignment.Left
    bannerLab.TextColor3 = Color3.fromRGB(160, 168, 176)
    bannerLab.Text = "Banner Mythic"
    bannerLab.Parent = card

    local bannerNames = Instance.new("TextLabel")
    bannerNames.Name = "BannerMythicNames"
    bannerNames.BackgroundTransparency = 1
    bannerNames.Size = UDim2.new(1, 0, 0, 36)
    bannerNames.Position = UDim2.fromOffset(0, 114)
    bannerNames.Font = Enum.Font.GothamBold
    bannerNames.TextSize = 13
    bannerNames.TextXAlignment = Enum.TextXAlignment.Left
    bannerNames.TextYAlignment = Enum.TextYAlignment.Top
    bannerNames.TextWrapped = true
    bannerNames.TextColor3 = Color3.fromRGB(255, 200, 120)
    bannerNames.Text = "—"
    bannerNames.Parent = card

    local function fmt(n)
        n = tonumber(n) or 0
        if n >= 1000000 then
            return string.format("%.1fM", n / 1000000)
        end
        if n >= 10000 then
            return string.format("%.1fK", n / 1000)
        end
        return tostring(math.floor(n))
    end

    task.spawn(function()
        while gui.Parent do
            local ok, snap = pcall(getStatsSnapshot)
            if ok and typeof(snap) == "table" then
                gemVal.Text = fmt(snap.gems)
                mythicVal.Text = tostring(snap.mythic or 0)
                traitVal.Text = fmt(snap.traitReroll)
            end
            local okN, names = pcall(getBannerMythicNames)
            if okN and typeof(names) == "table" and #names > 0 then
                bannerNames.Text = table.concat(names, ", ")
            else
                bannerNames.Text = "—"
            end
            task.wait(1.25)
        end
    end)

    print("[AE Kaitun] Stats UI = on (Gem / Mythic / Trait / Banner Mythic)")
end



StatsUI.getStatsSnapshot = getStatsSnapshot
StatsUI.createStatsUI = createStatsUI

return StatsUI
