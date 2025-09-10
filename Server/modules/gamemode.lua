local Game = {}

Game.__index = Game

function Game:new()
    local instance = {
        players = {},          -- players[player] = role
        gameState = 'waiting', -- waiting, playing, ended, restarting
        gameTime = 60,         -- Temps de partie en secondes
        gameTimer = nil,
        restartDelay = 5,      -- Délai avant relance en secondes
        flashlightCooldown = {},
        survivorSpawns = {
            Vector(0, 0, 100),
            Vector(100, 0, 100),
            Vector(200, 0, 100),
            Vector(300, 0, 100),
            Vector(400, 0, 100)
        },
        slasherSpawns = {
            Vector(500, 0, 100),
            Vector(600, 0, 100)
        },
        spectators = {}
    }
    setmetatable(instance, self)
    return instance
end

local gameInstance = Game:new()

local Flashlight = Package.Require("modules/flashlight.lua")

function Game:EnterSpectatorMode(player)
    self.spectators[player] = true
    Timer.SetTimeout(function()
        -- Player may have disconnected or been destroyed during the 1s delay
        if (not player) or (not NanosUtils.IsEntityValid(player)) then
            return
        end
        local char = player:GetControlledCharacter()
        if char and NanosUtils.IsEntityValid(char) then
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
        self.gameState = 'waiting'
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

    -- Nettoie les characters existants sur la map
    for _, char in pairs(Character.GetAll()) do
        if not char:IsValid() then
            char:Destroy()
        end
    end
    self.spectators = {}

    -- Assigner les rôles
    self:AssignRoles(force)

    -- Reset game time
    self.gameTime = 60

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
            local spawn = role == ROLE_SLASHER and self.slasherSpawns[math.random(#self.slasherSpawns)] or
                self.survivorSpawns[math.random(#self.survivorSpawns)]
            local char = Character(spawn, Rotator(0, 0, 0),
                role == ROLE_SLASHER and 'nanos-world::SK_PostApocalyptic' or 'nanos-world::SK_Male')
            player:SetCameraFOV(90)
            player:Possess(char)
            char:SetViewMode(0)
            char:SetLocation(spawn)
            if (role == ROLE_SLASHER) then
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

    if self.gameTimer then
        Timer.ClearInterval(self.gameTimer)
        self.gameTimer = nil
        for p, _ in pairs(self.players) do
            if p:IsValid() then
                Events.CallRemote('UpdateTime', p, 0)
            end
        end
    end

    -- Compter les survivants encore en vie
    local survivorsAlive = 0
    for p, role in pairs(self.players) do
        if p:IsValid() and role == ROLE_SURVIVOR and self.spectators[p] == nil then
            survivorsAlive = survivorsAlive + 1
        end
    end

    -- Si le temps est écoulé et qu'il reste des survivants, ils gagnent
    if survivorsAlive > 0 then
        Console.Log('Temps écoulé, les survivants ont gagné.')
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
        Console.Log('Le Slasher a tué tous les survivants.')
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

    -- Mettre tous les joueurs en mode spectateur (ce qui détruira leurs personnages)
    for _, p in pairs(Player.GetAll()) do
        if NanosUtils.IsEntityValid(p) then
            self:EnterSpectatorMode(p)
        end
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
    local controlledChar = player:GetControlledCharacter()
    if controlledChar and controlledChar:IsValid() then
        controlledChar:Destroy()
    end
    if gameInstance.gameState == 'playing' and gameInstance.players[player] then
        if gameInstance.players[player] == ROLE_SURVIVOR then
            local survivorsLeft = 0
            for p, role in pairs(gameInstance.players) do
                if p:IsValid() and role == ROLE_SURVIVOR and gameInstance.spectators[p] == nil then
                    survivorsLeft = survivorsLeft + 1
                end
            end
            if survivorsLeft == 0 then
                gameInstance:EndGame()
            else
                Chat.BroadcastMessage('Survivants restants: ' .. survivorsLeft)
            end
        else
            if gameInstance.players[player] == ROLE_SLASHER then
                gameInstance:EndGame()
            end
            gameInstance.players[player] = nil
        end
    end
end)

Character.Subscribe("Death",
    function(character, last_damage_taken, last_bone_damaged, damage_type_reason, hit_from_direction, killer, causer)
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
                        gameInstance.gameState = 'ended'

                        Chat.SendMessage(killerPlayer, 'Victoire ! Tous les survivants sont morts.')
                        for p, role in pairs(gameInstance.players) do
                            if p:IsValid() and role ~= ROLE_SLASHER then
                                Chat.SendMessage(p, 'Défaite ! Le Slasher a gagné.')
                            end
                        end

                        for p, role in pairs(gameInstance.players) do
                            if p:IsValid() then
                                Events.CallRemote('ClearRole', p)
                                gameInstance:ExitSpectatorMode(p)
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

    if gameInstance.players[player] == ROLE_SURVIVOR then
        Flashlight.Toggle(char)
    end
end)

Console.RegisterCommand('start_slasher', function()
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
