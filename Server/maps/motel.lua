local MapConfig = {}

-- Spawn locations
MapConfig.survivorSpawns = {
    Vector(-500, 0, 100),
    Vector(-400, 0, 100),
    Vector(-300, 0, 100),
    Vector(-200, 0, 100),
    Vector(-100, 0, 100)
}

MapConfig.slasherSpawns = {
    Vector(0, 0, 100),
    Vector(100, 0, 100)
}

-- Stage items locations
MapConfig.jerrycanLocations = {
    Vector(-400, 50, 100),
    Vector(-300, 50, 100),
    Vector(-200, 50, 100)
}

MapConfig.generatorLocations = {
    Vector(-100, 50, 100),
    Vector(0, 50, 100),
    Vector(100, 50, 100)
}

MapConfig.radioLocation = Vector(200, 50, 100)
MapConfig.exitZoneCenter = Vector(300, 50, 100)
MapConfig.policeSpawn = Vector(400, 50, 100)

-- Models
MapConfig.killerModel = "nanos-world::SK_Mannequin_01"
MapConfig.survivorModel = "nanos-world::SK_Male"

return MapConfig
