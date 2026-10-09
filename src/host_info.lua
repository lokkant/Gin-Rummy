-- Works out the addresses another player can use to join a game hosted on this computer (client only).
-- Used by scenes/start_menu.lua and shown by client/overlays.lua while the host waits for the opponent.

local host_info = {}

-- Returns this computer's address in the local network (e.g. "192.168.0.12") or nil if it can't be found.
-- A UDP socket is "connected" to a public address, which sends nothing but makes the system pick the
-- network interface it would use; the address of that interface is what other computers see in the LAN.
local function get_lan_ip()
    local ok, socket = pcall(require, "socket")
    if not ok then return nil end

    local udp = socket.udp()
    if udp == nil then return nil end

    local ip
    if udp:setpeername("8.8.8.8", 80) then
        ip = udp:getsockname()
    end
    udp:close()

    -- 0.0.0.0 comes back when there is no network at all
    if ip == nil or ip == "0.0.0.0" then return nil end
    return ip
end

-- Returns the list of "ip:port" strings to show to the other player: the local network address first (when
-- known), then 127.0.0.1 which only works for a second game window on this very computer.
function host_info.get_addresses(port)
    local addresses = {}

    local lan_ip = get_lan_ip()
    if lan_ip ~= nil then
        table.insert(addresses, lan_ip .. ":" .. port)
    end

    table.insert(addresses, "127.0.0.1:" .. port)

    return addresses
end

return host_info
