--!strict
-- The body's facing trailing the camera's yaw. The yaw is unwrapped so a turn
-- through ±180 degrees is not a jump, and the lag is the exact first-order lag
-- for a turn at a steady rate within each frame, so a steady turn trails by
-- the same angle at any frame rate. Requires only Math, so the desk tests can
-- load it outside Roblox.

local Math = require(script.Parent.Math)

export type State = {
	-- Unwrapped yaws in radians; target is nil until the first step.
	target: number?,
	current: number,
}

local TurnLag = {}

function TurnLag.new(): State
	return { current = 0 }
end

-- The next step snaps to the yaw it is given.
function TurnLag.reset(state: State)
	state.target = nil
end

-- Returns the trailing yaw for the camera's `yaw` now. `lagTime` is the time
-- constant of the lag and `maxLag` caps how far it trails, both in seconds
-- and radians.
function TurnLag.step(
	state: State,
	yaw: number,
	lagTime: number,
	maxLag: number,
	dt: number
): number
	local previous = state.target
	if previous == nil then
		state.target = yaw
		state.current = yaw
		return yaw
	end
	local target = previous + Math.shortestAngle(yaw - previous)
	local current = Math.follow(state.current, previous, target, lagTime, dt)
	state.current = target + math.clamp(current - target, -maxLag, maxLag)
	state.target = target
	return state.current
end

return TurnLag
