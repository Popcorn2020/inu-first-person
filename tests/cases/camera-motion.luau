--!strict
-- CameraMotion: ten scripted seconds (standing, walking, sprinting, strafing,
-- a step up, a slope, a jump, a fall off a ledge, stopping, third person and
-- a kick), played at 30, 60, 144 and 240 frames per second and with uneven
-- frames, show the same motion as at 960, give or take one frame. One frame
-- is how far sampling can shift a moment that falls between frames.
--
-- The bob and the breathing are compared by their size and pace, not their
-- phase: where in its cycle the bob stops depends on when within a frame the
-- character stopped, which no frame rate knows, and the cycle goes on from
-- there.

local Check = require("../check")
local Frames = require("../frames")
local roblox = require("@lune/roblox") :: any

local Vector3 = roblox.Vector3

local DURATION = 10
local REFERENCE_FPS = 960
local GRAVITY = 196.2
local WALK = 16
local RUN = 25.6
-- The root's height on the first floor.
local FLOOR = 3
local STEP_AT = 6
local STEP_UP = 1
local SLOPE_START = 39 / 6
local SLOPE_END = 41 / 6
local SLOPE_RISE_SPEED = 8
local JUMP_AT = 7
local JUMP_SPEED = 50
local LEDGE_AT = 8
local LEDGE_DROP = 10
local THIRD_FROM = 58 / 6
local THIRD_TO = 59 / 6
local KICK_AT = 9.5
-- Allowed beyond the reference's range within the window, as a share of the
-- channel's largest size.
local SLACK = 0.01

local UPPER = FLOOR + STEP_UP + SLOPE_RISE_SPEED * (SLOPE_END - SLOPE_START)
local JUMP_TIME = 2 * JUMP_SPEED / GRAVITY
local FALL_TIME = math.sqrt(2 * LEDGE_DROP / GRAVITY)

local CHANNELS = {
	"presence",
	"bob size",
	"bob pace",
	"tilt",
	"fatigue",
	"breath",
	"landing drop",
	"landing pitch",
	"step offset",
	"sprint fov",
	"kick pitch",
	"kick back",
	"world height",
	"body height",
	"fov offset",
}

local function ramp(time: number, start: number, length: number, from: number, to: number): number
	return from + (to - from) * math.clamp((time - start) / length, 0, 1)
end

local function speedAt(time: number): number
	if time < 1 then
		return 0
	elseif time < 3 then
		return ramp(time, 1, 1 / 6, 0, WALK)
	elseif time < 5 then
		return ramp(time, 3, 1 / 6, WALK, RUN)
	elseif time < 9 then
		return ramp(time, 5, 1 / 6, RUN, WALK)
	end
	return ramp(time, 9, 1 / 6, WALK, 0)
end

-- The root's height and vertical speed at `time`, and whether it is in the air.
local function bodyAt(time: number): (number, number, boolean)
	if time >= LEDGE_AT + FALL_TIME then
		return UPPER - LEDGE_DROP, 0, false
	elseif time >= LEDGE_AT then
		local t = time - LEDGE_AT
		return UPPER - GRAVITY / 2 * t * t, -GRAVITY * t, true
	elseif time >= JUMP_AT + JUMP_TIME then
		return UPPER, 0, false
	elseif time >= JUMP_AT then
		local t = time - JUMP_AT
		return UPPER + JUMP_SPEED * t - GRAVITY / 2 * t * t, JUMP_SPEED - GRAVITY * t, true
	elseif time >= SLOPE_END then
		return UPPER, 0, false
	elseif time >= SLOPE_START then
		return FLOOR + STEP_UP + SLOPE_RISE_SPEED * (time - SLOPE_START), SLOPE_RISE_SPEED, false
	elseif time >= STEP_AT then
		return FLOOR + STEP_UP, 0, false
	end
	return FLOOR, 0, false
end

local function describe(input: any, time: number)
	local height, verticalSpeed, airborne = bodyAt(time)
	local speed = speedAt(time)
	input.speed = speed
	input.horizontalSpeed = speed
	input.walkSpeed = WALK
	input.runSpeed = RUN
	input.strafe = if time >= 5 and time < 5.5 then ramp(time, 5, 1 / 6, 0, 1) else 0
	input.grounded = not airborne
	input.climbing = false
	input.airborne = airborne
	input.verticalSpeed = verticalSpeed
	input.height = height
	input.gravity = GRAVITY
	input.fatigue = if time < 5 then ramp(time, 3, 2, 0, 0.25) else ramp(time, 6, 1.25, 0.25, 0)
	input.motionScale = 1
	input.firstPerson = not (time >= THIRD_FROM and time < THIRD_TO)
end

local function sample(state: any): { number }
	return {
		state.presence,
		state.bobScale,
		state.bobCadence,
		state.tilt,
		state.fatigue,
		math.sin(state.breathPhase),
		state.landDrop,
		state.landPitch,
		state.stepOffset,
		state.sprintFov,
		state.kickRotation.X,
		state.kickPosition.Z,
		state.worldHeight,
		state.bodyHeight,
		state.fovOffset,
	}
end

type Played = {
	samples: { { number } },
	-- The bob's phase without the wrap, at each frame.
	phases: { number },
}

local function play(CameraMotion: any, settings: any, times: { number }): Played
	local state = CameraMotion.new()
	local input = CameraMotion.newInput()
	local samples = {}
	local phases = {}
	local phase = state.bobPhase
	local unwrapped = 0
	local last = 0
	for _, time in times do
		-- The kick lands at the start of the frame that begins at KICK_AT.
		if last <= KICK_AT and KICK_AT < time then
			CameraMotion.kick(state, settings, Vector3.new(-3, 1.5, 0), Vector3.new(0, 0, 0.15))
		end
		describe(input, time)
		CameraMotion.step(state, settings, input, time - last)
		last = time
		table.insert(samples, sample(state))
		unwrapped += (state.bobPhase - phase + math.pi) % (2 * math.pi) - math.pi
		phase = state.bobPhase
		table.insert(phases, unwrapped)
	end
	return { samples = samples, phases = phases }
end

return function(load: (string) -> any)
	local CameraMotion = load("CameraMotion")
	local Config = load("Config")
	local settings = Config.defaults
	Check.section("CameraMotion")

	-- The reference runs a second past the end, so the last frames of a run
	-- have the reference on both sides of their window.
	local reference = Frames.fixed(REFERENCE_FPS, DURATION + 1)
	local expected = play(CameraMotion, settings, reference.times)
	local count = #expected.samples
	local peaks = table.create(#CHANNELS, 0)
	for _, values in expected.samples do
		for channel, value in values do
			peaks[channel] = math.max(peaks[channel], math.abs(value))
		end
	end
	for channel, peak in peaks do
		Check.ok(`the scenario moves {CHANNELS[channel]}`, peak > 0)
	end

	local runs = {
		Frames.fixed(30, DURATION),
		Frames.fixed(60, DURATION),
		Frames.fixed(144, DURATION),
		Frames.fixed(240, DURATION),
		Frames.jitter(3, 1 / 240, 1 / 30, DURATION),
		Frames.jitter(5, 1 / 120, 1 / 50, DURATION),
	}
	for _, run in runs do
		local played = play(CameraMotion, settings, run.times)
		local window = run.longest
		for channel, name in CHANNELS do
			local slack = SLACK * peaks[channel] + 1e-12
			local misses = 0
			local worst = 0
			local worstTime = 0
			for index, time in run.times do
				local first = math.clamp(math.ceil((time - window) * REFERENCE_FPS), 1, count)
				local last = math.clamp(math.floor((time + window) * REFERENCE_FPS), 1, count)
				local low, high = math.huge, -math.huge
				for at = first, last do
					local value = expected.samples[at][channel]
					low = math.min(low, value)
					high = math.max(high, value)
				end
				local value = played.samples[index][channel]
				local outside = math.max(low - value, value - high, 0)
				if outside > slack then
					misses += 1
				end
				if outside > worst then
					worst = outside
					worstTime = time
				end
			end
			Check.ok(
				`{run.name}: {name} within a frame of {REFERENCE_FPS} fps`,
				misses == 0,
				`{misses} frames outside, worst {Check.show(worst / peaks[channel] * 100)}% of its size at {Check.show(
					worstTime
				)} s`
			)
		end

		-- Walking and sprinting without a stop, the bob keeps the same phase:
		-- a cycle is not lost or gained to the frame rate.
		for index, time in run.times do
			if time == SLOPE_END then
				local at = math.round(time * REFERENCE_FPS)
				Check.near(
					`{run.name}: bob phase after walking and sprinting`,
					played.phases[index],
					expected.phases[at],
					0.05
				)
			end
		end
	end

	-- The step is held back whole at any frame rate; only the catch-up of the
	-- frame that saw it shows.
	local catchUp = settings.stepSmoothing.catchUpSpeed + WALK
	local stepChannel = table.find(CHANNELS, "step offset") :: number
	for _, fps in { 30, 60, 144, 240 } do
		local played = play(CameraMotion, settings, Frames.fixed(fps, STEP_AT).times)
		local offset = played.samples[#played.samples][stepChannel]
		Check.near(`{fps} fps: the step is held back`, offset, -STEP_UP + catchUp / fps, 1e-9)
	end
end
