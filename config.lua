local CONFIG = {
    -- Peripheral sides (nil = auto-find via peripheral.find)
    jukeboxSide = nil,      -- e.g. "left", "right", "top", "bottom"
    detectorSide = nil,     -- e.g. "front", "back"

    -- Maximum distance in blocks to detect players.
    -- The entity detector's raw range is ~17x33x17 centered on the block.
    -- Set to nil to use full detector range.
    range = 15,

    -- Disc management
    autoInject = true,                              -- try to inject a disc if jukebox is empty
    injectFromSide = "back",                        -- adjacent inventory that has the disc
    discQuery = "minecraft:music_disc_13",          -- item query for injectDisc

    -- Behavior
    stopWhenEmpty = true,      -- stop playing when zero players in range

    -- Periodic fallback scan interval (seconds). 0 = disable.
    -- Catches missed events and handles edge cases.
    scanInterval = 5,

    -- Minimum time between play/stop actions (seconds)
    cooldown = 1,

    -- Debug logging
    debug = true,
}

return CONFIG
