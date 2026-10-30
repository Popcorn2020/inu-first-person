--!strict
-- The look sync's wire format, shared by the client (Sync) and the server
-- half (InuFirstPersonServer, which is built with its own copy of this file).
-- A look is a player's view relative to their character's facing, sent as
-- two int16, yaw then pitch, each a share of half a turn: 4 bytes, steps of
-- about 0.005 degrees. Requires nothing, so the Lune tests can load it.

local SCALE = 32767 / math.pi
-- Pitch past straight up or down is no view a camera gives.
local MAX_PITCH = math.round(math.pi / 2 * SCALE)

local SyncProtocol = {}

-- The UnreliableRemoteEvent the server half makes under the InuFirstPerson
-- module.
SyncProtocol.REMOTE_NAME = "InuFirstPersonLook"
SyncProtocol.LOOK_SIZE = 4
-- Updates a second the server takes from each player.
SyncProtocol.MAX_SEND_RATE = 30

-- Radians to the sent value, and back.
function SyncProtocol.quantize(angle: number): number
	return math.clamp(math.round(angle * SCALE), -32767, 32767)
end

function SyncProtocol.angle(value: number): number
	return value / SCALE
end

-- Writes the look at `index` (from 0) of a buffer of looks.
function SyncProtocol.write(data: buffer, index: number, yaw: number, pitch: number)
	local offset = index * SyncProtocol.LOOK_SIZE
	buffer.writei16(data, offset, yaw)
	buffer.writei16(data, offset + 2, math.clamp(pitch, -MAX_PITCH, MAX_PITCH))
end

function SyncProtocol.read(data: buffer, index: number): (number, number)
	local offset = index * SyncProtocol.LOOK_SIZE
	local yaw = buffer.readi16(data, offset)
	local pitch = math.clamp(buffer.readi16(data, offset + 2), -MAX_PITCH, MAX_PITCH)
	return yaw, pitch
end

return SyncProtocol
