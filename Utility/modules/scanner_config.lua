-- modules/scanner_config.lua
-- Centralized customization for scanner display: colors, hazards, POIs, block classification

local cfg = {}

-- Color palette
cfg.colors = {
  BG = colors.black,
  FRAME = colors.gray,
  POINT = colors.gray,
  ORE = colors.orange,
  FLUID = colors.lightBlue, -- legacy alias
  WATER = colors.lightBlue,
  LAVA = colors.orange,
  WOOD = colors.brown,
  MARK_FG = colors.red,
  MARK_BG = colors.black,
  STATUS = colors.white,
  ERROR = colors.red,
  headerBG = colors.yellow,
  headerFG = colors.black,
}

-- Block classification rules (order matters). First match wins.
-- A rule matches when any of: equals, suffixes, contains, patterns, or tag matches.
-- colorName must be a key in cfg.colors
cfg.classificationRules = {
  -- Differentiate lava vs water
  { name = "lava",  colorName = "LAVA",  equals = {"minecraft:lava"},  suffixes = {":lava"},  contains = {"lava"},  tags = {"minecraft:fluid"} },
  { name = "water", colorName = "WATER", equals = {"minecraft:water"}, suffixes = {":water"}, contains = {"water"}, tags = {"minecraft:fluid"} },
  { name = "ore", colorName = "ORE", contains = {"ore"}, patterns = {":deepslate_.-ore"} },
  { name = "wood", colorName = "WOOD", contains = {"log", "wood"} },
  { name = "point", colorName = "POINT" }, -- default catch-all
}

-- Hazard rules (rendered bottom-third). Order matters in display.
-- blink=true will toggle visibility. colorName maps to cfg.colors.
cfg.hazardRules = {
  { label = "WATER", colorName = "ORE", blink = false, equals = {"minecraft:water"}, suffixes = {":water"} },
  { label = "LAVA", colorName = "ERROR", blink = true, equals = {"minecraft:lava"}, suffixes = {":lava"} },
  { label = "SCULK", colorName = "ERROR", blink = true, contains = {":sculk"} },
  { label = "OBSIDIAN", colorName = "ORE", blink = false, equals = {"minecraft:obsidian"}, suffixes = {":obsidian"} },
  { label = "REINFORCED DEEPSLATE", colorName = "ORE", blink = false, equals = {"minecraft:reinforced_deepslate"}, suffixes = {":reinforced_deepslate"} },
}

-- POI rules (rendered middle-third). Order matters.
-- colorName optional; defaults to STATUS color.
cfg.poiRules = {
  { label = "MOB SPAWNER", equals = {"minecraft:spawner"}, suffixes = {":spawner"} },
  { label = "END PORTAL", suffixes = {":end_portal", ":end_portal_frame"} },
  -- Detect amethyst-related blocks to infer Geodes
  { label = "GEODE",
    contains = {"amethyst"},
    equals = {
      "minecraft:amethyst_block", "minecraft:budding_amethyst",
      "minecraft:amethyst_cluster", "minecraft:small_amethyst_bud",
      "minecraft:medium_amethyst_bud", "minecraft:large_amethyst_bud"
    }
  },
  { label = "STRUCTURE", patterns = {
      "bricks?", "planks", "stairs", "slab", "door", "trapdoor", "glass",
      "concrete", "wool", "terracotta", "lantern", "torch", "fence", "wall",
      "pillar", "polished", "cut_", "chiseled", "bookshelf"
    }
  },
}

return cfg
