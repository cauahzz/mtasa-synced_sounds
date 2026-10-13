-- Generic helpers. Loaded on both sides before client.lua and server.lua (see meta.xml),
-- so these are globals: each script file has its own local scope.

-- Applied by the server on every broadcast, and by the client when a play event is triggered directly
DEFAULTS_3D = {
    volume = 1,
    maxDistance = 20,
    minDistance = 5,
    loop = false,
    throttled = false,
}

DEFAULTS_2D = {
    volume = 1,
    loop = false,
    throttled = false,
}

function registerEvent(event, attached, func)
    addEvent(event, true)
    addEventHandler(event, attached, func)
end

function isValidIndex(index)
    return type(index) == 'string' or type(index) == 'number'
end

function isStream(path)
    return path:find('^%a+://') ~= nil
end

function applyDefaults(data, defaults)
    for key, value in pairs(defaults) do
        if data[key] == nil then
            data[key] = value
        end
    end
end

function normalizePosition(pos)
    if type(pos) ~= 'table' and type(pos) ~= 'userdata' then
        return nil
    end

    local x, y, z = tonumber(pos[1] or pos.x), tonumber(pos[2] or pos.y), tonumber(pos[3] or pos.z)
    if x and y and z then
        return { x, y, z }
    end
end

function getServerTime()
    -- servertimesync may be stopped or not have the time available yet
    local ok, serverTime = pcall(function()
        return exports['servertimesync']:getServerTime()
    end)
    return ok and serverTime or nil
end
