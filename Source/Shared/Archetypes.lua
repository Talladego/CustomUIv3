if not CustomUI then
    CustomUI = {}
end

if not CustomUI.Archetypes then
    CustomUI.Archetypes = {}
end

CustomUI.Archetypes.TANK = 1
CustomUI.Archetypes.DPS  = 2
CustomUI.Archetypes.HEAL = 3

CustomUI.Archetypes.RGB = {
    [CustomUI.Archetypes.TANK] = { 140, 178, 255 },
    [CustomUI.Archetypes.DPS]  = { 255, 176, 82 },
    [CustomUI.Archetypes.HEAL] = { 175, 255, 90 },
}

CustomUI.Archetypes.CareerMapping = {
    [GameData.CareerLine.IRON_BREAKER]   = CustomUI.Archetypes.TANK,
    [GameData.CareerLine.SWORDMASTER]    = CustomUI.Archetypes.TANK,
    [GameData.CareerLine.CHOSEN]         = CustomUI.Archetypes.TANK,
    [GameData.CareerLine.BLACK_ORC]      = CustomUI.Archetypes.TANK,
    [GameData.CareerLine.KNIGHT]         = CustomUI.Archetypes.TANK,
    [GameData.CareerLine.BLACKGUARD]     = CustomUI.Archetypes.TANK,
    [GameData.CareerLine.WITCH_HUNTER]   = CustomUI.Archetypes.DPS,
    [GameData.CareerLine.WHITE_LION]     = CustomUI.Archetypes.DPS,
    [GameData.CareerLine.MARAUDER]       = CustomUI.Archetypes.DPS,
    [GameData.CareerLine.WITCH_ELF]      = CustomUI.Archetypes.DPS,
    [GameData.CareerLine.BRIGHT_WIZARD]  = CustomUI.Archetypes.DPS,
    [GameData.CareerLine.MAGUS]          = CustomUI.Archetypes.DPS,
    [GameData.CareerLine.SORCERER]       = CustomUI.Archetypes.DPS,
    [GameData.CareerLine.ENGINEER]       = CustomUI.Archetypes.DPS,
    [GameData.CareerLine.SHADOW_WARRIOR] = CustomUI.Archetypes.DPS,
    [GameData.CareerLine.SQUIG_HERDER]   = CustomUI.Archetypes.DPS,
    [GameData.CareerLine.CHOPPA]         = CustomUI.Archetypes.DPS,
    [GameData.CareerLine.WARRIOR_PRIEST] = CustomUI.Archetypes.HEAL,
    [GameData.CareerLine.DISCIPLE]       = CustomUI.Archetypes.HEAL,
    [GameData.CareerLine.ARCHMAGE]       = CustomUI.Archetypes.HEAL,
    [GameData.CareerLine.SHAMAN]         = CustomUI.Archetypes.HEAL,
    [GameData.CareerLine.RUNE_PRIEST]    = CustomUI.Archetypes.HEAL,
    [GameData.CareerLine.ZEALOT]         = CustomUI.Archetypes.HEAL,
}

if GameData.CareerLine.SLAYER then
    CustomUI.Archetypes.CareerMapping[GameData.CareerLine.SLAYER] = CustomUI.Archetypes.DPS
end
if GameData.CareerLine.HAMMERER then
    CustomUI.Archetypes.CareerMapping[GameData.CareerLine.HAMMERER] = CustomUI.Archetypes.DPS
end

function CustomUI.Archetypes.GetArchetypeForCareerLine(careerLine)
    if not careerLine then return nil end
    return CustomUI.Archetypes.CareerMapping[careerLine]
end

function CustomUI.Archetypes.GetColorForCareerLine(careerLine)
    local arch = CustomUI.Archetypes.GetArchetypeForCareerLine(careerLine)
    local rgb = arch and CustomUI.Archetypes.RGB[arch]
    if rgb then
        return rgb[1], rgb[2], rgb[3]
    end
    return nil, nil, nil
end
