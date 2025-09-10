local players = {} -- players[player] = role
local gameState = 'waiting' -- waiting, playing, ended, restarting
local gameTime = 60 -- Temps de partie en secondes
local gameTimer = nil
local restartDelay = 15 -- Délai avant relance en secondes
local flashlightCooldown = {}

local Flashlight = Package.Require("modules/flashlight.lua")

-- Load configs
local generalConfig = Package.Require("maps/config.lua")
local currentMap = generalConfig.currentMap
local mapConfig = Package.Require("maps/" .. currentMap .. ".lua")

-- Stage system
local currentStage = 0
local requiredJerrycans = generalConfig.requiredJerrycans
local foundJerrycans = 0
local requiredGenerators = generalConfig.requiredGenerators
local activatedGenerators = 0
local policeCalled = false
local policeDelay = generalConfig.policeDelay
local policeTimer = nil

-- Map data from config
local jerrycanLocations = mapConfig.jerrycanLocations
local generatorLocations = mapConfig.generatorLocations
local radioLocation = mapConfig.radioLocation
local exitZoneCenter = mapConfig.exitZoneCenter
local policeSpawn = mapConfig.policeSpawn

-- Props
local jerrycanProps = {}
local generatorProps = {}
local radioProp = nil
local exitTrigger = nil

local survivorSpawns = mapConfig.survivorSpawns
local slasherSpawns = mapConfig.slasherSpawns

local spectators = {}

function SpawnStageProps()
    -- Spawn jerrycans
    for i, loc in ipairs(jerrycanLocations) do
        jerrycanProps[i] = Prop(loc, Rotator(), "nanos-world::SM_TallGasCanister_01 ", CollisionType.Normal)
        jerrycanProps[i]:Subscribe("Interact", function(prop, player)
            if currentStage == 1 and players[player] == ROLE_SURVIVOR and not player:GetValue("has_jerrycan") then
                foundJerrycans = foundJerrycans + 1
                player:SetValue("has_jerrycan", true)
                Chat.SendMessage(player, "Vous avez trouvé un jerrycan! (" .. foundJerrycans .. "/" .. requiredJerrycans .. ")")
                
                -- Attach jerrycan mesh to hand
                local char = player:GetControlledCharacter()
                if char then
                    local jerrycanMesh = StaticMesh(Vector(), Rotator(), "nanos-world::SM_TallGasCanister_01", CollisionType.NoCollision)
                    jerrycanMesh:AttachTo(char, AttachmentRule.SnapToTarget, "hand_l", -1, false)
                    jerrycanMesh:SetRelativeLocation(Vector(0, 0, 0))
                    player:SetValue("jerrycan_mesh", jerrycanMesh)
                    char:SetCanSprint(false)
                end
                
                prop:Destroy()
                jerrycanProps[i] = nil
                if foundJerrycans >= requiredJerrycans then
                    currentStage = 2
                    for p, _ in pairs(players) do
                        Events.CallRemote("UpdateStage", p, currentStage)
                        Chat.SendMessage(p, "Étape 2: Trouvez et allumez les générateurs!")
                    end
                end
            end
        end)
    end

    -- Spawn generators
    for i, loc in ipairs(generatorLocations) do
        generatorProps[i] = Prop(loc, Rotator(), "nanos-world::SM_LightGenerator_Base", CollisionType.Normal)
        generatorProps[i]:Subscribe("Interact", function(prop, player)
            if currentStage == 2 and players[player] == ROLE_SURVIVOR and player:GetValue("has_jerrycan") then
                activatedGenerators = activatedGenerators + 1
                player:SetValue("has_jerrycan", false)
                Chat.SendMessage(player, "Générateur activé! (" .. activatedGenerators .. "/" .. requiredGenerators .. ")")
                
                -- Destroy jerrycan mesh and re-enable sprint
                local mesh = player:GetValue("jerrycan_mesh")
                if mesh and mesh:IsValid() then
                    mesh:Destroy()
                end
                player:SetValue("jerrycan_mesh", nil)
                local char = player:GetControlledCharacter()
                if char then
                    char:SetCanSprint(true)
                end
                
                prop:Destroy()
                generatorProps[i] = nil
                if activatedGenerators >= requiredGenerators then
                    currentStage = 3
                    for p, _ in pairs(players) do
                        Events.CallRemote("UpdateStage", p, currentStage)
                        Chat.SendMessage(p, "Étape 3: Trouvez la radio pour appeler la police!")
                    end
                end
            elseif currentStage == 2 and players[player] == ROLE_SURVIVOR then
                Chat.SendMessage(player, "Vous avez besoin d'un jerrycan pour activer ce générateur!")
            end
        end)
    end

    -- Spawn radio
    radioProp = Prop(radioLocation, Rotator(), "nanos-world::P_Radio_01", CollisionType.Normal)
    radioProp:Subscribe("Interact", function(prop, player)
        if currentStage == 3 and players[player] == ROLE_SURVIVOR then
            policeCalled = true
            currentStage = 4
            prop:Destroy()
            radioProp = nil
            for p, _ in pairs(players) do
                Events.CallRemote("UpdateStage", p, currentStage)
                Chat.SendMessage(p, "Police appelée! Délai de " .. policeDelay .. " secondes avant l'arrivée.")
            end
            policeTimer = Timer.SetTimeout(function()
                -- Spawn police vehicle
                local policeVehicle = Vehicle(policeSpawn, Rotator(), "nanos-world::V_PoliceCar_01")
                for p, _ in pairs(players) do
                    Chat.SendMessage(p, "La police est arrivée! Fuyez vers la zone de sortie!")
                end
            end, policeDelay * 1000)
        end
    end)

    -- Spawn exit trigger
    exitTrigger = Trigger(exitZoneCenter, Rotator(), Vector(100, 100, 100), TriggerType.Sphere, false, Color.GREEN)
    exitTrigger:Subscribe("BeginOverlap", function(trigger, actor)
        if currentStage == 4 and actor:IsA(Character) then
            local player = actor:GetPlayer()
            if player and players[player] == ROLE_SURVIVOR then
                Chat.SendMessage(player, "Vous vous êtes échappé!")
            end
        end
    end)
end

function EnterSpectatorMode(player)
    spectators[player] = true

    Timer.SetTimeout(function()
        local char = player:GetControlledCharacter()
        if char and char:IsValid() then
            char:Destroy()
        end
    end, 1000)

    Chat.SendMessage(player, 'Vous êtes mort ! Vous êtes maintenant en mode spectateur.')
    Events.CallRemote('SetSpectator', player, true)
end

function ExitSpectatorMode(player)
    spectators[player] = nil
    Events.CallRemote('SetSpectator', player, false)
end

function ResetGame(force)
    if #Player.GetAll() < 2 and not force then
        print('Pas assez de joueurs pour commencer.')
        return
    end

    gameState = 'playing'

    -- Nettoyer les joueurs invalides
    for p, _ in pairs(players) do
        if not p:IsValid() then
            players[p] = nil
        end
    end

    -- Sortir tous les joueurs du mode spectateur
    for p, _ in pairs(spectators) do
        if p:IsValid() then
            ExitSpectatorMode(p)
        end
    end
    spectators = {}

    -- Reset stage system
    currentStage = 0
    foundJerrycans = 0
    activatedGenerators = 0
    policeCalled = false
    if policeTimer then
        Timer.ClearTimeout(policeTimer)
        policeTimer = nil
    end
    -- Destroy existing props
    for _, prop in pairs(jerrycanProps) do
        if prop and prop:IsValid() then
            prop:Destroy()
        end
    end
    jerrycanProps = {}
    for _, prop in pairs(generatorProps) do
        if prop and prop:IsValid() then
            prop:Destroy()
        end
    end
    generatorProps = {}
    if radioProp and radioProp:IsValid() then
        radioProp:Destroy()
    end
    radioProp = nil
    if exitTrigger and exitTrigger:IsValid() then
        exitTrigger:Destroy()
    end
    exitTrigger = nil

    -- Clean up jerrycan meshes
    for p, _ in pairs(players) do
        if p:IsValid() then
            local mesh = p:GetValue("jerrycan_mesh")
            if mesh and mesh:IsValid() then
                mesh:Destroy()
            end
            p:SetValue("jerrycan_mesh", nil)
            p:SetValue("has_jerrycan", false)
            local char = p:GetControlledCharacter()
            if char then
                char:SetCanSprint(true)
            end
        end
    end

    -- Assigner les rôles
    AssignRoles(force)

    -- Reset game time
    gameTime = 60

    -- Démarrer le timer de jeu
    StartGame()

    print('Partie commencée.')
end


function AssignRoles(force)
    local playerList = Player.GetAll()
    if #playerList < 2 and not force then
        return
    end

    -- Mélanger la liste des joueurs
    for i = #playerList, 2, -1 do
        local j = math.random(i)
        playerList[i], playerList[j] = playerList[j], playerList[i]
    end

    -- Assigner le rôle de Slasher au premier joueur de la liste mélangée 
    players[playerList[1]] = ROLE_SLASHER
    Chat.SendMessage(playerList[1], 'Vous êtes le Slasher ! Tuez les survivants.')
    Events.CallRemote('SetRole', playerList[1], ROLE_SLASHER)

    -- Assigner le rôle de Survivant aux autres joueurs
    for i = 2, #playerList do
        players[playerList[i]] = ROLE_SURVIVOR
        Chat.SendMessage(playerList[i], 'Vous êtes un Survivant ! Cachez-vous du Slasher.')
        Events.CallRemote('SetRole', playerList[i], ROLE_SURVIVOR)
    end

    return true
end

function StartGame()
    -- Spawn les joueurs
    for player, role in pairs(players) do
        if player:IsValid() then
            local spawn = role == ROLE_SLASHER and slasherSpawns[math.random(#slasherSpawns)] or survivorSpawns[math.random(#survivorSpawns)]
            local char = Character(spawn, Rotator(0, 0, 0), role == ROLE_SLASHER and mapConfig.killerModel or mapConfig.survivorModel)
            player:SetCameraFOV(90)
            player:Possess(char)
            char:SetViewMode(0)
            char:SetLocation(spawn)
            if(role == ROLE_SLASHER) then
                char:SetInvulnerable(true)
                char:SetTeam(2)
            else
                char:SetTeam(1)
                char:SetCanAim(false)
                char:SetCanPunch(false)
                Flashlight.Attach(char)
            end
        end
    end
    
    Events.Call("RoundStart")
    
    -- Start stage system
    currentStage = 1
    SpawnStageProps()
    for p, _ in pairs(players) do
        Events.CallRemote("UpdateStage", p, currentStage)
        if players[p] == ROLE_SURVIVOR then
            Chat.SendMessage(p, "Étape 1: Trouvez les jerrycans!")
        end
    end
    
    -- Informer tous les joueurs du temps restant
    for p, _ in pairs(players) do
        Events.CallRemote('UpdateTime', p, gameTime)
    end

    gameTimer = Timer.SetInterval(function()
        gameTime = gameTime - 1
        for p, _ in pairs(players) do
            Events.CallRemote('UpdateTime', p, gameTime)
        end
        if gameTime <= 0 then
            EndGame()
        end
    end, 1000)
end

function EndGame()
    gameState = 'ended'

    Events.Call("RoundEnd")

    if gameTimer then
        Timer.ClearInterval(gameTimer)
        gameTimer = nil
        for p, _ in pairs(players) do
            if p:IsValid() then
                Events.CallRemote('UpdateTime', p, 0)
            end
        end
    end

    -- Compter les survivants encore en vie
    local survivorsAlive = 0
    for p, role in pairs(players) do
        if p:IsValid() and role == ROLE_SURVIVOR and spectators[p] == nil then
            survivorsAlive = survivorsAlive + 1
        end
    end

    -- Si le temps est écoulé et qu'il reste des survivants, ils gagnent
    if survivorsAlive > 0 then
        -- Victoire des survivants
        for p, role in pairs(players) do
            if p:IsValid() then
                Events.CallRemote('ClearRole', p)
                if role == ROLE_SURVIVOR then
                    Chat.SendMessage(p, 'Victoire ! Temps écoulé, vous avez survécu !')
                else
                    Chat.SendMessage(p, 'Défaite ! Les survivants ont gagné.')
                end
            end
        end
    else
        -- Victoire du Slasher (tous les survivants morts)
        for p, role in pairs(players) do
            if p:IsValid() then
                Events.CallRemote('ClearRole', p)
                if role == ROLE_SLASHER then
                    Chat.SendMessage(p, 'Victoire ! Tous les survivants sont morts.')
                else
                    Chat.SendMessage(p, 'Défaite ! Le Slasher a gagné.')
                end
            end
        end
    end

    -- Nettoyer les personnages et spectateurs
    for p, role in pairs(players) do
        if p:IsValid() then
            ExitSpectatorMode(p)
            local char = p:GetControlledCharacter()
            if char then
                char:Destroy()
            end
        end
    end

    -- Redémarrage automatique
    Timer.SetTimeout(function()
        local currentPlayers = Player.GetAll()
        if #currentPlayers >= 2 then
            spectators = {}
            ResetGame()
        else
            gameState = 'waiting'
            spectators = {}
            for p, role in pairs(players) do
                if p:IsValid() then
                    Chat.SendMessage(p, 'Pas assez de joueurs pour relancer.')
                end
            end
        end
    end, restartDelay * 1000)
end

function CheckRole(player)
    return players[player]
end

Player.Subscribe('Spawn', function(player)
    if gameState == 'waiting' then
        Chat.SendMessage(player, 'Bienvenue dans Slasher ! Attendez que la partie commence.')
        if #Player.GetAll() >= 2 then
            ResetGame()
        end
    elseif gameState == 'playing' then
        Chat.SendMessage(player, 'La partie est en cours. Vous êtes spectateur.')
        EnterSpectatorMode(player)
    elseif gameState == 'ended' then
        Chat.SendMessage(player, 'La partie est terminée. Attendez le redémarrage.')
        EnterSpectatorMode(player)
    end
end)

Player.Subscribe('Destroy', function(player)
    if gameState == 'playing' and players[player] then
        if players[player] == ROLE_SURVIVOR then
            local survivorsLeft = 0
            for p, role in pairs(players) do
                if p:IsValid() and role == ROLE_SURVIVOR and spectators[p] == nil then
                    survivorsLeft = survivorsLeft + 1
                end
            end

            if survivorsLeft == 0 then
                gameState = 'ended'

                for p, role in pairs(players) do
                    if p:IsValid() then
                        Events.CallRemote('ClearRole', p)
                        if role == ROLE_SLASHER then
                            Chat.SendMessage(p, 'Victoire ! Tous les survivants sont morts.')
                        else
                            Chat.SendMessage(p, 'Défaite ! Le Slasher a gagné.')
                        end
                    end
                end

                if gameTimer then
                    Timer.ClearInterval(gameTimer)
                    gameTimer = nil
                    for p, role in pairs(players) do
                        if p:IsValid() then
                            Events.CallRemote('UpdateTime', p, 0)
                        end
                    end
                end

                for p, role in pairs(players) do
                    if p:IsValid() then
                        ExitSpectatorMode(p)
                        local char = p:GetControlledCharacter()
                        if char then
                            char:Destroy()
                        end
                    end
                end

                Timer.SetTimeout(function()
                    local currentPlayers = Player.GetAll()
                    if #currentPlayers >= 2 then
                        spectators = {}
                        ResetGame()
                    else
                        gameState = 'waiting'
                        spectators = {}
                    end
                end, restartDelay * 1000)
            else
                Chat.BroadcastMessage('Survivants restants: ' .. survivorsLeft)
            end
        end
        players[player] = nil
        spectators[player] = nil
    end
end)

Character.Subscribe("Death", function(character, last_damage_taken, last_bone_damaged, damage_type_reason, hit_from_direction, killer, causer)
    if gameState == 'playing' then
        local player = nil
        local killerPlayer = nil

        for p, _ in pairs(players) do
            if p:IsValid() then
                local controlledChar = p:GetControlledCharacter()
                if controlledChar and controlledChar == character then
                    player = p
                end
                if killer then
                    if killer == p then
                        killerPlayer = p
                    elseif controlledChar and controlledChar == killer then
                        killerPlayer = p
                    end
                end
            end
        end

        if player then
            -- Destroy jerrycan mesh if holding
            local mesh = player:GetValue("jerrycan_mesh")
            if mesh and mesh:IsValid() then
                mesh:Destroy()
            end
            player:SetValue("jerrycan_mesh", nil)
            player:SetValue("has_jerrycan", false)
            -- Re-enable sprint (though character is dead, for consistency)
            local char = player:GetControlledCharacter()
            if char then
                char:SetCanSprint(true)
            end
        end

        if player and players[player] == ROLE_SURVIVOR and killerPlayer and players[killerPlayer] == ROLE_SLASHER then
            Chat.SendMessage(player, 'Vous avez été tué par le Slasher !')
            Chat.SendMessage(killerPlayer, 'Vous avez tué un survivant !')

            EnterSpectatorMode(player)

            Timer.SetTimeout(function()
                local survivorsLeft = 0
                local totalPlayers = 0

                for p, role in pairs(players) do
                    if p:IsValid() then
                        totalPlayers = totalPlayers + 1
                        if role == ROLE_SURVIVOR and spectators[p] == nil then
                            survivorsLeft = survivorsLeft + 1
                        end
                    end
                end

                Chat.BroadcastMessage('Survivants restants: ' .. survivorsLeft)

                if survivorsLeft == 0 then
                    gameState = 'ended'

                    Chat.SendMessage(killerPlayer, 'Victoire ! Tous les survivants sont morts.')
                    for p, role in pairs(players) do
                        if p:IsValid() and role ~= ROLE_SLASHER then
                            Chat.SendMessage(p, 'Défaite ! Le Slasher a gagné.')
                        end
                    end

                    for p, role in pairs(players) do
                        if p:IsValid() then
                            Events.CallRemote('ClearRole', p)
                            ExitSpectatorMode(p)
                        end
                    end

                    if gameTimer then
                        Timer.ClearInterval(gameTimer)
                        gameTimer = nil
                        for p, role in pairs(players) do
                            if p:IsValid() then
                                Events.CallRemote('UpdateTime', p, 0)
                            end
                        end
                    end

                    for p, role in pairs(players) do
                        if p:IsValid() then
                            local char = p:GetControlledCharacter()
                            if char then
                                char:Destroy()
                            end
                        end
                    end

                    Timer.SetTimeout(function()
                        local currentPlayers = Player.GetAll()
                        if #currentPlayers >= 2 then
                            spectators = {}
                            ResetGame()
                        else
                            gameState = 'waiting'
                            spectators = {}
                        end
                    end, restartDelay * 1000)
                end
            end, 500)
        end
    end
end)

Events.SubscribeRemote("ToggleFlashlight", function(player)
    print('ToggleFlashlight called by player: ' .. tostring(player))
    local currentTime = os.time() * 1000
    if flashlightCooldown[player] and flashlightCooldown[player] > currentTime then
        return
    end

    flashlightCooldown[player] = currentTime + 350

    local char = player:GetControlledCharacter()
    if not char or not char:IsValid() or char:GetHealth() <= 0 then
        return
    end

    if players[player] == ROLE_SURVIVOR then
        Flashlight.Toggle(char)
    end
end)

Events.Subscribe("DropJerrycan", function(player)
    if players[player] == ROLE_SURVIVOR and player:GetValue("has_jerrycan") then
        player:SetValue("has_jerrycan", false)
        
        local char = player:GetControlledCharacter()
        if char then
            char:SetCanSprint(true)
            local mesh = player:GetValue("jerrycan_mesh")
            if mesh and mesh:IsValid() then
                mesh:Destroy()
            end
            player:SetValue("jerrycan_mesh", nil)
            
            -- Spawn jerrycan at feet
            local loc = char:GetLocation()
            Prop(loc, Rotator(), "nanos-world::SM_TallGasCanister_01", CollisionType.Normal)
        end
    end
end)

Console.RegisterCommand('start_slasher', function()
    ResetGame(true)
end, 'Démarrer une partie de Slasher (admin uniquement)', {})

Console.RegisterCommand('end_slasher', function()
    if gameState == 'playing' then
        EndGame()
    else
        print('Aucune partie en cours.')
    end
end, 'Terminer la partie de Slasher en cours (admin uniquement)', {})
