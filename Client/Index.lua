Package.Require("modules/gamemode.lua")
Package.Require("modules/input.lua")

Console.RegisterCommand("pos", function()
    local player = Client.GetLocalPlayer()
    if player then
        local char = player:GetControlledCharacter()
        if char and char:IsValid() then
            local location = char:GetLocation()
            print(location.X .. ", " .. location.Y .. ", " .. location.Z)
        else
            local location = player:GetCameraLocation()
            if location then
                print(location.X .. ", " .. location.Y .. ", " .. location.Z)
            else
                print("Impossible de récupérer la position de la caméra.")
            end
        end
    else
        print("Joueur local non trouvé.")
    end
end, "Affiche la position actuelle du joueur ou de la caméra", {})

print('Gamemode Slasher chargé côté client.')