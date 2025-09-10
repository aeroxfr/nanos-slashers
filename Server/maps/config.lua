-- General map configuration
local Config = {}

Config.currentMap = "school"  -- Change this to switch maps: "school", "motel", etc.

Config.requiredJerrycans = 3
Config.requiredGenerators = 1  -- Un seul générateur par map
Config.jerrycansPerGenerator = 3  -- Nombre de jerrycans nécessaires par générateur
Config.policeDelay = 60
Config.debugMode = true  -- Set to true to disable role checks for testing

return Config
