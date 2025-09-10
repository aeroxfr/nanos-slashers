local Flashlight = Package.Require("modules/flashlight.lua")
local generalConfig = Package.Require("maps/config.lua")
local currentMap = generalConfig.currentMap
local mapConfig = Package.Require("maps/" .. currentMap .. ".lua")

local jerrycanLocations = mapConfig.jerrycanLocations
local generatorLocations = mapConfig.generatorLocations
local radioLocation = mapConfig.radioLocation
local exitZoneCenter = mapConfig.exitZoneCenter
local policeSpawn = mapConfig.policeSpawn

local survivorSpawns = mapConfig.survivorSpawns
local slasherSpawns = mapConfig.slasherSpawns
local debugMode = generalConfig.debugMode or false

local Game = {}

Game.__index = Game

function Game:new()
    local instance = {
        players = {}, -- players[player] = role
        gameState = 'waiting', -- waiting, playing, ended, restarting
        gameTime = 300, -- Temps de partie en secondes
        gameTimer = nil,
        restartDelay = 15, -- Délai avant relance en secondes
        flashlightCooldown = {},
        currentStage = 0,
        requiredJerrycans = generalConfig.requiredJerrycans,
        foundJerrycans = 0,
        requiredGenerators = generalConfig.requiredGenerators,
        activatedGenerators = 0,
        jerrycansPerGenerator = generalConfig.jerrycansPerGenerator,
        generatorJerrycans = 0,  -- Nombre de jerrycans déposés sur le générateur
        policeCalled = false,
        policeDelay = generalConfig.policeDelay,
        policeTimer = nil,
        jerrycanProps = {},
        generatorProps = {},
        generatorTrigger = nil,
        radioProp = nil,
        exitTrigger = nil,
        escapedSurvivors = 0,
        survivorSpawns = survivorSpawns,
        slasherSpawns = slasherSpawns,
        spectators = {}
    }
    setmetatable(instance, self)
    return instance
end

-- Cache frequently used values
local cachedPlayerList = {}
local cachedSurvivorCount = 0
local lastPlayerCountUpdate = 0

function Game:UpdatePlayerCache()
    local currentTime = os.time()
    if currentTime - lastPlayerCountUpdate < 1 then return end -- Update cache max once per second

    cachedPlayerList = Player.GetAll()
    cachedSurvivorCount = 0

    for _, player in ipairs(cachedPlayerList) do
        if player:IsValid() and self.players[player] == ROLE_SURVIVOR and not self.spectators[player] then
            cachedSurvivorCount = cachedSurvivorCount + 1
        end
    end

    lastPlayerCountUpdate = currentTime
end

function Game:GetSurvivorCount()
    self:UpdatePlayerCache()
    return cachedSurvivorCount
end

function Game:BroadcastToSurvivors(message)
    for p, role in pairs(self.players) do
        if p:IsValid() and role == ROLE_SURVIVOR then
            Chat.SendMessage(p, message)
        end
    end
end

function Game:CanPerformSurvivorAction(player)
    -- Allow survivor actions if player is a survivor OR if debug mode is enabled
    return self.players[player] == ROLE_SURVIVOR or debugMode
end

-- Optimized timer management
function Game:ClearAllTimers()
    if self.gameTimer then
        Timer.ClearInterval(self.gameTimer)
        self.gameTimer = nil
    end
    if self.policeTimer then
        Timer.ClearTimeout(self.policeTimer)
        self.policeTimer = nil
    end
end

function Game:BroadcastToAll(message)
    for p, _ in pairs(self.players) do
        if p:IsValid() then
            Chat.SendMessage(p, message)
        end
    end
end

function Game:HandleObjectInteraction(character, object)
    local player = character:GetPlayer()
    if not player or not player:IsValid() then return end

    local prop = object:GetMesh()
    if not prop then return end

    -- Generator interaction
    if prop == "nanos-world::SM_LightGenerator_Base" and self.currentStage == 1 and self:CanPerformSurvivorAction(player) then
        if self.generatorJerrycans >= self.jerrycansPerGenerator then
            self.activatedGenerators = self.activatedGenerators + 1
            Chat.SendMessage(player, "Générateur activé!")
            Chat.BroadcastMessage("Le générateur a été allumé!")

            if self.generatorTrigger and self.generatorTrigger:IsValid() then
                self.generatorTrigger:Destroy()
                self.generatorTrigger = nil
            end

            if self.generatorProps[1] then
                self.generatorProps[1]:SetGrabMode(GrabMode.Disabled)
                self.generatorProps[1] = nil
            end

            if self.activatedGenerators >= self.requiredGenerators then
                self.currentStage = 2
                for p, _ in pairs(self.players) do
                    if p:IsValid() then
                        Events.CallRemote("UpdateStage", p, self.currentStage)
                        if self.players[p] == ROLE_SURVIVOR then
                            Chat.SendMessage(p, "Étape 2: Allez à la radio pour appeler la police!")
                        end
                    end
                end
                Chat.BroadcastMessage("Le générateur a été démarré! Tuez les survivants avant qu'ils n'appellent la police.")
            end
        else
            local jerrycansNeeded = self.jerrycansPerGenerator - self.generatorJerrycans
            Chat.SendMessage(player, "Il manque " .. jerrycansNeeded .. " jerrycans pour allumer ce générateur!")
            Chat.SendMessage(player, "Déposez les jerrycans près du générateur (dans la zone bleue).")
        end
        return false
    end

    -- Radio interaction
    if prop == "nanos-world::SM_MobilePhone" and self.currentStage == 2 and self:CanPerformSurvivorAction(player) then
        self.policeCalled = true
        self.currentStage = 3

        if self.radioProp and self.radioProp:IsValid() then
            self.radioProp:SetGrabMode(GrabMode.Disabled)
            self.radioProp = nil
        end

        for p, _ in pairs(self.players) do
            if p:IsValid() then
                Events.CallRemote("UpdateStage", p, self.currentStage)
                Chat.SendMessage(p, "Police appelée! Délai de " .. self.policeDelay .. " secondes avant l'arrivée.")
            end
        end

        self.policeTimer = Timer.SetTimeout(function()
            self.policeVehicle = StaticMesh(policeSpawn, Rotator(), "nanos-world::SM_Cube")
            self.currentStage = 4
            for p, _ in pairs(self.players) do
                if p:IsValid() then
                    Events.CallRemote("UpdateStage", p, self.currentStage)
                    Chat.SendMessage(p, "La police est arrivée! Fuyez vers la zone de sortie!")
                end
            end
        end, self.policeDelay * 1000)
    end
end

local gameInstance = Game:new()

function Game:SpawnStageProps()
    for i, loc in ipairs(jerrycanLocations) do
        self.jerrycanProps[i] = Prop(loc, Rotator(), "nanos-world::SM_TallGasCanister_01", CollisionType.Normal)
        self.jerrycanProps[i]:Subscribe("Grab", function(prop, character)
            local player = character:GetPlayer()
            if self.currentStage >= 1 and player and player:IsA(Player) and self:CanPerformSurvivorAction(player) and not player:GetValue("has_jerrycan") then
                self.foundJerrycans = self.foundJerrycans + 1
                player:SetValue("has_jerrycan", true)
                player:SetValue("jerrycan_prop", prop)
                Chat.SendMessage(player, "Vous avez trouvé un jerrycan! (" .. self.foundJerrycans .. "/" .. self.requiredJerrycans .. ")")
                
                if self.foundJerrycans >= self.requiredJerrycans then
                    Chat.BroadcastMessage("Tous les jerrycans ont été ramassés! Apportez-les au générateur.")
                end
            end
        end)

        self.jerrycanProps[i]:Subscribe("UnGrab", function(prop, character)
            local player = character:GetPlayer()
            if self.currentStage >= 1 and player and player:IsA(Player) and self:CanPerformSurvivorAction(player) and player:GetValue("has_jerrycan") then
                player:SetValue("has_jerrycan", false)
                player:SetValue("jerrycan_prop", nil)
                print("Jerrycan dropped by player: " .. tostring(player:GetName()))
            end
        end)
    end

    local randomGeneratorIndex = math.random(#generatorLocations)
    local generatorLocation = generatorLocations[randomGeneratorIndex]
    self.generatorProps[1] = Prop(generatorLocation, Rotator(), "nanos-world::SM_LightGenerator_Base", CollisionType.Normal)
    self.generatorProps[1]:SetGrabMode(GrabMode.Enabled)
    self.generatorTrigger = Trigger(generatorLocation, Rotator(), Vector(200, 200, 100), TriggerType.Sphere, true, Color.BLUE)
    self.generatorTrigger:Subscribe("BeginOverlap", function(trigger, actor)
        if self.currentStage == 1 and actor:IsA(Prop) then
            local assetName = actor:GetMesh()
            if assetName == "nanos-world::SM_TallGasCanister_01" then
                self.generatorJerrycans = self.generatorJerrycans + 1
                
                actor:Destroy()
                
                local jerrycansNeeded = self.jerrycansPerGenerator - self.generatorJerrycans
                if jerrycansNeeded > 0 then
                    Chat.BroadcastMessage("Un jerrycan a été déposé près du générateur! Il en manque encore " .. jerrycansNeeded .. ".")
                    Chat.BroadcastMessage("Générateur: " .. self.generatorJerrycans .. "/" .. self.jerrycansPerGenerator .. " jerrycans déposés")
                else
                    Chat.BroadcastMessage("Tous les jerrycans ont été déposés! Le générateur peut maintenant être activé.")
                end
            end
        end
    end)
    
    -- Move global event subscriptions outside of SpawnStageProps to avoid multiple subscriptions
    if not self.interactSubscribed then
        Character.Subscribe("Interact", function(character, object)
            self:HandleObjectInteraction(character, object)
        end)
        self.interactSubscribed = true
    end

    self.radioProp = Prop(radioLocation, Rotator(), "nanos-world::SM_MobilePhone", CollisionType.Normal)

    self.exitTrigger = Trigger(exitZoneCenter, Rotator(), Vector(100, 100, 100), TriggerType.Sphere, true, Color.GREEN)
    self.exitTrigger:Subscribe("BeginOverlap", function(trigger, actor)
        if self.currentStage == 4 and actor:IsA(Character) then
            local player = actor:GetPlayer()
            if player and self:CanPerformSurvivorAction(player) and not player:GetValue("escaped") then
                player:SetValue("escaped", true)
                self.escapedSurvivors = self.escapedSurvivors + 1
                Chat.SendMessage(player, "Vous vous êtes échappé!")
                
                if self.escapedSurvivors >= self:GetSurvivorCount() then
                    Chat.BroadcastMessage("Tous les survivants se sont échappés! Victoire des survivants!")
                    self:EndGame()
                end
            end
        end
    end)
end

function Game:EnterSpectatorMode(player)
    self.spectators[player] = true

    Timer.SetTimeout(function()
        local char = player:GetControlledCharacter()
        if char and char:IsValid() then
            char:Destroy()
        end
    end, 1000)

    Events.CallRemote('SetSpectator', player, true)
end

function Game:ExitSpectatorMode(player)
    self.spectators[player] = nil
    Events.CallRemote('SetSpectator', player, false)
end

function Game:ResetGame(force)
    if #Player.GetAll() < 2 and not force then
        Console.Log('Pas assez de joueurs pour commencer.')
        return
    end

    self.gameState = 'playing'

    -- Nettoyer les joueurs invalides
    for p, _ in pairs(self.players) do
        if not p:IsValid() then
            self.players[p] = nil
        end
    end

    -- Sortir tous les joueurs du mode spectateur
    for p, _ in pairs(self.spectators) do
        if p:IsValid() then
            self:ExitSpectatorMode(p)
        end
    end
    self.spectators = {}

    -- Reset stage system
    self.currentStage = 0
    self.foundJerrycans = 0
    self.activatedGenerators = 0
    self.generatorJerrycans = 0  -- Reset jerrycans déposés
    self.escapedSurvivors = 0  -- Reset survivants échappés
    self.policeCalled = false
    self:ClearAllTimers()
    if self.policeVehicle and self.policeVehicle:IsValid() then
        self.policeVehicle:Destroy()
    end
    self.policeVehicle = nil
    -- Destroy existing props
    for _, prop in pairs(self.jerrycanProps) do
        if prop and prop:IsValid() then
            prop:Destroy()
        end
    end
    self.jerrycanProps = {}
    for _, prop in pairs(self.generatorProps) do
        if prop and prop:IsValid() then
            prop:Destroy()
        end
    end
    self.generatorProps = {}
    if self.radioProp and self.radioProp:IsValid() then
        self.radioProp:Destroy()
    end
    self.radioProp = nil
    if self.exitTrigger and self.exitTrigger:IsValid() then
        self.exitTrigger:Destroy()
    end
    self.exitTrigger = nil
    if self.generatorTrigger and self.generatorTrigger:IsValid() then
        self.generatorTrigger:Destroy()
    end
    self.generatorTrigger = nil
    if self.policeVehicle and self.policeVehicle:IsValid() then
        self.policeVehicle:Destroy()
    end
    self.policeVehicle = nil

    -- Clean up jerrycan meshes
    for p, _ in pairs(self.players) do
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
    self:AssignRoles(force)

    -- Reset game time
    self.gameTime = 300

    -- Démarrer le timer de jeu
    self:StartGame()

    Console.Log('Partie commencée.')
end


function Game:AssignRoles(force)
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
    self.players[playerList[1]] = ROLE_SLASHER
    Chat.SendMessage(playerList[1], 'Vous êtes le Slasher ! Tuez les survivants.')
    Events.CallRemote('SetRole', playerList[1], ROLE_SLASHER)

    -- Assigner le rôle de Survivant aux autres joueurs
    for i = 2, #playerList do
        self.players[playerList[i]] = ROLE_SURVIVOR
        Chat.SendMessage(playerList[i], 'Vous êtes un Survivant ! Cachez-vous du Slasher.')
        Events.CallRemote('SetRole', playerList[i], ROLE_SURVIVOR)
    end

    return true
end

function Game:StartGame()
    -- Spawn les joueurs
    for player, role in pairs(self.players) do
        if player:IsValid() then
            local spawn = role == ROLE_SLASHER and self.slasherSpawns[math.random(#self.slasherSpawns)] or self.survivorSpawns[math.random(#self.survivorSpawns)]
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
    self.currentStage = 1
    self:SpawnStageProps()
    for p, _ in pairs(self.players) do
        Events.CallRemote("UpdateStage", p, self.currentStage)
        if self:CanPerformSurvivorAction(p) then
            Chat.SendMessage(p, "Étape 1: Ramassez et déposez les jerrycans!")
        elseif debugMode and self.players[p] == ROLE_SLASHER then
            Chat.SendMessage(p, "[DEBUG] Étape 1: Ramassez et déposez les jerrycans!")
        end
    end
    
    -- Informer tous les joueurs du temps restant
    for p, _ in pairs(self.players) do
        Events.CallRemote('UpdateTime', p, self.gameTime)
    end

    self.gameTimer = Timer.SetInterval(function()
        self.gameTime = self.gameTime - 1
        for p, _ in pairs(self.players) do
            Events.CallRemote('UpdateTime', p, self.gameTime)
        end
        if self.gameTime <= 0 then
            self:EndGame()
        end
    end, 1000)
end

function Game:EndGame()
    self.gameState = 'ended'

    Events.Call("RoundEnd")

    self:ClearAllTimers()

    -- Compter les survivants encore en vie
    local survivorsAlive = 0
    for p, role in pairs(self.players) do
        if p:IsValid() and role == ROLE_SURVIVOR and self.spectators[p] == nil then
            survivorsAlive = survivorsAlive + 1
        end
    end

    -- Si le temps est écoulé et qu'il reste des survivants, ils gagnent
    if survivorsAlive > 0 then
        -- Victoire des survivants
        for p, role in pairs(self.players) do
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
        for p, role in pairs(self.players) do
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

    -- Nettoyer les rôles
    self.players = {}

    -- Clean up jerrycan meshes before ending game
    for _, p in pairs(Player.GetAll()) do
        if p:IsValid() then
            local mesh = p:GetValue("jerrycan_mesh")
            if mesh and mesh:IsValid() then
                mesh:Destroy()
            end
            p:SetValue("jerrycan_mesh", nil)
            p:SetValue("has_jerrycan", false)
        end
    end

    -- Mettre tous les joueurs en mode spectateur (ce qui détruira leurs personnages)
    for _, p in pairs(Player.GetAll()) do
        self:EnterSpectatorMode(p)
    end

    -- Relancer automatiquement après un délai
    Timer.SetTimeout(function()
        self:ResetGame()
    end, self.restartDelay * 1000)
end

function Game:CheckRole(player)
    return self.players[player]
end

Player.Subscribe('Spawn', function(player)
    if gameInstance.gameState == 'waiting' then
        Chat.SendMessage(player, 'Bienvenue dans Slasher ! Attendez que la partie commence.')
        if #Player.GetAll() >= 2 then
            gameInstance:ResetGame()
        end
    elseif gameInstance.gameState == 'playing' then
        Chat.SendMessage(player, 'La partie est en cours. Vous êtes spectateur.')
        gameInstance:EnterSpectatorMode(player)
    elseif gameInstance.gameState == 'ended' then
        Chat.SendMessage(player, 'La partie est terminée. Attendez le redémarrage.')
        gameInstance:EnterSpectatorMode(player)
    end
end)

Player.Subscribe('Destroy', function(player)
    if gameInstance.gameState == 'playing' and gameInstance.players[player] then
        if gameInstance.players[player] == ROLE_SURVIVOR then
            local survivorsLeft = 0
            for p, role in pairs(gameInstance.players) do
                if p:IsValid() and role == ROLE_SURVIVOR and gameInstance.spectators[p] == nil then
                    survivorsLeft = survivorsLeft + 1
                end
            end

            if survivorsLeft == 0 then
                gameInstance.gameState = 'ended'

                for p, role in pairs(gameInstance.players) do
                    if p:IsValid() then
                        Events.CallRemote('ClearRole', p)
                        if role == ROLE_SLASHER then
                            Chat.SendMessage(p, 'Victoire ! Tous les survivants sont morts.')
                        else
                            Chat.SendMessage(p, 'Défaite ! Le Slasher a gagné.')
                        end
                    end
                end

                if gameInstance.gameTimer then
                    Timer.ClearInterval(gameInstance.gameTimer)
                    gameInstance.gameTimer = nil
                    for p, role in pairs(gameInstance.players) do
                        if p:IsValid() then
                            Events.CallRemote('UpdateTime', p, 0)
                        end
                    end
                end

                for p, role in pairs(gameInstance.players) do
                    if p:IsValid() then
                        gameInstance:ExitSpectatorMode(p)
                        local char = p:GetControlledCharacter()
                        if char then
                            char:Destroy()
                        end
                    end
                end

                Timer.SetTimeout(function()
                    local currentPlayers = Player.GetAll()
                    if #currentPlayers >= 2 then
                        gameInstance.spectators = {}
                        gameInstance:ResetGame()
                    else
                        gameInstance.gameState = 'waiting'
                        gameInstance.spectators = {}
                    end
                end, gameInstance.restartDelay * 1000)
            else
                Chat.BroadcastMessage('Survivants restants: ' .. survivorsLeft)
            end
        end
        gameInstance.players[player] = nil
    end
end)

Character.Subscribe("Death", function(character, last_damage_taken, last_bone_damaged, damage_type_reason, hit_from_direction, killer, causer)
    if gameInstance.gameState == 'playing' then
        local player = nil
        local killerPlayer = nil

        for p, _ in pairs(gameInstance.players) do
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

        if player and gameInstance.players[player] == ROLE_SURVIVOR then
            -- Destroy jerrycan mesh if holding
            local mesh = player:GetValue("jerrycan_mesh")
            if mesh and mesh:IsValid() then
                mesh:Destroy()
            end
            player:SetValue("jerrycan_mesh", nil)
            player:SetValue("has_jerrycan", false)
            local char = player:GetControlledCharacter()
            if char then
                char:SetCanSprint(true)
            end
        end

        if player and gameInstance.players[player] == ROLE_SURVIVOR and killerPlayer and gameInstance.players[killerPlayer] == ROLE_SLASHER then
            Chat.SendMessage(player, 'Vous avez été tué par le Slasher !')
            Chat.SendMessage(killerPlayer, 'Vous avez tué un survivant !')

            gameInstance:EnterSpectatorMode(player)

            Timer.SetTimeout(function()
                local survivorsLeft = 0
                local totalPlayers = 0

                for p, role in pairs(gameInstance.players) do
                    if p:IsValid() then
                        totalPlayers = totalPlayers + 1
                        if role == ROLE_SURVIVOR and gameInstance.spectators[p] == nil then
                            survivorsLeft = survivorsLeft + 1
                        end
                    end
                end

                Chat.BroadcastMessage('Survivants restants: ' .. survivorsLeft)

                if survivorsLeft == 0 then
                    gameInstance:EndGame()
                end
            end, 500)
        end
    end
end)

Events.SubscribeRemote("ToggleFlashlight", function(player)
    print('ToggleFlashlight called by player: ' .. tostring(player))
    local currentTime = os.time() * 1000
    if gameInstance.flashlightCooldown[player] and gameInstance.flashlightCooldown[player] > currentTime then
        return
    end

    gameInstance.flashlightCooldown[player] = currentTime + 350

    local char = player:GetControlledCharacter()
    if not char or not char:IsValid() or char:GetHealth() <= 0 then
        return
    end

    if gameInstance:CanPerformSurvivorAction(player) then
        Flashlight.Toggle(char)
    end
end)

Console.RegisterCommand('start_slasher', function()
    if(#Player.GetAll() == 0) then
        Console.Log('Pas assez de joueurs pour commencer.')
        return
    end
    gameInstance:ResetGame(true)
end, 'Démarrer une partie de Slasher (admin uniquement)', {})

Console.RegisterCommand('end_slasher', function()
    if gameInstance.gameState == 'playing' then
        gameInstance:EndGame()
    else
        Console.Log('Aucune partie en cours.')
    end
end, 'Terminer la partie de Slasher en cours (admin uniquement)', {})

return Game, gameInstance
