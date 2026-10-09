local json = require "dkjson"

local network = {}

local host
local server
local status = "idle" -- idle | connecting | connected | disconnected | failed | closed
local inbox = {}

local function release()
    if server ~= nil then
        pcall(server.disconnect_now, server)
    end

    if host ~= nil then
        pcall(host.flush, host)
        if host.destroy then
            pcall(host.destroy, host)
        end
    end

    host = nil
    server = nil
end

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

function network.close()
    release()
    inbox = {}
    status = "closed"
end

function network.get_status()
    return status
end

function network.is_connected()
    return status == "connected"
end

function network.poll()
    if host == nil then return end

    local ok, event = pcall(host.service, host, 0)

    while ok and event do
        if event.type == "connect" then
            status = "connected"
        elseif event.type == "disconnect" then
            status = (status == "connecting") and "failed" or "disconnected"
        elseif event.type == "receive" then
            local ok_decode, message = pcall(json.decode, event.data)
            if ok_decode and type(message) == "table" and type(message.type) == "string" then
                table.insert(inbox, message)
            end
        end

        ok, event = pcall(host.service, host, 0)
    end

    if not ok then
        status = "disconnected"
    end
end

function network.pop()
    return table.remove(inbox, 1)
end

function network.has_message(message_type)
    for _, message in ipairs(inbox) do
        if message.type == message_type then
            return true
        end
    end
    return false
end

function network.send(message)
    if server == nil or status ~= "connected" then return false end
    return pcall(server.send, server, json.encode(message))
end

return network
