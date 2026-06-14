local CONFIG = {
    -- Peripheral sides (nil = auto-find via peripheral.find)
    jukeboxSide = nil,      -- e.g. "left", "right", "top", "bottom"
    detectorSide = nil,     -- e.g. "front", "back"

    -- Maximum distance in blocks to detect players.
    -- The entity detector's raw range is ~17x33x17 centered on the block.
    -- Set to nil to use full detector range.
    range = 15,

    -- Behavior
    stopWhenEmpty = true,      -- stop playing when zero players in range

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
