--!strict
-- The camera's motion worked out from plain numbers about the character:
-- head bob, strafe lean, hand-held sway, breathing, the landing dip, step
-- smoothing, the sprint field of view and kicks. Camera feeds it each frame
-- and puts the result on the Roblox camera. It touches no Instances, so the
-- desk tests can run it at any frame rate outside Roblox.

local Config = require(script.Parent.Config)
local Math = require(script.Parent.Math)

local TWO_PI = 2 * math.pi
-- The bob rests and starts again at this phase, where every part of it is 0.
local BOB_REST_PHASE = -math.pi / 2
-- Below this the bob counts as stopped and its phase goes back to rest.
local BOB_STOPPED_SCALE = 1e-3
-- The noise time wraps at this period to keep math.noise precise. The jump at
-- the wrap is far below what the eye can see at the sway's sizes.
local NOISE_TIME_WRAP = 4096
-- The air brings the step offset back this many times faster than the ground,
-- so a jump is not smoothed.
local AIR_CATCH_UP = 4

-- What Camera reads off the character each frame. The table is reused.
export type Input = {
	-- Horizontal speed that drives the bob: the root's speed, held down to the
	-- speed the character is walking at so pushing into a wall does not bob.
	-- While climbing, the climbing speed.
	speed: number,
	-- The root's actual horizontal speed, for the step smoothing allowance.
	horizontalSpeed: number,
	-- Walking and full sprinting speed right now, after multipliers.
	walkSpeed: number,
	runSpeed: number,
	-- -1..1. Move input along the camera's right.
	strafe: number,
	grounded: boolean,
	climbing: boolean,
	airborne: boolean,
	-- The root's vertical velocity and height.
	verticalSpeed: number,
	height: number,
	-- 0 with full stamina, 1 with none.
	fatigue: number,
	-- Multiplies every motion (see Config.camera.motionScale).
	motionScale: number,
	-- false in third person, where only kicks and the field of view apply.
	firstPerson: boolean,
}

export type State = {
	time: number,
	-- 0..1. How much of the walking motion shows: 0 in third person, easing
	-- up to 1 after zooming into first person.
	presence: number,
	bobPhase: number,
	bobScale: number,
	tilt: number,
	fatigue: number,
	breathPhase: number,
	wasAirborne: boolean,
	-- The fastest fall since leaving the ground (negative is down).
	airLowestSpeed: number,
	landDrop: number,
	landDropVelocity: number,
	landPitch: number,
	landPitchVelocity: number,
	lastHeight: number?,
	stepOffset: number,
	sprintFov: number,
	kickRotation: Vector3,
	kickRotationVelocity: Vector3,
	kickPosition: Vector3,
	kickPositionVelocity: Vector3,

	-- The result of the last step.
	-- Offset in the camera's own space.
	localPosition: Vector3,
	-- Radians in the camera's own space: X pitch, Y yaw, Z roll.
	localRotation: Vector3,
	-- World-up offset of the camera: the step smoothing plus the landing dip.
	worldHeight: number,
	-- The step smoothing part of worldHeight, which the body follows so it
	-- stays put in the view.
	bodyHeight: number,
	-- Degrees added to the field of view.
	fovOffset: number,
}

local CameraMotion = {}

function CameraMotion.newInput(): Input
	return {
		speed = 0,
		horizontalSpeed = 0,
		walkSpeed = 16,
		runSpeed = 16,
		strafe = 0,
		grounded = true,
		climbing = false,
		airborne = false,
		verticalSpeed = 0,
		height = 0,
		fatigue = 0,
		motionScale = 1,
		firstPerson = true,
	}
end

function CameraMotion.new(): State
	local state = {} :: State
	CameraMotion.reset(state)
	return state
end

-- Back to rest, as for a new character. Kicks in flight are dropped too.
function CameraMotion.reset(state: State)
	state.time = 0
	state.presence = 0
	state.bobPhase = BOB_REST_PHASE
	state.bobScale = 0
	state.tilt = 0
	state.fatigue = 0
	state.breathPhase = 0
	state.wasAirborne = false
	state.airLowestSpeed = 0
	state.landDrop = 0
	state.landDropVelocity = 0
	state.landPitch = 0
	state.landPitchVelocity = 0
	state.lastHeight = nil
	state.stepOffset = 0
	state.sprintFov = 0
	state.kickRotation = Vector3.zero
	state.kickRotationVelocity = Vector3.zero
	state.kickPosition = Vector3.zero
	state.kickPositionVelocity = Vector3.zero
	state.localPosition = Vector3.zero
	state.localRotation = Vector3.zero
	state.worldHeight = 0
	state.bodyHeight = 0
	state.fovOffset = 0
end

-- Starts a kick that swings out to `rotationDegrees` (X pitch up, Y yaw left,
-- Z roll left) and `position` (camera space) and springs back.
function CameraMotion.kick(
	state: State,
	settings: Config.Config,
	rotationDegrees: Vector3,
	position: Vector3
)
	local frequency, damping = settings.kick.frequency, settings.kick.damping
	local share = Math.springKickVelocity(1, frequency, damping)
	local rotation = Vector3.new(
		math.rad(rotationDegrees.X),
		math.rad(rotationDegrees.Y),
		math.rad(rotationDegrees.Z)
	)
	state.kickRotationVelocity += rotation * share
	state.kickPositionVelocity += position * share
end

local function lerp(from: number, to: number, alpha: number): number
	return from + (to - from) * alpha
end

local function stepSpring3(
	position: Vector3,
	velocity: Vector3,
	frequency: number,
	damping: number,
	dt: number
): (Vector3, Vector3)
	local x, vx = Math.spring(position.X, velocity.X, 0, frequency, damping, dt)
	local y, vy = Math.spring(position.Y, velocity.Y, 0, frequency, damping, dt)
	local z, vz = Math.spring(position.Z, velocity.Z, 0, frequency, damping, dt)
	return Vector3.new(x, y, z), Vector3.new(vx, vy, vz)
end

type SwayBand = {
	frequency: number,
	position: Vector3,
	rotationDegrees: Vector3,
}

-- Six channels (position XYZ, then pitch, yaw, roll) of one band, each in
-- -1..1 times its size. `channelBase` keeps the bands' noise apart.
local function sampleSway(
	band: SwayBand,
	seed: number,
	time: number,
	channelBase: number
): (Vector3, Vector3)
	local x = time * band.frequency
	local function sample(channel: number): number
		return math.clamp(math.noise(x, seed * 1000 + (channelBase + channel) * 19.19) * 2, -1, 1)
	end
	local position = Vector3.new(sample(0), sample(1), sample(2)) * band.position
	local degrees = Vector3.new(sample(3), sample(4), sample(5)) * band.rotationDegrees
	return position, Vector3.new(math.rad(degrees.X), math.rad(degrees.Y), math.rad(degrees.Z))
end

-- 0 at walking speed or slower, 1 at full sprinting speed.
local function getSprintBlend(input: Input): number
	if input.runSpeed <= input.walkSpeed then
		return 0
	end
	return math.clamp((input.speed - input.walkSpeed) / (input.runSpeed - input.walkSpeed), 0, 1)
end

local function stepBob(
	state: State,
	settings: Config.Config,
	input: Input,
	sprintBlend: number,
	dt: number
)
	local bob = settings.bob
	local moveRatio = input.speed / bob.referenceSpeed
	local stepping = (input.grounded or input.climbing) and moveRatio > 0

	local targetScale = 0
	if stepping then
		local kind = if input.climbing
			then bob.climbScale
			else 1 + (bob.sprintScale - 1) * sprintBlend
		targetScale = math.min(moveRatio, 1) * kind
	end
	state.bobScale = Math.approach(state.bobScale, targetScale, bob.responseTime, dt)

	-- The phase keeps the last speed's pace while the bob eases out, so the
	-- steps wind down instead of freezing; it stops with the character.
	local cadence = if stepping then bob.frequency * moveRatio ^ bob.cadencePower else 0
	state.bobPhase = (state.bobPhase + TWO_PI * cadence * dt) % TWO_PI
	if targetScale == 0 and state.bobScale < BOB_STOPPED_SCALE then
		state.bobPhase = BOB_REST_PHASE
	end
end

local function stepLanding(state: State, settings: Config.Config, input: Input, dt: number)
	local landing = settings.landing
	if input.airborne then
		state.wasAirborne = true
		state.airLowestSpeed = math.min(state.airLowestSpeed, input.verticalSpeed)
	elseif state.wasAirborne then
		state.wasAirborne = false
		local impact = -state.airLowestSpeed
		state.airLowestSpeed = 0
		local span = landing.maxSpeed - landing.minSpeed
		local share = if span > 0
			then math.clamp((impact - landing.minSpeed) / span, 0, 1)
			elseif impact >= landing.minSpeed then 1
			else 0
		if share > 0 then
			local kick = Math.springKickVelocity(share, landing.frequency, landing.damping)
			state.landDropVelocity -= kick * landing.drop
			state.landPitchVelocity -= kick * math.rad(landing.pitchDegrees)
		end
	end
	state.landDrop, state.landDropVelocity = Math.spring(
		state.landDrop,
		state.landDropVelocity,
		0,
		landing.frequency,
		landing.damping,
		dt
	)
	state.landPitch, state.landPitchVelocity = Math.spring(
		state.landPitch,
		state.landPitchVelocity,
		0,
		landing.frequency,
		landing.damping,
		dt
	)
end

local function stepSmoothing(state: State, settings: Config.Config, input: Input, dt: number)
	local smoothing = settings.stepSmoothing
	local lastHeight = state.lastHeight or input.height
	local rise = input.height - lastHeight
	state.lastHeight = input.height

	if smoothing.responseTime <= 0 or math.abs(rise) > smoothing.teleportDistance then
		state.stepOffset = 0
		return
	end
	if input.grounded then
		-- Only the part of the rise faster than walking up a slope could make
		-- is held back, so slopes pass through with no delay.
		local allowed = (smoothing.allowance + input.horizontalSpeed) * dt
		local excess = rise - math.clamp(rise, -allowed, allowed)
		state.stepOffset =
			math.clamp(state.stepOffset - excess, -smoothing.maxOffset, smoothing.maxOffset)
	end
	local responseTime = if input.grounded
		then smoothing.responseTime
		else smoothing.responseTime / AIR_CATCH_UP
	state.stepOffset = Math.approach(state.stepOffset, 0, responseTime, dt)
end

-- Advances the motion by `dt` seconds and leaves the result in the state's
-- result fields.
function CameraMotion.step(state: State, settings: Config.Config, input: Input, dt: number)
	local scale = input.motionScale
	local sprintBlend = getSprintBlend(input)
	state.time = (state.time + dt) % NOISE_TIME_WRAP
	-- Leaving first person drops the motion at once, since it would shake the
	-- orbiting camera; coming back eases it in.
	state.presence = if input.firstPerson
		then Math.approach(state.presence, 1, settings.camera.transitionTime, dt)
		else 0

	stepBob(state, settings, input, sprintBlend, dt)
	stepLanding(state, settings, input, dt)
	stepSmoothing(state, settings, input, dt)

	local tiltTarget = -math.clamp(input.strafe, -1, 1) * math.rad(settings.strafeTilt.degrees)
	state.tilt = Math.approach(state.tilt, tiltTarget, settings.strafeTilt.responseTime, dt)

	local breathing = settings.breathing
	state.fatigue =
		Math.approach(state.fatigue, math.clamp(input.fatigue, 0, 1), breathing.responseTime, dt)
	local fatigue = state.fatigue
	state.breathPhase = (
		state.breathPhase + TWO_PI * lerp(breathing.rate, breathing.tiredRate, fatigue) * dt
	) % TWO_PI
	local breath = math.sin(state.breathPhase)
	local breathPitch = math.rad(lerp(breathing.pitchDegrees, breathing.tiredPitchDegrees, fatigue))
		* breath
	local breathHeight = lerp(breathing.height, breathing.tiredHeight, fatigue) * breath

	local sway = settings.sway
	local swayScale = 1 + (sway.tiredScale - 1) * fatigue
	local driftPosition, driftRotation = sampleSway(sway.drift, sway.seed, state.time, 0)
	local jitterPosition, jitterRotation = sampleSway(sway.jitter, sway.seed, state.time, 6)
	local swayPosition = (driftPosition + jitterPosition) * swayScale
	local swayRotation = (driftRotation + jitterRotation) * swayScale

	local fovTarget = settings.sprintFov.degrees * sprintBlend
	state.sprintFov = Math.approach(state.sprintFov, fovTarget, settings.sprintFov.responseTime, dt)

	state.kickRotation, state.kickRotationVelocity = stepSpring3(
		state.kickRotation,
		state.kickRotationVelocity,
		settings.kick.frequency,
		settings.kick.damping,
		dt
	)
	state.kickPosition, state.kickPositionVelocity = stepSpring3(
		state.kickPosition,
		state.kickPositionVelocity,
		settings.kick.frequency,
		settings.kick.damping,
		dt
	)

	local bob = settings.bob
	local phase = state.bobPhase
	local bobSize = state.bobScale
	local bobPosition = Vector3.new(
		math.cos(phase) * bob.amplitude.X,
		math.sin(2 * phase) * bob.amplitude.Y,
		math.sin(2 * phase) * bob.amplitude.Z
	) * bobSize
	local bobRoll = math.rad(bob.rollDegrees) * math.cos(phase) * bobSize

	local presence = state.presence
	local walkingPosition = bobPosition + Vector3.new(0, breathHeight, 0) + swayPosition
	local walkingRotation = Vector3.new(breathPitch + state.landPitch, 0, bobRoll + state.tilt)
		+ swayRotation
	state.localPosition = (walkingPosition * presence + state.kickPosition) * scale
	state.localRotation = (walkingRotation * presence + state.kickRotation) * scale
	-- The step smoothing steadies the view rather than moving it, so the
	-- motion scale leaves it alone.
	state.worldHeight = (state.stepOffset + state.landDrop * scale) * presence
	state.bodyHeight = state.stepOffset * presence
	state.fovOffset = state.sprintFov * scale
end

return CameraMotion
