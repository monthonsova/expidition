-- [[
--     AE Kaitun — Utils Module
-- ]]

local Utils = {}

local Core = _G.AEKaitun_Loader and _G.AEKaitun_Loader.require("src/Core.lua") or loadstring(readfile("expidition/src/Core.lua"))()

local Services = Core.Services
local LocalPlayer = Core.LocalPlayer
local Workspace = Core.Workspace
local Lighting = Core.Lighting
local Terrain = Core.Terrain
local ReplicatedStorage = Core.ReplicatedStorage

local getCachedUnitUtils = Core.getCachedUnitUtils
local getCachedInformation = Core.getCachedInformation
local peek = Core.peek

------------------------------------------------------------------------
-- Boost FPS (ลบเอฟเฟกต์ + พื้น Plastic ต่ำสุด — ไม่ lock FPS)
------------------------------------------------------------------------
local fpsBoosted = false
local FLAT_FLOOR = Color3.fromRGB(40, 40, 40)
local FLAT_PROP = Color3.fromRGB(25, 25, 25)

local function isUiOrChar(v)
    local p = v
    while p do
        if p:IsA("ScreenGui") or p:IsA("BillboardGui") or p:IsA("SurfaceGui") then
            return true
        end
        if p:IsA("PlayerGui") or p.Name == "PlayerGui" then
            return true
        end
        if LocalPlayer.Character and p == LocalPlayer.Character then
            return true
        end
        p = p.Parent
    end
    return false
end

local function stripVisual(v)
    pcall(function()
        if not v or not v.Parent or isUiOrChar(v) then
            return
        end
        -- เอฟเฟกต์ → ปิดแล้วทำลาย
        if v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Beam") then
            v.Enabled = false
            pcall(function()
                v.Rate = 0
                v.Lifetime = NumberRange.new(0)
            end)
            v:Destroy()
            return
        end
        if v:IsA("Fire") or v:IsA("Smoke") or v:IsA("Sparkles")
            or v:IsA("SpotLight") or v:IsA("PointLight") or v:IsA("SurfaceLight")
            or v:IsA("Highlight")
        then
            v.Enabled = false
            v:Destroy()
            return
        end
        if v:IsA("Explosion") then
            v.BlastPressure = 0
            v.BlastRadius = 0
            v.Visible = false
            return
        end
        -- พื้นผิว / เท็กซ์เจอร์
        if v:IsA("Decal") or v:IsA("Texture") then
            v.Transparency = 1
            v:Destroy()
            return
        end
        if v:IsA("SurfaceAppearance") or v:IsA("MaterialVariant") then
            v:Destroy()
            return
        end
        if v:IsA("Shirt") or v:IsA("Pants") or v:IsA("ShirtGraphic") or v:IsA("CharacterMesh") then
            return
        end
        -- พื้น / พาร์ท → Plastic เรียบ สีเข้ม (เห็นผลชัด)
        if v:IsA("MeshPart") then
            v.Material = Enum.Material.Plastic
            v.Color = FLAT_PROP
            v.Reflectance = 0
            v.CastShadow = false
            v.TextureID = ""
            return
        end
        if v:IsA("SpecialMesh") then
            v.TextureId = ""
            return
        end
        if v:IsA("UnionOperation") or v:IsA("Part") or v:IsA("WedgePart")
            or v:IsA("CornerWedgePart") or v:IsA("TrussPart")
        then
            v.Material = Enum.Material.Plastic
            v.Color = FLAT_FLOOR
            v.Reflectance = 0
            v.CastShadow = false
            pcall(function()
                v.MaterialVariant = ""
            end)
            return
        end
        if v:IsA("BasePart") and not v:IsA("Terrain") then
            v.Material = Enum.Material.Plastic
            v.Color = FLAT_FLOOR
            v.Reflectance = 0
            v.CastShadow = false
        end
    end)
end

local function boostLighting()
    pcall(function()
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
    end)
    pcall(function()
        settings().Rendering.QualityLevel = "Level01"
    end)
    pcall(function()
        Terrain.WaterWaveSize = 0
        Terrain.WaterWaveSpeed = 0
        Terrain.WaterReflectance = 0
        Terrain.WaterTransparency = 1
        Terrain.Decoration = false
    end)
    pcall(function()
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 9e9
        Lighting.Brightness = 0
        Lighting.Ambient = Color3.fromRGB(128, 128, 128)
        Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
        Lighting.EnvironmentDiffuseScale = 0
        Lighting.EnvironmentSpecularScale = 0
        Lighting.ShadowSoftness = 0
        pcall(function()
            Lighting.Technology = Enum.Technology.Compatibility
        end)
        for _, e in ipairs(Lighting:GetChildren()) do
            if e:IsA("PostEffect") or e:IsA("BlurEffect") or e:IsA("SunRaysEffect")
                or e:IsA("ColorCorrectionEffect") or e:IsA("BloomEffect")
                or e:IsA("DepthOfFieldEffect") or e:IsA("Atmosphere")
                or e:IsA("Sky") or e:IsA("Clouds")
            then
                e.Enabled = false
            end
        end
    end)
end

local function boostFPS()
    if not _G.Settings["Boost FPS"] then
        return
    end
    print("[AE Kaitun] Boost FPS — ลบเอฟเฟกต์ + พื้นต่ำสุด (ไม่ยิง setting remote)")

    -- ห้าม FireServer CLIENT_CHANGE_SETTING ที่นี่!
    -- ยิงทีละก้อนไม่มีหน่วง = "Please wait before doing that again!" เต็มจอ
    -- ตั้งค่าเกมไปที่ applyUnitSettings / enableAutoVoteSetting แทน

    boostLighting()

    -- กวาด Workspace ทั้งก้อน (เห็นผลชัด)
    task.spawn(function()
        local n = 0
        for _, v in ipairs(Workspace:GetDescendants()) do
            stripVisual(v)
            n += 1
            if n % 300 == 0 then
                task.wait()
            end
        end
        for _, v in ipairs(Lighting:GetDescendants()) do
            stripVisual(v)
        end
        print("[AE Kaitun] Boost strip แล้ว", n, "objects")
    end)

    if not fpsBoosted then
        fpsBoosted = true
        -- [Removed] Workspace/Lighting DescendantAdded connections here to prevent micro-stutters during heavy waves

        -- กวาดซ้ำเบาๆ นานๆ ครั้ง (ไม่ทุก 5 วิ)
        task.spawn(function()
            while _G.Settings["Boost FPS"] do
                task.wait(25)
                boostLighting()
                local c = 0
                for _, v in ipairs(Workspace:GetDescendants()) do
                    if v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Beam")
                        or v:IsA("Fire") or v:IsA("Smoke") or v:IsA("Decal") or v:IsA("Texture")
                    then
                        stripVisual(v)
                        c += 1
                        if c % 200 == 0 then
                            task.wait()
                        end
                    end
                end
            end
        end)
    end

    print("[AE Kaitun] Boost FPS = on (ไม่ lock FPS)")
end

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local waitPeek = Core.waitPeek

Utils.peek = peek
Utils.getCachedUnitUtils = getCachedUnitUtils
Utils.getCachedInformation = getCachedInformation
Utils.waitPeek = waitPeek
Utils.isUiOrChar = isUiOrChar
Utils.stripVisual = stripVisual
Utils.boostLighting = boostLighting
Utils.boostFPS = boostFPS

return Utils
