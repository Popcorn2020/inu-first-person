--!strict
-- How a character's neck and waist share where its player looks, from the
-- look relative to the body (yaw left, pitch up, radians). The head takes the
-- look at once and the upper body its share a moment later, so a quick look
-- shows the head first and the chest after it, then the body (Turn). The
-- head takes only part of a look up or down; the eyes take the rest.
--
-- The neck turns only so far. A look further round than the head reaches,
-- which no head could follow, lets it go rather than holding it at the limit:
-- the head eases back to the front, and takes the look up again once it
-- comes back past a margin, so a look near the edge does not flicker between
-- the two. A quick look holds the head at the neck's limit only until the
-- waist catches up. Requires only Math, so the Lune tests can load it.

local Math = require(script.Parent.Math)

-- A look that let the head go takes it up again this far inside the angle.
local LOOK_AWAY_MARGIN = math.rad(20)
-- How quickly the head eases to the front on letting go, and back.
local LOOK_AWAY_TIME = 0.15
-- A neck that takes almost all of the turn would leave no room for the
-- waist's share: the reach stops at this.
local MAX_REACH = math.pi

export type Settings = {
	-- Radians: how far the neck itself turns, and the look past which the
	-- head lets go (never further than its reach).
	neckYawLimit: number,
	lookAwayAngle: number,
	-- Shares: of a look up or down, what the head takes; of the head's turn,
	-- what the waist takes.
	headPitchShare: number,
	waistShare: number,
	-- Seconds the waist trails the head by.
	waistLag: number,
}

export type State = {
	-- 0..1: how much of the look the head shows.
	weight: number,
	away: boolean,
	-- The waist's turn and tilt as they trail the head, and the targets they
	-- trailed at the last step (nil before the first).
	waistYaw: number,
	waistPitch: number,
	waistYawTarget: number?,
	waistPitchTarget: number?,
	-- The result of the last step, radians relative to the body: the head as
	-- a whole, and the part of it each joint takes.
	headYaw: number,
	headPitch: number,
	neckYaw: number,
	neckPitch: number,
}

local LookPose = {}

function LookPose.new(): State
	return {
		weight = 1,
		away = false,
		waistYaw = 0,
		waistPitch = 0,
		headYaw = 0,
		headPitch = 0,
		neckYaw = 0,
		neckPitch = 0,
	}
end

-- Back to a head facing the front, as for a new character.
function LookPose.reset(state: State)
	state.weight = 1
	state.away = false
	state.waistYaw = 0
	state.waistPitch = 0
	state.waistYawTarget = nil
	state.waistPitchTarget = nil
	state.headYaw = 0
	state.headPitch = 0
	state.neckYaw = 0
	state.neckPitch = 0
end

-- How far the head as a whole may turn: the neck's own reach, and with a
-- waist the share the waist adds to it.
function LookPose.getReach(settings: Settings, hasWaist: boolean): number
	if not hasWaist then
		return settings.neckYawLimit
	end
	local rest = 1 - settings.waistShare
	if rest <= 0 then
		return MAX_REACH
	end
	return math.min(settings.neckYawLimit / rest, MAX_REACH)
end

-- Advances to the look `yaw`, `pitch` and leaves the pose in the state.
-- `scale` (0..1) fades the whole pose, as when first person eases in;
-- `ownView` keeps the waist from bending forward or back.
function LookPose.step(
	state: State,
	yaw: number,
	pitch: number,
	settings: Settings,
	hasWaist: boolean,
	ownView: boolean,
	scale: number,
	dt: number
)
	local reach = LookPose.getReach(settings, hasWaist)
	local letGo = math.min(settings.lookAwayAngle, reach)
	local distance = math.abs(yaw)
	if state.away then
		if distance < letGo - math.min(LOOK_AWAY_MARGIN, letGo / 2) then
			state.away = false
		end
	elseif distance > letGo then
		state.away = true
	end
	state.weight = Math.approach(state.weight, if state.away then 0 else 1, LOOK_AWAY_TIME, dt)

	local shown = state.weight * scale
	local headYaw = math.clamp(yaw, -reach, reach) * shown
	local headPitch = pitch * settings.headPitchShare * shown
	local share = if hasWaist then settings.waistShare else 0
	local yawTarget = headYaw * share
	local pitchTarget = if ownView then 0 else headPitch * share
	state.waistYaw = Math.follow(
		state.waistYaw,
		state.waistYawTarget or yawTarget,
		yawTarget,
		settings.waistLag,
		dt
	)
	state.waistPitch = Math.follow(
		state.waistPitch,
		state.waistPitchTarget or pitchTarget,
		pitchTarget,
		settings.waistLag,
		dt
	)
	state.waistYawTarget = yawTarget
	state.waistPitchTarget = pitchTarget

	-- Until the waist catches up with a quick look, the neck stops at its
	-- limit and the head waits with it.
	local limit = settings.neckYawLimit
	state.neckYaw = math.clamp(headYaw - state.waistYaw, -limit, limit)
	state.neckPitch = headPitch - state.waistPitch
	state.headYaw = state.waistYaw + state.neckYaw
	state.headPitch = headPitch
end

return LookPose
