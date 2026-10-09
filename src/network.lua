-- Client side of the network: one ENet connection to the server plus an inbox of decoded JSON messages.
-- Messages are tables {type = "...", ...}; the protocol is documented at the top of server.lua.
-- Never blocks: poll() must be called every frame and moves received messages into the inbox, the game
-- scenes then take them with pop(). All state is module-local, so there is exactly one connection.

local json = require "dkjson"

local network = {}

-- ENet host (our local endpoint) and the peer that represents the server; nil while not connected.
local host
local server
-- Connection state, see get_status().
local status = "idle" -- idle | connecting | connected | disconnected | failed | closed
-- Received messages that nobody took yet (oldest first).
local inbox = {}

-- Drops the connection and frees the ENet host. Everything is wrapped in pcall because the peer or host may
-- already be invalid (e.g. after a lost connection) and cleanup must never raise.
local function release()
    if server ~= nil then
        -- disconnect_now does not wait for the graceful handshake: a normal disconnect needs more service()
        -- calls to finish, but the host is destroyed right after this (on quit or when leaving to the
        -- menu).
        pcall(server.disconnect_now, server)
    end

    if host ~= nil then
        -- Flush first so the disconnect packet really leaves before the host goes away.
        pcall(host.flush, host)
        -- Not every lua-enet build has destroy().
        if host.destroy then
            pcall(host.destroy, host)
        end
    end

    host = nil
    server = nil
end

-- Starts connecting to `address` ("host:port"). Returns true when the attempt was started (status becomes
-- "connecting", the outcome arrives later through poll()), false when it could not even be started
-- (status "failed"). Any previous connection is dropped and the inbox is cleared.
function network.connect(address)
    release()
    inbox = {}
    status = "connecting"

    local enet = require "enet"

    local ok_host, new_host = pcall(enet.host_create)
    if not ok_host or new_host == nil then
        status = "failed"
        return false
    end
    host = new_host

    local ok_peer, peer = pcall(host.connect, host, address)
    if not ok_peer or peer == nil then
        release()
        status = "failed"
        return false
    end
    server = peer

    return true
end

-- Closes the connection for good (status "closed"); used when the game quits or goes back to the menu.
function network.close()
    release()
    inbox = {}
    status = "closed"
end

-- Returns "idle", "connecting", "connected", "disconnected" (lost after having been connected),
-- "failed" (could not connect) or "closed" (closed by us).
function network.get_status()
    return status
end

-- True while the connection is established.
function network.is_connected()
    return status == "connected"
end

-- Services ENet without waiting (timeout 0): handles every pending event, updates the status and appends
-- decoded messages to the inbox. Call it once per frame.
function network.poll()
    if host == nil then return end

    local ok, event = pcall(host.service, host, 0)

    while ok and event do
        if event.type == "connect" then
            status = "connected"
        -- A disconnect before the connect event means the connection attempt itself failed.
        elseif event.type == "disconnect" then
            status = (status == "connecting") and "failed" or "disconnected"
        elseif event.type == "receive" then
            local ok_decode, message = pcall(json.decode, event.data)
            -- Only JSON objects with a string "type" are valid protocol messages; anything else is dropped.
            if ok_decode and type(message) == "table" and type(message.type) == "string" then
                table.insert(inbox, message)
            end
        end

        ok, event = pcall(host.service, host, 0)
    end

    -- host:service raised an error: treat the connection as lost.
    if not ok then
        status = "disconnected"
    end
end

-- Removes and returns the oldest received message, or nil if the inbox is empty.
function network.pop()
    return table.remove(inbox, 1)
end

-- True when an unprocessed message of this type is waiting in the inbox (the message stays there). The
-- layoff scene uses it to notice "game_over" without consuming messages that belong to the game scene.
function network.has_message(message_type)
    for _, message in ipairs(inbox) do
        if message.type == message_type then
            return true
        end
    end
    return false
end

-- Encodes `message` (a table) as JSON and sends it to the server. Returns true when it was queued, false
-- when there is no established connection.
function network.send(message)
    if server == nil or status ~= "connected" then return false end
    return pcall(server.send, server, json.encode(message))
end

return network
