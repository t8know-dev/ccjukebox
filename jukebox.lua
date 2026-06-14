--[[
ccjukebox  –  Automatically plays music discs in a jukebox when
players are detected nearby via an entity detector.

Usage:
  jukebox.lua

Edit config.lua to change peripheral sides, range, disc, etc.
]]

local CONFIG = require("config")

------------------------------------------------------------------------
-- Peripherals & state
------------------------------------------------------------------------
local jukebox = nil
local detector = nil

-- { [uuid] = true } – players currently within the detector's max range
-- (17x33x17 area centered on the block). Playing continues as long as
-- at least one player is in this set, and we only start when someone
-- enters the smaller trigger range.
local playersInDetector = {}
local isPlaying = false
local cooldownUntil = 0      -- os.epoch("utc") millis

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function nowMs()
    return os.epoch("utc")
end

local function debug(msg, ...)
    if CONFIG.debug then
        print(string.format("[%s] " .. msg, os.date("%H:%M:%S"), ...))
    end
end

local detectorPos = nil

local function sq(x) return x * x end

local function tableCount(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

------------------------------------------------------------------------
-- Distance filter – small trigger range
------------------------------------------------------------------------
local function isInSmallRange(entity)
    if not CONFIG.range then return true end
    local dp = detectorPos
    if not dp then return true end
    local d2 = sq(entity.x - dp.x) + sq(entity.y - dp.y) + sq(entity.z - dp.z)
    return d2 <= CONFIG.range * CONFIG.range
end

------------------------------------------------------------------------
-- Peripheral setup
------------------------------------------------------------------------

local function setup()
    -- Jukebox
    if CONFIG.jukeboxSide then
        jukebox = peripheral.wrap(CONFIG.jukeboxSide)
    else
        jukebox = peripheral.find("jukebox")
    end
    if not jukebox then error("jukebox not found") end
    debug("jukebox OK")

    -- Entity detector – try the given side or auto-find
    if CONFIG.detectorSide then
        detector = peripheral.wrap(CONFIG.detectorSide)
    else
        detector = peripheral.find("entity_detector")
    end
    if not detector then error("entity_detector not found") end
    debug("detector OK")

    -- Use detector position from config (required when range is set)
    detectorPos = CONFIG.detectorPos
    if CONFIG.range and not detectorPos then
        debug("WARNING: range is set but detectorPos is nil in config — range disabled")
    end
end

------------------------------------------------------------------------
-- Jukebox control
------------------------------------------------------------------------
local function startPlaying()
    if isPlaying then return end
    if cooldownUntil > nowMs() then return end

    if not jukebox.getDisc() then
        debug("cannot play — no disc in jukebox")
        return
    end

    local ok, err = pcall(jukebox.replay, jukebox)
    if not ok then
        debug("replay error: %s", tostring(err))
        return
    end
    isPlaying = true
    cooldownUntil = nowMs() + CONFIG.cooldown * 1000
    debug(">> playing <<")
end

local function stopPlaying(reason)
    if not isPlaying then return end
    if cooldownUntil > nowMs() then return end

    local ok, err = pcall(jukebox.stop, jukebox)
    if not ok then
        debug("stop error: %s", tostring(err))
        return
    end
    isPlaying = false
    cooldownUntil = nowMs() + CONFIG.cooldown * 1000
    debug(">> stopped (%s) <<", reason or "no reason")
end

------------------------------------------------------------------------
-- Player tracking (detector's max range = 17x33x17 area)
------------------------------------------------------------------------
local function onPlayerInDetector(uuid, name, entity)
    if playersInDetector[uuid] then return end
    playersInDetector[uuid] = true
    debug("+ %s entered detector range", name or uuid)
    -- Start playing if this player is within the small trigger range
    if not isPlaying and entity and isInSmallRange(entity) then
        startPlaying()
    end
end

local function onPlayerOutOfDetector(uuid, name)
    if not playersInDetector[uuid] then return end
    playersInDetector[uuid] = nil
    local remaining = tableCount(playersInDetector)
    debug("- %s left detector range (remaining: %d)", name or uuid, remaining)
    if remaining == 0 and isPlaying then
        stopPlaying("no players in detector range")
    end
end

------------------------------------------------------------------------
-- Event handlers
------------------------------------------------------------------------

-- Entity detector fires new_entity / removed_entity with an array of entities
local function handleEventEntityArray(entities, entered)
    if type(entities) ~= "table" then return end
    for _, entity in ipairs(entities) do
        if entity and entity.isPlayer then
            local uuid = entity.uuid or entity.name
            if entered then
                onPlayerInDetector(uuid, entity.name, entity)
            else
                onPlayerOutOfDetector(uuid, entity.name)
            end
        end
    end
end

-- nearbyEntities() returns an array of all entities within detector's max range
local function handleScanEntities(entities)
    if type(entities) ~= "table" then return end

    local detected = {}
    for _, e in ipairs(entities) do
        if e.isPlayer then
            detected[e.uuid or e.name] = e
        end
    end

    -- Additions (players newly seen in detector range)
    for uuid, entity in pairs(detected) do
        if not playersInDetector[uuid] then
            onPlayerInDetector(uuid, entity.name, entity)
        end
    end
    -- Removals (players no longer in detector range)
    for uuid in pairs(playersInDetector) do
        if not detected[uuid] then
            onPlayerOutOfDetector(uuid, uuid)
        end
    end

    -- If not playing but some player is within the small trigger range,
    -- try to start (e.g. a disc was inserted while they were nearby).
    if not isPlaying and next(playersInDetector) then
        for _, e in ipairs(entities) do
            if e.isPlayer and isInSmallRange(e) then
                startPlaying()
                break
            end
        end
    end
end

------------------------------------------------------------------------
-- Main loop
------------------------------------------------------------------------
local function main()
    setup()

    -- Initial scan: catch players already in detector range
    local ok, entities = pcall(function() return detector.nearbyEntities() end)
    if ok then
        handleScanEntities(entities)
    else
        debug("initial scan failed: %s", tostring(entities))
    end

    -- Log disc status (playing is started by player presence, not boot)
    local disc = jukebox.getDisc()
    if disc then
        debug("disc present on startup: %s", disc.displayName or disc.name or "?")
    else
        debug("no disc on startup — waiting for one...")
    end

    -- Periodic fallback scan
    if CONFIG.scanInterval > 0 then
        os.startTimer(CONFIG.scanInterval)
    end

    while true do
        local ev = { os.pullEvent() }
        local name = ev[1]

        if name == "new_entity" or name == "removed_entity" then
            -- ev[2] = peripheral side, ev[3] = array of entity tables
            handleEventEntityArray(ev[3], name == "new_entity")
        elseif name == "timer" then
            -- If not playing, poll for a disc that may have appeared
            if not isPlaying and next(playersInDetector) and jukebox.getDisc() then
                debug("disc appeared in jukebox!")
                startPlaying()
            end

            -- Periodic entity scan (handles new/removed players and
            -- starts playing if someone is within small range)
            local ok2, entities2 = pcall(function() return detector.nearbyEntities() end)
            if ok2 then
                handleScanEntities(entities2)
            else
                debug("scan failed: %s", tostring(entities2))
            end
            if CONFIG.scanInterval > 0 then
                os.startTimer(CONFIG.scanInterval)
            end
        end
    end
end

local ok, err = pcall(main)
if not ok then
    printError("ccjukebox: " .. tostring(err))
end
