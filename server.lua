local sounds3D = {}
local sounds2D = {}
local lastSoundId = 0
local readyPlayers = {} -- [player] = true

local NUMERIC_FIELDS = { 'volume', 'maxDistance', 'minDistance', 'dimension', 'interior', 'duration' }
local BOOLEAN_FIELDS = { 'loop', 'throttled' }

local function reject(caller, reason)
    outputDebugString('[synced_sounds] ' .. caller .. ': ' .. reason, 1)
    return false, reason
end

-- Copies only the known fields: it doesn't mutate the caller's table and keeps
-- stray (or reserved) fields from reaching the clients.
local function buildSoundData(data, is3D)
    if type(data) ~= 'table' then
        return false, 'table expected, got ' .. type(data)
    end

    if type(data.path) ~= 'string' or data.path == '' then
        return false, 'path must be a non-empty string'
    end

    if not isValidIndex(data.index) then
        return false, 'index must be a string or number'
    end

    local sound = { path = data.path, index = data.index }

    if is3D then
        if data.element ~= nil then
            if not isElement(data.element) then
                return false, 'element does not exist'
            end
            sound.element = data.element
        else
            sound.pos = normalizePosition(data.pos)
            if not sound.pos then
                return false, 'element or pos {x, y, z} expected'
            end
        end
    end

    for _, field in ipairs(NUMERIC_FIELDS) do
        if data[field] ~= nil then
            sound[field] = tonumber(data[field])
            if not sound[field] then
                return false, field .. ' must be a number'
            end
        end
    end

    for _, field in ipairs(BOOLEAN_FIELDS) do
        if data[field] ~= nil then
            sound[field] = data[field] == true
        end
    end

    applyDefaults(sound, is3D and DEFAULTS_3D or DEFAULTS_2D)

    -- MTA can't seek a throttled stream, so late joiners would hear it from the start
    if sound.throttled and isStream(sound.path) then
        outputDebugString('[synced_sounds] Sound "' .. tostring(sound.index) .. '" is a URL with throttled = true: ' ..
            'it will play out of sync (from the start) for players who join later. Set throttled = false to fix it.', 2)
    end

    return sound
end

-- server_id lets clients tell a new broadcast from one they already play;
-- server_startTick lets late joiners seek to the current position
local function stampSound(sound)
    lastSoundId = lastSoundId + 1
    sound.server_id = lastSoundId
    sound.server_startTick = getServerTime()
end

-- Iterates backwards because entries are removed while looping
local function removeWhere(list, matches)
    local removed = false

    for i = #list, 1, -1 do
        if matches(list[i]) then
            table.remove(list, i)
            removed = true
        end
    end

    return removed
end

local function upsertSound(list, sound, isSame)
    removeWhere(list, isSame)
    list[#list + 1] = sound
end

local function isExpired(sound, now)
    if sound.element ~= nil and not isElement(sound.element) then
        return true
    end

    -- The server can't know the audio length, so it only expires sounds that came with `duration`
    if sound.duration and not sound.loop and sound.server_startTick and now then
        return now >= sound.server_startTick + sound.duration * 1000
    end

    return false
end

local function pruneExpired()
    local now = getServerTime()
    local function expired(sound)
        return isExpired(sound, now)
    end

    removeWhere(sounds3D, expired)
    removeWhere(sounds2D, expired)
end

-- Players still downloading the resource don't have the events yet; they get a full sync once it starts
local function triggerReadyClients(event, ...)
    local players = {}
    for player in pairs(readyPlayers) do
        players[#players + 1] = player
    end

    if #players > 0 then
        triggerClientEvent(players, event, resourceRoot, ...)
    end
end

-- Always sends the full lists: clients diff them by server_id
local function syncSound(sendTo)
    pruneExpired()

    if sendTo then
        triggerClientEvent(sendTo, 'syncedSounds:syncSounds', resourceRoot, sounds3D, sounds2D)
    else
        triggerReadyClients('syncedSounds:syncSounds', sounds3D, sounds2D)
    end
end

function broadcastSound3D(data)
    local sound, reason = buildSoundData(data, true)
    if not sound then
        return reject('broadcastSound3D', reason)
    end

    stampSound(sound)
    upsertSound(sounds3D, sound, function(other)
        return other.index == sound.index and other.element == sound.element
    end)
    syncSound()

    return true
end

function broadcastSound(data)
    local sound, reason = buildSoundData(data, false)
    if not sound then
        return reject('broadcastSound', reason)
    end

    stampSound(sound)
    upsertSound(sounds2D, sound, function(other)
        return other.index == sound.index
    end)
    syncSound()

    return true
end

function broadcastSetSoundVolume(volume, index, element)
    volume = tonumber(volume)
    if not volume then
        return reject('broadcastSetSoundVolume', 'volume must be a number')
    end

    if not isValidIndex(index) then
        return reject('broadcastSetSoundVolume', 'index must be a string or number')
    end

    local found = false

    for _, sound in ipairs(sounds3D) do
        if sound.index == index and sound.element == element then
            sound.volume = volume
            found = true
        end
    end

    if element == nil then
        for _, sound in ipairs(sounds2D) do
            if sound.index == index then
                sound.volume = volume
                found = true
            end
        end
    end

    if found then
        triggerReadyClients('syncedSounds:setSoundVolume', volume, index, element)
    end

    return found
end

function broadcastStopSound(index, element)
    if not isValidIndex(index) then
        return reject('broadcastStopSound', 'index must be a string or number')
    end

    local removed = removeWhere(sounds3D, function(sound)
        return sound.index == index and sound.element == element
    end)

    if element == nil then
        removed = removeWhere(sounds2D, function(sound)
            return sound.index == index
        end) or removed
    end

    if removed then
        triggerReadyClients('syncedSounds:stopSound', index, element)
    end

    return removed
end

addEventHandler('onPlayerResourceStart', root, function(startedResource)
    if startedResource == resource then
        readyPlayers[source] = true
        syncSound(source)
    end
end)

addEventHandler('onPlayerQuit', root, function()
    readyPlayers[source] = nil
end)

addEventHandler('onElementDestroy', root, function()
    -- Fires for every element destroyed on the server, so skip the work when there is nothing to match
    if #sounds3D == 0 then
        return
    end

    local destroyed = source
    removeWhere(sounds3D, function(sound)
        return sound.element == destroyed
    end)
end)

-- Expired sounds are otherwise only dropped on the next broadcast
setTimer(pruneExpired, 60000, 0)

local function describeSound(sound)
    local target = '-'
    if sound.element ~= nil then
        target = getElementType(sound.element) or 'destroyed'
    elseif sound.pos then
        target = table.concat(sound.pos, ', ')
    end

    return '  - ' .. tostring(sound.index) .. ' | ' .. sound.path .. ' | vol ' .. tostring(sound.volume) ..
        ' | loop ' .. tostring(sound.loop) .. ' | ' .. target
end

-- `restricted = true`: only runs for players with the `command.viewSyncedSounds` right in the ACL
addCommandHandler('viewSyncedSounds', function(player)
    if tostring(get('debug')) ~= 'true' then
        outputChatBox('synced_sounds debug is disabled ("debug" setting).', player)
        return
    end

    outputChatBox('Synced Sounds 3D:', player)
    for _, sound in ipairs(sounds3D) do
        outputChatBox(describeSound(sound), player)
    end

    outputChatBox('Synced Sounds:', player)
    for _, sound in ipairs(sounds2D) do
        outputChatBox(describeSound(sound), player)
    end
end, true)
