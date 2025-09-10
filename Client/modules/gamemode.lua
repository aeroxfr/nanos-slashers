local myRole = nil
local timeLeft = 0
local isSpectator = false
local battery = 100

local canvas = Canvas(true, Color(0, 0, 0, 0), 1, true, true, 1920, 1080, Vector2D(0, 0))

Events.SubscribeRemote("SetRole", function(role)
    myRole = role
end)

Events.SubscribeRemote("ClearRole", function()
    myRole = nil
end)

Events.SubscribeRemote("UpdateTime", function(time)
    timeLeft = time
end)

Events.SubscribeRemote("SetSpectator", function(spectator)
    isSpectator = spectator
end)

Client.Subscribe("Tick", function()
    if Client.GetLocalPlayer() then
        local char = Client.GetLocalPlayer():GetControlledCharacter()
        if char and char:IsValid() then
            battery = char:GetValue("flashlight_battery") or 0
        end
    end
end)

canvas:Subscribe("Update", function()
    if isSpectator then
        canvas:DrawText("MODE SPECTATEUR", Vector2D(10, 10), FontType.Roboto, 24, Color.YELLOW)
        canvas:DrawText("Vous observez la partie", Vector2D(10, 35), FontType.Roboto, 18, Color.WHITE)
    elseif myRole == ROLE_SLASHER then
        canvas:DrawText("Vous êtes le Slasher", Vector2D(10, 10), FontType.Roboto, 24, Color.RED)
    elseif myRole == ROLE_SURVIVOR then
        canvas:DrawText("Vous êtes un Survivant", Vector2D(10, 10), FontType.Roboto, 24, Color.GREEN)
    end
    if timeLeft > 0 then
        local minutes = math.floor(timeLeft / 60)
        local seconds = timeLeft % 60
        canvas:DrawText(string.format("Temps restant: %02d:%02d", minutes, seconds), Vector2D(10, 60), FontType.Roboto, 20, Color.WHITE)
    end
    if myRole == ROLE_SURVIVOR then
        canvas:DrawText("Batterie: " .. battery .. "%", Vector2D(10, 85), FontType.Roboto, 18, Color.WHITE)
    end
end)

Sky.Spawn()
Sky.SetTimeOfDay(2, 30)