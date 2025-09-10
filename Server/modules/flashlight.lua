local Flashlight = {}

local FLASHLIGHT_COLOR = Color(0.97, 0.76, 0.46)
local DRAIN_TIME = 1000 -- ms, drain 1% per second
local REGEN_TIME = 2000 -- ms, regen 1% per 2 seconds
local BUG_DELAY = 30000 -- ms, 30 seconds
local INITIAL_BATTERY = 100

function Flashlight.Attach(character)
    if character:GetValue("flashlight_mesh") then
        return
    end

    local flashlightMesh = StaticMesh(Vector(), Rotator(), "nanos-world::SM_Flashlight", CollisionType.NoCollision)
    flashlightMesh:SetScale(Vector(1.0))
    flashlightMesh:AttachTo(character, AttachmentRule.SnapToTarget, "hand_l", -1, false)
    flashlightMesh:SetRelativeRotation(Rotator(-60, 90, 0))
    flashlightMesh:SetRelativeLocation(Vector(10, -10, 10))

    local light = Light(Vector(), Rotator(), FLASHLIGHT_COLOR, LightType.Spot, 20, 100, 28, 45, 1000, true, true, false)
    light:AttachTo(flashlightMesh, AttachmentRule.SnapToTarget, "", -1, false)
    light:SetRelativeLocation(Vector(40, 0, 0))
    light:SetTextureLightProfile( LightProfile.Shattered_04 )
    light:SetVisibility(false)

    character:SetValue("flashlight_mesh", flashlightMesh, false)
    character:SetValue("flashlight_light", light, false)
    character:SetValue("flashlight_battery", INITIAL_BATTERY, true)
    character:SetValue("flashlight_enabled", false, true)

    character:Subscribe("Destroy", function()
        if flashlightMesh:IsValid() then
            flashlightMesh:Destroy()
        end
        if light:IsValid() then
            light:Destroy()
        end
    end)
end

-- Get attached flashlight
function Flashlight.GetAttached(character)
    return character:GetValue("flashlight_mesh"), character:GetValue("flashlight_light")
end

-- Set battery
function Flashlight.SetBattery(character, battery)
    battery = math.max(0, math.min(100, battery))
    if battery == character:GetValue("flashlight_battery") then
        return
    end

    character:SetValue("flashlight_battery", battery, true)

    if battery <= 0 then
        Flashlight.Disable(character)
    end
end

function Flashlight.GetBattery(character)
    return character:GetValue("flashlight_battery") or 0
end

function Flashlight.IsEnabled(character)
    return character:GetValue("flashlight_enabled") or false
end

function Flashlight.Enable(character)
    if Flashlight.IsEnabled(character) then
        return false
    end

    if Flashlight.GetBattery(character) <= 0 then
        return false, "Not enough battery"
    end

    local regenTimer = character:GetValue("battery_regen_timer")
    if regenTimer and Timer.IsValid(regenTimer) then
        Timer.ClearInterval(regenTimer)
        character:SetValue("battery_regen_timer", nil, false)
    end

    local drainTimer = Timer.SetInterval(function()
        Flashlight.SetBattery(character, Flashlight.GetBattery(character) - 1)
    end, DRAIN_TIME)
    Timer.Bind(drainTimer, character)
    character:SetValue("battery_drain_timer", drainTimer, false)

    local mesh, light = Flashlight.GetAttached(character)
    if mesh and mesh:IsValid() then
        mesh:SetMaterialColorParameter("Emissive", Color(50, 50, 50))
    end
    if light and light:IsValid() then
        light:SetVisibility(true)
    end

    character:SetValue("flashlight_enabled", true, true)
    return true
end

function Flashlight.Disable(character)
    if not Flashlight.IsEnabled(character) then
        return false
    end

    local drainTimer = character:GetValue("battery_drain_timer")
    if drainTimer and Timer.IsValid(drainTimer) then
        Timer.ClearInterval(drainTimer)
        character:SetValue("battery_drain_timer", nil, false)
    end

    local regenTimer = Timer.SetInterval(function()
        if character:GetGaitMode() == GaitMode.Sprinting then
            Flashlight.SetBattery(character, Flashlight.GetBattery(character) + 1)
        end
    end, REGEN_TIME)
    Timer.Bind(regenTimer, character)
    character:SetValue("battery_regen_timer", regenTimer, false)

    local mesh, light = Flashlight.GetAttached(character)
    if mesh and mesh:IsValid() then
        mesh:SetMaterialColorParameter("Emissive", Color.BLACK)
    end
    if light and light:IsValid() then
        light:SetVisibility(false)
    end

    character:SetValue("flashlight_enabled", false, true)
    return true
end

function Flashlight.Toggle(character)
    if Flashlight.IsEnabled(character) then
        return Flashlight.Disable(character)
    else
        return Flashlight.Enable(character)
    end
end

local function triggerLightBug()
    local enabledChars = {}
    for _, char in ipairs(Character.GetAll()) do
        if char:IsValid() and Flashlight.IsEnabled(char) then
            table.insert(enabledChars, char)
        end
    end

    if #enabledChars == 0 then
        return
    end

    local randomChar = enabledChars[math.random(1, #enabledChars)]
    if not randomChar or not randomChar:IsValid() then
        return
    end

    local player = randomChar:GetPlayer()

    local intervals = 0
    local flickerTimer = Timer.SetInterval(function()
        if intervals == 5 then
            return false
        end

        intervals = intervals + 1

        if intervals < 3 or intervals > 4 then
            Flashlight.Toggle(randomChar)
        end
    end, 150)
    Timer.Bind(flickerTimer, randomChar)
end

local lightBugTimer = nil

Events.Subscribe("RoundStart", function()
    if lightBugTimer and Timer.IsValid(lightBugTimer) then
        Timer.ClearInterval(lightBugTimer)
    end
    lightBugTimer = Timer.SetInterval(triggerLightBug, BUG_DELAY)
end)

Events.Subscribe("RoundEnd", function()
    if lightBugTimer and Timer.IsValid(lightBugTimer) then
        Timer.ClearInterval(lightBugTimer)
        lightBugTimer = nil
    end
end)

return Flashlight
