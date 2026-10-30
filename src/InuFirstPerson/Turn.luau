--!strict
-- How far a character's facing is turned from the view (the twist), for a
-- character that turns with the camera in first person. Standing still, the
-- feet stay put, so the twist grows as the view turns, until it passes the
-- threshold; then the body swings round to the view over a fixed time while
-- keeping up with it. Moving (or holding a Tool), the body swings round the
-- same way and from then on turns with the view exactly.
--
-- The swing is a function of the time since it began, and a threshold
-- crossed partway through a frame starts it partway through, so a steady
-- turn gives the same twist at any frame rate. Requires only Math, so the
-- Lune tests can load it outside Roblox.

local Math = require(script.Parent.Math)

-- A twist this small counts as facing the view.
local ALIGNED = math.rad(0.5)

export type State = {
	-- Body yaw minus view yaw, in radians; nil until the first step.
	twist: number?,
	-- The view's yaw at the last step.
	lastYaw: number,
	-- While swinging round: the twist the swing began from, and the time since.
	swingFrom: number?,
	swingTime: number,
	-- Turning with the view exactly.
	locked: boolean,
}

local Turn = {}

function Turn.new(): State
	return { lastYaw = 0, swingTime = 0, locked = false }
end

-- The next step starts from `twist` (radians, body yaw minus view yaw) with
-- the view at `yaw`, as when the character is taken over with its feet where
-- they are.
function Turn.reset(state: State, twist: number, yaw: number)
	state.twist = twist
	state.lastYaw = yaw
	state.swingFrom = nil
	state.swingTime = 0
	state.locked = false
end

local function smoothstep(share: number): number
	local x = math.clamp(share, 0, 1)
	return x * x * (3 - 2 * x)
end

local function startSwing(state: State, from: number, elapsed: number)
	state.swingFrom = from
	state.swingTime = elapsed
end

-- Advances to the view's `yaw` and returns the twist (radians). `follow` is
-- true while the body should end up turning with the view (moving, holding a
-- Tool). `threshold` and `limit` are radians, `swingTime` seconds.
function Turn.step(
	state: State,
	yaw: number,
	follow: boolean,
	threshold: number,
	limit: number,
	swingTime: number,
	dt: number
): number
	local twist = state.twist
	if twist == nil then
		state.twist = 0
		state.lastYaw = yaw
		state.locked = follow
		return 0
	end
	local turned = Math.shortestAngle(yaw - state.lastYaw)
	state.lastYaw = yaw

	if state.locked then
		if follow then
			state.twist = 0
			return 0
		end
		-- Stopping: the feet stay where the view was a frame ago.
		state.locked = false
		twist = 0
	end

	local from = state.swingFrom
	if from == nil then
		local before = twist
		local after = math.clamp(twist - turned, -limit, limit)
		if follow then
			if math.abs(after) < ALIGNED then
				state.locked = true
				state.twist = 0
				return 0
			end
			startSwing(state, after, 0)
		elseif math.abs(after) > threshold then
			if math.abs(before) < threshold and after ~= before then
				-- The view turned past the threshold partway through the
				-- frame; the swing began there.
				local crossing = if after > 0 then threshold else -threshold
				startSwing(state, crossing, (after - crossing) / (after - before) * dt)
			else
				-- Already past it, as when taken over facing away.
				startSwing(state, after, dt)
			end
		else
			state.twist = after
			return after
		end
	else
		state.swingTime += dt
	end

	local swingFrom = state.swingFrom :: number
	local over = state.swingTime - math.max(swingTime, 0)
	if over >= 0 then
		-- The swing ended partway through the frame; standing, the feet have
		-- stayed put since, while the view went on turning.
		state.swingFrom = nil
		state.locked = follow
		local result = if follow or dt <= 0 then 0 else -turned * math.min(over / dt, 1)
		state.twist = result
		return result
	end
	local result = swingFrom * (1 - smoothstep(state.swingTime / swingTime))
	state.twist = result
	return result
end

return Turn
