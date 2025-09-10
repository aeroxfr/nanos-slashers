local MapConfig = {}

-- Spawn locations
MapConfig.survivorSpawns = {
    Vector(0, 0, 100),
    Vector(100, 0, 100),
    Vector(200, 0, 100),
    Vector(300, 0, 100),
    Vector(400, 0, 100)
}

MapConfig.slasherSpawns = {
    Vector(500, 0, 100),
    Vector(600, 0, 100)
}

-- Stage items locations
MapConfig.jerrycanLocations = {
    Vector(100, 0, 100),
    Vector(200, 0, 100),
    Vector(300, 0, 100)
}

MapConfig.generatorLocations = {
    Vector(400, 0, 100),
    Vector(500, 0, 100),
    Vector(600, 0, 100)
}

MapConfig.radioLocation = Vector(700, 0, 100)
MapConfig.exitZoneCenter = Vector(800, 0, 100)
MapConfig.policeSpawn = Vector(900, 0, 100)

-- Killer model
MapConfig.killerModel = "nanos-world::SK_PostApocalyptic"
MapConfig.survivorModel = "nanos-world::SK_Male"

return MapConfig
