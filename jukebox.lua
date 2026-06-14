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

-- { [uuid] = true } – players currently in range
local players = {}
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
-- Distance filter
------------------------------------------------------------------------
local function isInRange(entity)
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

local function stopPlaying()
    if not isPlaying then return end
    if cooldownUntil > nowMs() then return end

    local ok, err = pcall(jukebox.stop, jukebox)
    if not ok then
        debug("stop error: %s", tostring(err))
        return
    end
    isPlaying = false
    cooldownUntil = nowMs() + CONFIG.cooldown * 1000
    debug(">> stopped <<")
end

------------------------------------------------------------------------
-- Player tracking
------------------------------------------------------------------------
local function onPlayerEnter(uuid, name)
    if players[uuid] then return end
    players[uuid] = true
    debug("+ %s", name or uuid)
    if not isPlaying then
        startPlaying()
    end
end

local function onPlayerLeave(uuid)
    if not players[uuid] then return end
    players[uuid] = nil
    debug("- player (remaining: %d)", tableCount(players))
    if next(players) == nil and isPlaying and CONFIG.stopWhenEmpty then
        stopPlaying()
    end
end

------------------------------------------------------------------------
-- Event handlers
------------------------------------------------------------------------

-- Entity detector fires new_entity / removed_entity with an array of entities
local function handleEventEntityArray(entities, entered)
    if type(entities) ~= "table" then return end
    for _, entity in ipairs(entities) do
        if entity and entity.isPlayer and isInRange(entity) then
            local uuid = entity.uuid or entity.name
            if entered then
                onPlayerEnter(uuid, entity.name)
            else
                onPlayerLeave(uuid)
            end
        end
    end
end

-- nearbyEntities() returns an array
local function handleScanEntities(entities)
    if type(entities) ~= "table" then return end

    local detected = {}
    for _, e in ipairs(entities) do
        if e.isPlayer and isInRange(e) then
            detected[e.uuid or e.name] = e.name or "?"
        end
    end

    -- Additions
    for uuid, name in pairs(detected) do
        if not players[uuid] then
            onPlayerEnter(uuid, name)
        end
    end
    -- Removals
    for uuid in pairs(players) do
        if not detected[uuid] then
            onPlayerLeave(uuid)
        end
    end
end

------------------------------------------------------------------------
-- Main loop
------------------------------------------------------------------------
local function main()
    setup()

    -- Initial scan: catch players already in range
    local ok, entities = pcall(function() return detector.nearbyEntities() end)
    if ok then
        handleScanEntities(entities)
    else
        debug("initial scan failed: %s", tostring(entities))
    end

    -- Start playing immediately if a disc is already in the jukebox
    local disc = jukebox.getDisc()
    if disc then
        debug("disc found on startup: %s", disc.displayName or disc.name or "?")
        startPlaying()
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
            if not isPlaying and jukebox.getDisc() then
                debug("disc appeared in jukebox!")
                startPlaying()
            end

            -- Periodic entity scan
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
