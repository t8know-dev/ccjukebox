local CONFIG = {
    -- Peripheral sides (nil = auto-find via peripheral.find)
    jukeboxSide = "minecraft:jukebox_0",      -- e.g. "left", "right", "top", "bottom"
    detectorSide = "entity_detector_2",     -- e.g. "front", "back"

    -- Maximum distance in blocks to detect players.
    -- The entity detector's raw range is ~17x33x17 centered on the block.
    -- Uses the relative coordinates returned by nearbyEntities().
    -- Set to nil to use full detector range.
    range = 3,

    -- Periodic fallback scan interval (seconds). 0 = disable.
    -- Catches missed events and handles edge cases.
    -- Also used to poll for a disc appearing in the jukebox.
    scanInterval = 5,

    -- Minimum time between play/stop actions (seconds)
    cooldown = 1,

    -- Debug logging
    debug = true,
}

return CONFIG
