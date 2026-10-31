--!strict
-- InuFirstPersonServer
-- https://github.com/Popcorn2020/inu-first-person
--
-- MIT License
--
-- Copyright (c) 2026 inu (@inutataaaaa)
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

-- The server half of InuFirstPerson: it passes on where each player looks,
-- so everyone sees the others' heads and arms turn. It keeps no game state
-- and loads none of the client code. Put it in ServerScriptService and call,
-- from a server Script:
--
--     local InuFirstPersonServer = require(ServerScriptService.InuFirstPersonServer)
--     InuFirstPersonServer.start(ReplicatedStorage.InuFirstPerson)
--
-- It makes an UnreliableRemoteEvent under the client module, takes each
-- player's look (4 bytes, at most SyncProtocol.MAX_SEND_RATE a second) and
-- sends the looks that changed to every client a few times a second, in
-- batches. Everyone's look goes out again now and then, for players who
-- joined since and for updates the unreliable remote dropped.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local SyncProtocol = require(script.SyncProtocol)
local Version = require(script.Version)

local BROADCASTS_PER_SECOND = 15
-- Everyone's look is sent this often, changed or not.
local FULL_PERIOD = 3
-- Updates a player may send at once beyond the steady rate, as after a
-- hitch on their side.
local RECEIVE_BURST = 10
-- Looks per message, well inside an unreliable remote's size limit.
local BATCH_SIZE = 30

type Look = {
	-- As sent: SyncProtocol values.
	yaw: number,
	pitch: number,
	-- Updates this player may still send now; refilled at the steady rate.
	allowance: number,
	changed: boolean,
}

local InuFirstPersonServer = {}

InuFirstPersonServer.version = Version

local remote: UnreliableRemoteEvent? = nil
local connections: { RBXScriptConnection } = {}
local looks: { [Player]: Look } = {}
local sinceBroadcast = 0
local sinceFull = 0

local function receive(player: Player, data: unknown)
	if typeof(data) ~= "buffer" or buffer.len(data) ~= SyncProtocol.LOOK_SIZE then
		return
	end
	local look = looks[player]
	if not look then
		if player.Parent ~= Players then
			return
		end
		look = { yaw = 0, pitch = 0, allowance = RECEIVE_BURST, changed = false }
		looks[player] = look
	end
	if look.allowance < 1 then
		return
	end
	look.allowance -= 1
	local yaw, pitch = SyncProtocol.read(data, 0)
	if yaw ~= look.yaw or pitch ~= look.pitch then
		look.yaw = yaw
		look.pitch = pitch
		look.changed = true
	end
end

local function sendBatch(event: UnreliableRemoteEvent, batch: { Player })
	local data = buffer.create(#batch * SyncProtocol.LOOK_SIZE)
	for index, player in batch do
		local look = looks[player]
		SyncProtocol.write(data, index - 1, look.yaw, look.pitch)
	end
	event:FireAllClients(batch, data)
end

local function broadcast(event: UnreliableRemoteEvent, full: boolean)
	local batch: { Player } = {}
	for player, look in looks do
		if full or look.changed then
			look.changed = false
			table.insert(batch, player)
			if #batch == BATCH_SIZE then
				sendBatch(event, batch)
				batch = {}
			end
		end
	end
	if #batch > 0 then
		sendBatch(event, batch)
	end
end

local function step(dt: number)
	local event = remote
	if not event then
		return
	end
	for _, look in looks do
		look.allowance = math.min(look.allowance + SyncProtocol.MAX_SEND_RATE * dt, RECEIVE_BURST)
	end
	sinceBroadcast += dt
	sinceFull += dt
	if sinceBroadcast < 1 / BROADCASTS_PER_SECOND then
		return
	end
	sinceBroadcast = 0
	local full = sinceFull >= FULL_PERIOD
	if full then
		sinceFull = 0
	end
	broadcast(event, full)
end

-- Starts passing on the looks. `client` is the InuFirstPerson ModuleScript
-- the clients use, whose version must match this one. Errors if already
-- running or called on a client.
function InuFirstPersonServer.start(client: ModuleScript)
	if not RunService:IsServer() then
		error("InuFirstPersonServer runs on the server: start it from a server Script", 2)
	end
	if remote then
		error("InuFirstPersonServer is already running; call stop() first", 2)
	end
	if typeof(client) ~= "Instance" or not client:IsA("ModuleScript") then
		error("InuFirstPersonServer.start takes the InuFirstPerson ModuleScript", 2)
	end
	local versionModule = client:FindFirstChild("Version")
	local clientVersion = if versionModule and versionModule:IsA("ModuleScript")
		then require(versionModule) :: any
		else nil
	if clientVersion ~= Version then
		error(
			`InuFirstPersonServer {Version} needs the InuFirstPerson of the same version, not {client:GetFullName()} ({tostring(
				clientVersion
			)})`,
			2
		)
	end

	local event = Instance.new("UnreliableRemoteEvent")
	event.Name = SyncProtocol.REMOTE_NAME
	event.Parent = client
	remote = event
	sinceBroadcast = 0
	sinceFull = 0
	connections = {
		event.OnServerEvent:Connect(receive),
		RunService.Heartbeat:Connect(step),
		Players.PlayerRemoving:Connect(function(player: Player)
			looks[player] = nil
		end),
	}
end

-- Stops and removes the remote; the clients stop sending.
function InuFirstPersonServer.stop()
	local event = remote
	if not event then
		return
	end
	remote = nil
	for _, connection in connections do
		connection:Disconnect()
	end
	connections = {}
	table.clear(looks)
	event:Destroy()
end

return InuFirstPersonServer
