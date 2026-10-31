--!strict
-- The camera's motion worked out from plain numbers about the character:
-- head bob, strafe lean, hand-held sway, breathing, the landing dip, step
-- smoothing, the sprint field of view, and kicks with their shake. Camera
-- feeds it each frame and puts the result on the Roblox camera. It touches no Instances, so the
-- Lune tests can run it at any frame rate outside Roblox.

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
-- A kick swinging this many degrees shakes fully at kick.shake 1. The swing
-- is measured as if undamped, about 1.5 times what a kick of 0.3 damping
-- actually reaches.
local FULL_SHAKE_DEGREES = 10

-- What Camera reads off the character each frame. The table is reused.
export type Input = {
	-- Horizontal speed that drives the bob: the root's speed, held down to the
	-- speed the character is walking at so pushing into a wall does not bob.
	-- While climbing, the climbing speed.
	speed: number,
	-- The root's actual horizontal speed, which sets how fast the view climbs
	-- steps.
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
	-- How fast the floor carries the root up: the floor's own vertical speed
	-- plus the climb of its slope along the root's way over it. A step is flat
	-- and still, so it rises at 0 even while the root pops up onto it.
	floorRiseSpeed: number,
	-- workspace.Gravity, to work out the end of a fall between two frames.
	gravity: number,
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
	-- Bob cycles (two steps each) per second, last frame.
	bobCadence: number,
	bobScale: number,
	tilt: number,
	fatigue: number,
	breathPhase: number,
	-- What the bob size, tilt, tiredness and sprint field of view were easing
	-- toward last frame, nil before the first. These eases take the target to
	-- have moved in a straight line over the frame, so an input that ramps up
	-- leaves the same lag at any frame rate.
	bobTarget: number?,
	tiltTarget: number?,
	fatigueTarget: number?,
	fovTarget: number?,
	wasAirborne: boolean,
	-- The fastest fall since leaving the ground (negative is down), and the
	-- height it was seen at.
	airLowestSpeed: number,
	airLowestHeight: number?,
	landDrop: number,
	landDropVelocity: number,
	landPitch: number,
	landPitchVelocity: number,
	-- The last frame's height, floor rise speed and footing, nil height before
	-- the first frame.
	lastHeight: number?,
	lastFloorRiseSpeed: number,
	wasGrounded: boolean,
	stepOffset: number,
	sprintFov: number,
	-- The kick's spring, for rotation (radians) and position, with their
	-- velocities.
	kickRotation: Vector3,
	kickRotationVelocity: Vector3,
	kickPosition: Vector3,
	kickPositionVelocity: Vector3,
	-- Kicks so far, which picks each kick's variation.
	kickCount: number,

	-- The result of the last step.
	-- Offset in the camera's own space.
	localPosition: Vector3,
	-- Radians in the camera's own space: X pitch, Y yaw, Z roll.
	localRotation: Vector3,
	-- World-up offset of the camera: the step smoothing plus the landing dip.
	worldHeight: number,
	-- Degrees added to the field of view.
	fovOffset: number,
	-- How far each part of the motion turns the view this frame, in radians
	-- after the motion scale, and how far the motion moves it, in studs (for
	-- InuFirstPerson.camera.getMotion).
	bobAngle: number,
	swayAngle: number,
	breathAngle: number,
	tiltAngle: number,
	landingAngle: number,
	kickAngle: number,
	shakeAngle: number,
	motionDistance: number,
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
		floorRiseSpeed = 0,
		gravity = 196.2,
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
	state.bobCadence = 0
	state.bobScale = 0
	state.tilt = 0
	state.fatigue = 0
	state.breathPhase = 0
	state.bobTarget = nil
	state.tiltTarget = nil
	state.fatigueTarget = nil
	state.fovTarget = nil
	state.wasAirborne = false
	state.airLowestSpeed = 0
	state.airLowestHeight = nil
	state.landDrop = 0
	state.landDropVelocity = 0
	state.landPitch = 0
	state.landPitchVelocity = 0
	state.lastHeight = nil
	state.lastFloorRiseSpeed = 0
	state.wasGrounded = false
	state.stepOffset = 0
	state.sprintFov = 0
	state.kickRotation = Vector3.zero
	state.kickRotationVelocity = Vector3.zero
	state.kickPosition = Vector3.zero
	state.kickPositionVelocity = Vector3.zero
	state.kickCount = 0
	state.localPosition = Vector3.zero
	state.localRotation = Vector3.zero
	state.worldHeight = 0
	state.fovOffset = 0
	state.bobAngle = 0
	state.swayAngle = 0
	state.breathAngle = 0
	state.tiltAngle = 0
	state.landingAngle = 0
	state.kickAngle = 0
	state.shakeAngle = 0
	state.motionDistance = 0
end

-- -1..1, the same for the same seed, kick and channel. A hash of the count
-- rather than a Random, so a seed's kicks repeat in the tests.
local function variationOf(seed: number, count: number, channel: number): number
	return math.clamp(
		math.noise(count * 1.618 + 0.37, seed * 3.17 + channel * 7.31, 0.5) * 2,
		-1,
		1
	)
end

-- Starts a kick that swings out to about `rotationDegrees` (X pitch up, Y
-- yaw left, Z roll left) and `position` (camera space) and wobbles back to
-- rest on one spring, each swing smaller than the last by the same share,
-- with a fine shake that dies away with the wobble.
function CameraMotion.kick(
	state: State,
	settings: Config.Config,
	rotationDegrees: Vector3,
	position: Vector3
)
	local kick = settings.kick
	state.kickCount += 1
	local size = rotationDegrees.Magnitude
	local spread = kick.variation * size
	local varied = rotationDegrees
		+ Vector3.new(
			0,
			variationOf(kick.seed, state.kickCount, 1) * spread,
			variationOf(kick.seed, state.kickCount, 2) * spread
		)
	local rotation = Vector3.new(math.rad(varied.X), math.rad(varied.Y), math.rad(varied.Z))

	local impulse = Math.springKickVelocity(1, kick.frequency, kick.damping)
	state.kickRotationVelocity += rotation * impulse
	state.kickPositionVelocity += position * impulse
end

-- How far a spring's swing reaches from rest now, wherever in the swing it
-- is: it falls off smoothly as the wobble dies, with no dips where the
-- swing turns. Radians, over the three axes.
local function swingSize(
	position: Vector3,
	velocity: Vector3,
	frequency: number,
	damping: number
): number
	local omega = 2 * math.pi * frequency
	if omega <= 0 then
		return position.Magnitude
	end
	if damping >= 1 then
		-- No swing: where it is and how far its speed still carries it.
		return (position + velocity / omega).Magnitude
	end
	local damped = omega * math.sqrt(1 - damping * damping)
	local lead = (velocity + position * damping * omega) / damped
	return math.sqrt(position:Dot(position) + lead:Dot(lead))
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
	state.bobScale = Math.follow(
		state.bobScale,
		state.bobTarget or targetScale,
		targetScale,
		bob.responseTime,
		dt
	)
	state.bobTarget = targetScale

	-- The phase stops with the character, and the shrinking scale brings the
	-- view back to rest from wherever the step was. It advances by the pace
	-- at both ends of the frame, so speeding up shifts it the same at any
	-- frame rate.
	local cadence = if stepping then bob.frequency * moveRatio ^ bob.cadencePower else 0
	state.bobPhase = (state.bobPhase + math.pi * (state.bobCadence + cadence) * dt) % TWO_PI
	state.bobCadence = cadence
	if targetScale == 0 and state.bobScale < BOB_STOPPED_SCALE then
		state.bobPhase = BOB_REST_PHASE
	end
end

local function stepLanding(state: State, settings: Config.Config, input: Input, dt: number)
	local landing = settings.landing
	if input.airborne then
		state.wasAirborne = true
		if input.verticalSpeed < state.airLowestSpeed then
			state.airLowestSpeed = input.verticalSpeed
			state.airLowestHeight = input.height
		end
	elseif state.wasAirborne then
		state.wasAirborne = false
		-- The fall goes on for part of a frame after the last look at it; the
		-- height lost since gives the speed at touchdown, which is then the
		-- same at any frame rate.
		local lowestHeight = state.airLowestHeight
		local drop = if lowestHeight then math.max(lowestHeight - input.height, 0) else 0
		local impact = math.sqrt(state.airLowestSpeed ^ 2 + 2 * input.gravity * drop)
		state.airLowestSpeed = 0
		state.airLowestHeight = nil
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

-- How far the floor carried the root up over a frame, from its rise speeds at
-- the frame's two ends. The slower end counts, so stepping onto a slope or a
-- lift between two frames is not credited for the whole frame.
local function riseFromFloor(before: number, after: number, dt: number): number
	if before > 0 and after > 0 then
		return math.min(before, after) * dt
	elseif before < 0 and after < 0 then
		return math.max(before, after) * dt
	end
	return 0
end

local function stepSmoothing(state: State, settings: Config.Config, input: Input, dt: number)
	local smoothing = settings.stepSmoothing
	local lastHeight = state.lastHeight
	local lastFloorRiseSpeed = state.lastFloorRiseSpeed
	local wasGrounded = state.wasGrounded
	state.lastHeight = input.height
	state.lastFloorRiseSpeed = input.floorRiseSpeed
	state.wasGrounded = input.grounded

	if not smoothing.enabled or lastHeight == nil then
		state.stepOffset = 0
		return
	end
	local rise = input.height - lastHeight
	if math.abs(rise) > smoothing.teleportDistance then
		state.stepOffset = 0
		return
	end
	-- Whatever lifted the root beyond what the floor explains is a step,
	-- however many frames the Humanoid takes to climb it and whatever velocity it
	-- shows meanwhile. That part is held back, then let out at a steady pace
	-- over real time. The end of a fall is the landing dip's.
	if input.grounded and wasGrounded then
		local popped = rise - riseFromFloor(lastFloorRiseSpeed, input.floorRiseSpeed, dt)
		state.stepOffset =
			math.clamp(state.stepOffset - popped, -smoothing.maxOffset, smoothing.maxOffset)
	end
	local catchUp = (smoothing.catchUpSpeed + input.horizontalSpeed) * dt
	state.stepOffset -= math.clamp(state.stepOffset, -catchUp, catchUp)
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
	state.tilt = Math.follow(
		state.tilt,
		state.tiltTarget or tiltTarget,
		tiltTarget,
		settings.strafeTilt.responseTime,
		dt
	)
	state.tiltTarget = tiltTarget

	local breathing = settings.breathing
	local fatigueTarget = math.clamp(input.fatigue, 0, 1)
	state.fatigue = Math.follow(
		state.fatigue,
		state.fatigueTarget or fatigueTarget,
		fatigueTarget,
		breathing.responseTime,
		dt
	)
	state.fatigueTarget = fatigueTarget
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
	state.sprintFov = Math.follow(
		state.sprintFov,
		state.fovTarget or fovTarget,
		fovTarget,
		settings.sprintFov.responseTime,
		dt
	)
	state.fovTarget = fovTarget

	local kick = settings.kick
	state.kickRotation, state.kickRotationVelocity = stepSpring3(
		state.kickRotation,
		state.kickRotationVelocity,
		kick.frequency,
		kick.damping,
		dt
	)
	state.kickPosition, state.kickPositionVelocity = stepSpring3(
		state.kickPosition,
		state.kickPositionVelocity,
		kick.frequency,
		kick.damping,
		dt
	)
	-- The shake rides on the wobble: it goes as the square of the swing's
	-- size (as Eiserloh's camera shake goes as the square of trauma, GDC
	-- 2016), so it ends before the wobble does rather than outlasting it.
	local kickRotation = state.kickRotation
	local kickPosition = state.kickPosition
	local shakeRotation = Vector3.zero
	local swing = math.deg(
		swingSize(kickRotation, state.kickRotationVelocity, kick.frequency, kick.damping)
	)
	local strength = math.min(kick.shake * swing / FULL_SHAKE_DEGREES, 1) ^ 2
	if strength > 0 then
		local x = state.time * kick.shakeFrequency
		local function sample(channel: number): number
			return math.clamp(math.noise(x, kick.seed * 1000 + channel * 23.71) * 2, -1, 1)
		end
		local degrees = Vector3.new(sample(1), sample(2), sample(3)) * kick.shakeDegrees * strength
		shakeRotation = Vector3.new(math.rad(degrees.X), math.rad(degrees.Y), math.rad(degrees.Z))
	end

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
	state.localPosition = (walkingPosition * presence + kickPosition) * scale
	state.localRotation = (walkingRotation * presence + kickRotation + shakeRotation) * scale
	-- The step smoothing steadies the view rather than moving it, so the
	-- motion scale leaves it alone.
	state.worldHeight = (state.stepOffset + state.landDrop * scale) * presence
	state.fovOffset = state.sprintFov * scale

	local walking = presence * scale
	state.bobAngle = math.abs(bobRoll) * walking
	state.swayAngle = swayRotation.Magnitude * walking
	state.breathAngle = math.abs(breathPitch) * walking
	state.tiltAngle = math.abs(state.tilt) * walking
	state.landingAngle = math.abs(state.landPitch) * walking
	state.kickAngle = kickRotation.Magnitude * scale
	state.shakeAngle = shakeRotation.Magnitude * scale
	state.motionDistance = (state.localPosition + Vector3.new(
		0,
		state.landDrop * scale * presence,
		0
	)).Magnitude
end

return CameraMotion
