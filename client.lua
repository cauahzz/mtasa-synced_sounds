local sounds3DByElement = {} -- [element][index] = entry
local sounds3DByIndex = {} -- [index] = entry (3D sounds placed by position)
local sounds2D = {} -- [index] = entry
local entryBySound = {} -- [soundElement] = entry
local startedServerIds = {} -- [server_id] = true

local MAX_SEEK_ATTEMPTS = 10
local RESYNC_TOLERANCE = 0.3 -- seconds

-- Only clears the slot if it still holds this entry: a replacement may already be registered there
local function forgetEntry(entry)
    if entry.store[entry.key] == entry then
        entry.store[entry.key] = nil
    end

    entryBySound[entry.soundElement] = nil
end

local function removeEntry(entry)
    if not entry then
        return
    end

    forgetEntry(entry)
    if isElement(entry.soundElement) then
        stopSound(entry.soundElement)
    end
end

local function registerEntry(store, key, soundElement, data)
    local entry = { soundElement = soundElement, data = data, store = store, key = key }
    store[key] = entry
    entryBySound[soundElement] = entry
    return entry
end

local function findEntry(index, element)
    if element then
        local byElement = sounds3DByElement[element]
        return byElement and byElement[index]
    end

    return sounds3DByIndex[index] or sounds2D[index]
end

-- Where the sound should be right now, in seconds. Returns nil when a non-looping sound has already ended.
local function getServerPosition(entry, serverTime, length)
    -- Clamped: the client clock estimate can land slightly before the start tick
    local elapsed = math.max((serverTime - entry.data.server_startTick) / 1000, 0)

    if length > 0 and elapsed >= length then
        if not entry.data.loop then
            return nil
        end

        elapsed = elapsed % length
    end

    return elapsed
end

local function seekToServerPosition(entry, length, attempt)
    local soundElement = entry.soundElement
    if not isElement(soundElement) then
        return
    end

    -- Without the server time there is nothing to seek to: let it play instead of
    -- holding it paused. resyncSounds fixes the position once the time arrives.
    local serverTime = getServerTime()
    if not serverTime then
        setSoundPaused(soundElement, false)
        return
    end

    local position = getServerPosition(entry, serverTime, length)
    if not position then
        removeEntry(entry)
        return
    end

    -- Paused so nothing is heard from the wrong spot while the seek is retried
    setSoundPaused(soundElement, true)

    if length <= 0 or setSoundPosition(soundElement, position) then
        setSoundPaused(soundElement, false)
        return
    end

    -- The stream may not accept seeking yet
    if attempt < MAX_SEEK_ATTEMPTS then
        -- A closure, not timer arguments: setTimer copies table arguments, and the retry needs this very entry
        setTimer(function()
            seekToServerPosition(entry, length, attempt + 1)
        end, 100 * (attempt + 1), 1)
    else
        outputDebugString('[synced_sounds] Could not sync the position of sound ' .. tostring(entry.data.index), 2)
        setSoundPaused(soundElement, false)
    end
end

-- onClientSoundStream only fires for streams; local files are seekable as soon as they are created
local function syncStartPosition(entry)
    if entry.data.server_startTick and not isStream(entry.data.path) then
        seekToServerPosition(entry, getSoundLength(entry.soundElement) or 0, 0)
    end
end

local function handlePlaySound3D(data)
    assert(type(data) == 'table', "Bad argument event @ playSound3D (table expected at argument 1, got " .. type(data) .. ")")
    assert(data.element ~= nil or type(data.pos) == 'table', "Bad argument 1 event @ playSound3D (element or position expected in table, got nil)")
    assert(type(data.path) == 'string', "Bad argument 1 event @ playSound3D (string path expected in table, got " .. type(data.path) .. ")")
    assert(isValidIndex(data.index), "Bad argument 1 event @ playSound3D (string/int index expected in table, got " .. type(data.index) .. ")")

    --[[
    data = {
        element = element or pos = { x, y, z }
        index = string,
        path = string ,
        [ -- OPTIONAL
            volume = int,
            maxDistance = int,
            minDistance = int,
            loop = boolean,
            throttled = boolean,
            dimension = int,
            interior = int
        ]
    }
    ]]

    applyDefaults(data, DEFAULTS_3D)

    local x, y, z, store
    if data.element ~= nil then
        assert(isElement(data.element), "Bad argument event @ playSound3D (element expected in table, got element doesn't exist)")

        x, y, z = getElementPosition(data.element)
        sounds3DByElement[data.element] = sounds3DByElement[data.element] or {}
        store = sounds3DByElement[data.element]
    else
        x, y, z = data.pos[1], data.pos[2], data.pos[3]
        assert(type(x) == 'number' and type(y) == 'number' and type(z) == 'number', "Bad argument event @ playSound3D (pos expected as { x, y, z })")
        store = sounds3DByIndex
    end

    removeEntry(store[data.index])

    local soundElement = playSound3D(data.path, x, y, z, data.loop, data.throttled)
    if not soundElement then
        return false
    end

    local entry = registerEntry(store, data.index, soundElement, data)

    setSoundVolume(soundElement, tonumber(data.volume) or DEFAULTS_3D.volume)
    setSoundMaxDistance(soundElement, tonumber(data.maxDistance) or DEFAULTS_3D.maxDistance)
    setSoundMinDistance(soundElement, tonumber(data.minDistance) or DEFAULTS_3D.minDistance)

    if data.element ~= nil then
        attachElements(soundElement, data.element)

        data.interior = data.interior or getElementInterior(data.element)
        data.dimension = data.dimension or getElementDimension(data.element)
    end

    setElementInterior(soundElement, tonumber(data.interior) or 0)
    setElementDimension(soundElement, tonumber(data.dimension) or 0)

    syncStartPosition(entry)

    return true
end
registerEvent('syncedSounds:playSound3D', root, handlePlaySound3D)

local function handlePlaySound(data)
    assert(type(data) == 'table', "Bad argument event @ playSound (table expected at argument 1, got " .. type(data) .. ")")
    assert(type(data.path) == 'string', "Bad argument 1 event @ playSound (string path expected in table, got " .. type(data.path) .. ")")
    assert(isValidIndex(data.index), "Bad argument 1 event @ playSound (string/int index expected in table, got " .. type(data.index) .. ")")

    --[[
    data = {
        index = string,
        path = string ,
        [ -- OPTIONAL
            volume = int,
            loop = boolean,
            throttled = boolean,
        ]
    }
    ]]

    applyDefaults(data, DEFAULTS_2D)

    removeEntry(sounds2D[data.index])

    local soundElement = playSound(data.path, data.loop, data.throttled)
    if not soundElement then
        return false
    end

    local entry = registerEntry(sounds2D, data.index, soundElement, data)
    setSoundVolume(soundElement, tonumber(data.volume) or DEFAULTS_2D.volume)

    syncStartPosition(entry)

    return true
end
registerEvent('syncedSounds:playSound', root, handlePlaySound)

local function handleStopSound(index, element)
    assert(isValidIndex(index), "Bad argument 1 event @ stopSound (string/int expected in argument 1, got " .. type(index) .. ")")

    local entry = findEntry(index, element)
    if not entry then
        return false
    end

    local wasPlaying = isElement(entry.soundElement)
    removeEntry(entry)

    return wasPlaying
end
registerEvent('syncedSounds:stopSound', root, handleStopSound)

local function handleSetSoundVolume(volume, index, element)
    assert(tonumber(volume), "Bad argument 1 event @ setSoundVolume (number expected in argument 1, got " .. type(volume) .. ")")
    assert(isValidIndex(index), "Bad argument 2 event @ setSoundVolume (string/int expected in argument 2, got " .. type(index) .. ")")

    local entry = findEntry(index, element)
    if not entry then
        return false
    end

    if not isElement(entry.soundElement) then
        removeEntry(entry)
        return false
    end

    setSoundVolume(entry.soundElement, tonumber(volume))

    return true
end
registerEvent('syncedSounds:setSoundVolume', root, handleSetSoundVolume)

-- Sound that ended (or was destroyed) on its own: just clear the record
local function forgetSound(soundElement)
    local entry = entryBySound[soundElement]
    if entry then
        forgetEntry(entry)
    end
end

addEventHandler('onClientElementDestroy', root, function()
    local byElement = sounds3DByElement[source]
    if byElement then
        for _, entry in pairs(byElement) do
            removeEntry(entry)
        end
        sounds3DByElement[source] = nil
    end

    forgetSound(source)
end)

addEventHandler('onClientSoundStopped', root, function(reason)
    if reason == 'finished' then
        forgetSound(source)
    end
end)

addEventHandler('onClientSoundStream', root, function(success, length)
    local entry = entryBySound[source]

    if success and entry and entry.data.server_startTick then
        seekToServerPosition(entry, length, 0)
    end
end)

local function resyncEntry(entry, serverTime)
    local soundElement = entry.soundElement
    if not entry.data.server_startTick or not isElement(soundElement) then
        return
    end

    -- A stream that hasn't loaded yet has no length; onClientSoundStream seeks it when it does
    local length = getSoundLength(soundElement) or 0
    if length <= 0 then
        return
    end

    local elapsed = getServerPosition(entry, serverTime, length)
    if not elapsed then
        removeEntry(entry)
        return
    end

    local drift = math.abs((getSoundPosition(soundElement) or 0) - elapsed)
    if entry.data.loop then
        -- Either side of the loop point is the same spot
        drift = math.min(drift, length - drift)
    end

    -- Seeking causes an audible skip, so sounds already in place are left alone
    if drift > RESYNC_TOLERANCE then
        setSoundPosition(soundElement, elapsed)
    end
end

-- Sent by servertimesync's server side: when the client first gets the server time, and on each
-- periodic clock correction. The time comes in the event itself, so this doesn't depend on
-- servertimesync's own handler having stored it first.
registerEvent('onServerTimeUpdate', root, function(serverTime)
    if type(serverTime) ~= 'number' then
        return
    end

    -- Entries may be removed while looping: clearing existing keys during pairs is safe
    for _, entry in pairs(entryBySound) do
        resyncEntry(entry, serverTime)
    end
end)

local function playFromServer(play, data)
    -- One broken sound must not stop the others from playing
    local ok, result = pcall(play, data)

    if not ok then
        outputDebugString('[synced_sounds] Error playing sound ' .. tostring(data.index) .. ': ' .. tostring(result), 1)
    elseif not result then
        outputDebugString('[synced_sounds] Could not start sound ' .. tostring(data.index), 2)
    end

    return ok and result == true
end

registerEvent('syncedSounds:syncSounds', root, function(serverSounds3D, serverSounds)
    local wanted = {}
    for _, sound in ipairs(serverSounds3D) do
        wanted[sound.server_id] = true
    end
    for _, sound in ipairs(serverSounds) do
        wanted[sound.server_id] = true
    end

    for _, entry in pairs(entryBySound) do
        if entry.data.server_id and not wanted[entry.data.server_id] then
            removeEntry(entry)
        end
    end

    for id in pairs(startedServerIds) do
        if not wanted[id] then
            startedServerIds[id] = nil
        end
    end

    -- Each broadcast is started once per server_id: a non-looping sound that already
    -- ended stays in the server list and must not restart on the next sync.
    -- A sound that failed to start is left unmarked, so the next sync retries it.
    for _, sound in ipairs(serverSounds3D) do
        -- element unavailable on this client and no pos: nowhere to play it, retry on the next sync
        if (sound.element or sound.pos) and not startedServerIds[sound.server_id] then
            startedServerIds[sound.server_id] = playFromServer(handlePlaySound3D, sound) or nil
        end
    end

    for _, sound in ipairs(serverSounds) do
        if not startedServerIds[sound.server_id] then
            startedServerIds[sound.server_id] = playFromServer(handlePlaySound, sound) or nil
        end
    end
end)
