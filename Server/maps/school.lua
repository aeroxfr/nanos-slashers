local MapConfig = {}

-- Spawn locations
MapConfig.survivorSpawns = {
    Vector(-151089.26219033, -119612.56948287, 5040.5116728712),
    Vector(-158373.0904784, -119166.36892358, 4828.8135267483),
    Vector(-152956.76063367, -123811.27870233, 5004.2928827518)
}

MapConfig.slasherSpawns = {
    Vector(-155024.88500397, -109065.03340545, 4999.3044111373),
    Vector(-163930.77476381, -115655.81964756, 5097.9267677183),
}

-- Stage items locations
MapConfig.jerrycanLocations = {
    Vector(-156437.45121668, -114191.39888854, 5018.2020241537),
    Vector(-151074.7976018, -115213.64574943, 4987.3732240448),
    Vector(-150550.62375625, -120250.03856972, 5072.6722770619)
}

MapConfig.generatorLocations = {
    Vector(-152796.53858294, -113781.92508321, 4981.2059643899),
    Vector(-151875.28768567, -123203.80227056, 4991.3658583045),
    Vector(-155518.06451391, -115761.19040823, 4904.7703953169)
}

MapConfig.radioLocation = Vector(-155159.03999104, -115786.31104715, 4927.901915621)
MapConfig.exitZoneCenter = Vector(-154776.10978896, -126859.81310129, 5249.0419940315)
MapConfig.policeSpawn = Vector(-154767.7055525, -127343.61813433, 5358.1555661192)

-- Killer model
MapConfig.killerModel = "nanos-world::SK_PostApocalyptic"
MapConfig.survivorModel = "nanos-world::SK_Male"

return MapConfig
