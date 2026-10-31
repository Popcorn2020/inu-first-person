--!strict
-- Smoothing and springs that do not depend on the frame rate. Each step is
-- solved exactly over its length, so a second taken in 30 frames and in 240
-- frames ends in the same place. This module requires nothing, so the Lune
-- tests can load it outside Roblox.

local Math = {}

local TWO_PI = 2 * math.pi
-- Damping ratios this close to 1 use the critically damped solution, whose
-- formula has no division by the (vanishing) damped frequency.
local CRITICAL_BAND = 1e-4

-- Moves `current` toward a target that holds still during the step: the gap
-- shrinks to 1/e every `timeConstant` seconds. 0 or less snaps to the target.
function Math.approach(current: number, target: number, timeConstant: number, dt: number): number
	if timeConstant <= 0 then
		return target
	end
	return target + (current - target) * math.exp(-dt / timeConstant)
end

-- A first-order lag behind a target that moved in a straight line from
-- `targetBefore` to `targetAfter` during the step. Exact for that path, so a
-- steady motion leaves the same lag (speed * timeConstant) at any frame rate,
-- which `approach` would not.
function Math.follow(
	current: number,
	targetBefore: number,
	targetAfter: number,
	timeConstant: number,
	dt: number
): number
	if timeConstant <= 0 or dt <= 0 then
		return targetAfter
	end
	local lead = (targetAfter - targetBefore) / dt * timeConstant
	return targetAfter - lead + (current - targetBefore + lead) * math.exp(-dt / timeConstant)
end

-- Steps a damped spring toward `target` and returns the new position and
-- velocity. `frequency` is the undamped frequency in Hz; `damping` is the
-- damping ratio (1 settles without overshoot, below 1 swings past a little,
-- above 1 creeps in).
function Math.spring(
	position: number,
	velocity: number,
	target: number,
	frequency: number,
	damping: number,
	dt: number
): (number, number)
	local omega = TWO_PI * frequency
	if omega <= 0 or dt <= 0 then
		return position, velocity
	end
	local offset = position - target

	if math.abs(damping - 1) <= CRITICAL_BAND then
		local decay = math.exp(-omega * dt)
		local slope = velocity + omega * offset
		return target + (offset + slope * dt) * decay, (velocity - omega * slope * dt) * decay
	elseif damping < 1 then
		local damped = omega * math.sqrt(1 - damping * damping)
		local decay = math.exp(-damping * omega * dt)
		local cosine = math.cos(damped * dt)
		local sine = math.sin(damped * dt)
		local newOffset = decay
			* (offset * cosine + (velocity + damping * omega * offset) / damped * sine)
		local newVelocity = decay
			* (
				velocity * cosine
				- (omega * omega * offset + damping * omega * velocity) / damped * sine
			)
		return target + newOffset, newVelocity
	end

	local root = math.sqrt(damping * damping - 1)
	local fast = -omega * (damping + root)
	local slow = -omega * (damping - root)
	local slowShare = (velocity - fast * offset) / (slow - fast)
	local fastShare = offset - slowShare
	local slowDecay = math.exp(slow * dt)
	local fastDecay = math.exp(fast * dt)
	return target + slowShare * slowDecay + fastShare * fastDecay,
		slowShare * slow * slowDecay + fastShare * fast * fastDecay
end

-- A damped spring chasing a target that moved in a straight line from
-- `targetBefore` to `targetAfter` during the step, solved exactly for that
-- path, as `follow` is for the first-order lag. A steady chase then trails
-- by the same amount (2 * damping * speed / omega) at any frame rate.
function Math.springFollow(
	position: number,
	velocity: number,
	targetBefore: number,
	targetAfter: number,
	frequency: number,
	damping: number,
	dt: number
): (number, number)
	local omega = TWO_PI * frequency
	if omega <= 0 or dt <= 0 then
		return position, velocity
	end
	local speed = (targetAfter - targetBefore) / dt
	local trail = 2 * damping * speed / omega
	-- Where it stands against the steady chase, which a plain spring settles.
	local offset, offsetVelocity =
		Math.spring(position - (targetBefore - trail), velocity - speed, 0, frequency, damping, dt)
	return offset + targetAfter - trail, offsetVelocity + speed
end

-- Lets a spring's motion die away with no pull, as when its target is wherever
-- it happens to be: the damping alone slows it.
function Math.coast(
	position: number,
	velocity: number,
	frequency: number,
	damping: number,
	dt: number
): (number, number)
	local drag = 2 * damping * TWO_PI * frequency
	if drag <= 0 or dt <= 0 then
		return position + velocity * math.max(dt, 0), velocity
	end
	local decay = math.exp(-drag * dt)
	return position + velocity * (1 - decay) / drag, velocity * decay
end

-- The velocity to give a spring at rest so that it swings out to `peak` and
-- back. Lets callers ask for a dip of a size instead of a speed. Only for
-- damping up to 1; above 1 it treats the spring as critically damped.
function Math.springKickVelocity(peak: number, frequency: number, damping: number): number
	local omega = TWO_PI * frequency
	if omega <= 0 then
		return 0
	end
	local zeta = math.clamp(damping, 0, 1)
	local peakShare
	if zeta >= 1 - CRITICAL_BAND then
		-- Critically damped: the swing peaks at t = 1/omega, at v/omega/e.
		peakShare = math.exp(-1)
	elseif zeta <= 0 then
		peakShare = 1
	else
		local root = math.sqrt(1 - zeta * zeta)
		peakShare = math.exp(-zeta / root * math.atan2(root, zeta))
	end
	return peak * omega / peakShare
end

-- The angle wrapped into [-pi, pi), the shortest turn with the same effect.
function Math.shortestAngle(angle: number): number
	return (angle + math.pi) % TWO_PI - math.pi
end

return Math
