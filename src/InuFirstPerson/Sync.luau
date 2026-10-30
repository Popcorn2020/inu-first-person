--!strict
-- Shares where the local player looks with the others, through the remote
-- the server half (InuFirstPersonServer) makes under this module. Without
-- the server half there is no remote, and nothing is sent.
--
-- A look goes out only while it changes, at most Config.sync.sendRate a
-- second, and a couple of times more once it holds still, in case the
-- unreliable remote dropped the last change. The others' looks come back
-- from the server in batches.

local Players = game:GetService("Players")

local Shared = require(script.Parent.Shared)
local SyncProtocol = require(script.Parent.SyncProtocol)

-- Changes smaller than this (radians) are not sent.
local MIN_CHANGE = math.rad(0.25)
-- Once the look holds still, it is sent this many times more, this far apart.
local RESENDS = 2
local RESEND_PERIOD = 0.5
-- Sends of the look straight ahead on stopping, as the unreliable remote may
-- drop one and nothing follows it.
local FINAL_SENDS = 3

export type Look = {
	-- Radians, relative to the character's facing: yaw left, pitch up.
	yaw: number,
	pitch: number,
}

local Sync = {}

local player = Players.LocalPlayer
local container = script.Parent

local running = false
local remote: UnreliableRemoteEvent? = nil
local remoteConnections: { RBXScriptConnection } = {}
local connections: { RBXScriptConnection } = {}
local looks: { [Player]: Look } = {}

local outgoing = buffer.create(SyncProtocol.LOOK_SIZE)
local sentYaw = 0
local sentPitch = 0
local sinceSend = math.huge
local resendsLeft = 0

local function receive(players: unknown, data: unknown)
	if typeof(players) ~= "table" or typeof(data) ~= "buffer" then
		return
	end
	local size = buffer.len(data)
	-- A Player who has left arrives as nil, so the list may have holes.
	for index, other in players :: { [unknown]: unknown } do
		if
			typeof(index) == "number"
			and index * SyncProtocol.LOOK_SIZE <= size
			and typeof(other) == "Instance"
			and other:IsA("Player")
			and other ~= player
			and other.Parent == Players
		then
			local yaw, pitch = SyncProtocol.read(data, index - 1)
			local look = looks[other]
			if not look then
				look = { yaw = 0, pitch = 0 }
				looks[other] = look
			end
			look.yaw = SyncProtocol.angle(yaw)
			look.pitch = SyncProtocol.angle(pitch)
		end
	end
end

local function unbind()
	for _, connection in remoteConnections do
		connection:Disconnect()
	end
	remoteConnections = {}
	remote = nil
	table.clear(looks)
end

local function bind(child: Instance)
	if
		remote
		or child.Name ~= SyncProtocol.REMOTE_NAME
		or not child:IsA("UnreliableRemoteEvent")
	then
		return
	end
	local event = child :: UnreliableRemoteEvent
	remote = event
	sinceSend = math.huge
	resendsLeft = 0
	remoteConnections = {
		event.OnClientEvent:Connect(receive),
		event.AncestryChanged:Connect(function()
			if not event:IsDescendantOf(game) then
				unbind()
			end
		end),
	}
end

function Sync.start()
	running = true
	connections = {
		container.ChildAdded:Connect(bind),
		Players.PlayerRemoving:Connect(function(other: Player)
			looks[other] = nil
		end),
	}
	local existing = container:FindFirstChild(SyncProtocol.REMOTE_NAME)
	if existing then
		bind(existing)
	end
end

function Sync.stop()
	if not running then
		return
	end
	running = false
	for _, connection in connections do
		connection:Disconnect()
	end
	connections = {}
	unbind()
end

-- Sends the look straight ahead at once, before this client stops sending,
-- so the others do not keep the last look.
function Sync.sendStraight()
	local event = remote
	if not event or not Shared.config.sync.enabled then
		return
	end
	SyncProtocol.write(outgoing, 0, 0, 0)
	for _ = 1, FINAL_SENDS do
		event:FireServer(outgoing)
	end
	sentYaw, sentPitch = 0, 0
end

-- The latest looks of the other players, by player. Read only.
function Sync.getLooks(): { [Player]: Look }
	return looks
end

-- Offers the local player's look (radians) each step; sends it when due.
function Sync.offer(yaw: number, pitch: number, dt: number)
	sinceSend += dt
	local event = remote
	local settings = Shared.config.sync
	if not event or not settings.enabled or settings.sendRate <= 0 then
		return
	end
	if sinceSend < 1 / settings.sendRate then
		return
	end
	local changed = math.abs(yaw - sentYaw) >= MIN_CHANGE
		or math.abs(pitch - sentPitch) >= MIN_CHANGE
	if changed then
		resendsLeft = RESENDS
	elseif resendsLeft > 0 and sinceSend >= RESEND_PERIOD then
		resendsLeft -= 1
	elseif sinceSend ~= math.huge then
		return
	end
	SyncProtocol.write(outgoing, 0, SyncProtocol.quantize(yaw), SyncProtocol.quantize(pitch))
	event:FireServer(outgoing)
	sentYaw = yaw
	sentPitch = pitch
	sinceSend = 0
end

return Sync
