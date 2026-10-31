--!strict
-- Turn: the body trails a steady turn by the spring's steady lag and catches
-- up, a little past, when the view stops; turning a little at a time, it
-- follows each turn as it comes rather than in later chunks. With a slack,
-- the feet hold while the view turns within it, the turn beyond drags the
-- body smoothly, and the body stays where the drag left it. Played at 30, 60,
-- 144 and 240 frames per second and with uneven frames, the body stays
-- within a frame of the 960 fps run, through the ±180 degree wrap.

local Check = require("../check")
local Frames = require("../frames")

local SLACK = math.rad(45)
local FREQUENCY = 2.25
local DAMPING = 0.6
local RATE = math.rad(90)
local START = math.rad(170)
local TURN_UNTIL = 7 / 6
local DURATION = 3
local REFERENCE_FPS = 960
-- Allowed beyond the reference's range within the window, in radians. The
-- body switches between held and dragged at the end of a frame, which leaves
-- a few hundredths of a degree at 30 fps; a tenth is far below what shows.
local WINDOW_ERROR = math.rad(0.1)
-- Turning a little at a time: a turn of this much over TURN_TIME, then a
-- hold of HOLD_TIME, over and over.
local LITTLE_TURN = math.rad(10)
local TURN_TIME = 0.25
local HOLD_TIME = 0.75

return function(load: (string) -> any)
	local Math = load("Math")
	local Turn = load("Turn")
	Check.section("Turn")

	local function steadyView(time: number): number
		return Math.shortestAngle(START + RATE * math.min(time, TURN_UNTIL))
	end

	local function littleTurns(time: number): number
		local period = TURN_TIME + HOLD_TIME
		local done = math.floor(time / period)
		local into = math.clamp((time - done * period) / TURN_TIME, 0, 1)
		return Math.shortestAngle(START + LITTLE_TURN * (done + into))
	end

	-- The twist (view less body, radians) at each frame.
	local function play(times: { number }, viewAt: (number) -> number, slack: number): { number }
		local state = Turn.new()
		Turn.reset(state, viewAt(0), viewAt(0))
		local twists = {}
		local last = 0
		for _, time in times do
			local view = viewAt(time)
			local yaw = Turn.step(state, view, slack, FREQUENCY, DAMPING, time - last)
			last = time
			table.insert(twists, Math.shortestAngle(view - yaw))
		end
		return twists
	end

	local reference = Frames.fixed(REFERENCE_FPS, DURATION + 1)
	local function at(twists: { number }, time: number): number
		return twists[math.round(time * REFERENCE_FPS)]
	end

	-- Following: the steady lag of a spring chasing a steady turn.
	local following = play(reference.times, steadyView, 0)
	local omega = 2 * math.pi * FREQUENCY
	local lag = 2 * DAMPING * RATE / omega
	Check.near("follows a steady turn by the steady lag", at(following, 1), lag, math.rad(0.2))
	Check.near("catches up once the view stops", at(following, 2.5), 0, math.rad(0.1))
	local past = 0
	for index, time in reference.times do
		if time > TURN_UNTIL then
			past = math.min(past, following[index])
		end
	end
	Check.ok(
		"swings a little past the view",
		past < 0 and past > -lag * 0.3,
		`{Check.show(math.deg(past))} degrees`
	)

	-- Turning a little at a time, the body keeps up with each turn instead of
	-- waiting and catching up in a chunk.
	local little = play(reference.times, littleTurns, 0)
	local widest = 0
	for _, twist in little do
		widest = math.max(widest, math.abs(twist))
	end
	local littleLag = 2 * DAMPING * (LITTLE_TURN / TURN_TIME) / omega
	Check.ok(
		"little turns: never further behind than a steady turn's lag",
		widest < littleLag * 1.2,
		`{Check.show(math.deg(widest))} degrees, the lag {Check.show(math.deg(littleLag))}`
	)
	local period = TURN_TIME + HOLD_TIME
	Check.near(
		"little turns: caught up before the next one",
		at(little, 2 * period - 0.01),
		0,
		math.rad(0.2)
	)

	-- With a slack: the feet hold within it, the rest drags the body, and it
	-- stays twisted where the drag left it.
	local slack = play(reference.times, steadyView, SLACK)
	Check.near("slack: holds within it", at(slack, 0.4), RATE * 0.4, 1e-9)
	Check.near("slack: drags the body past it", at(slack, 1), SLACK + lag, math.rad(1))
	local final = at(slack, DURATION)
	Check.ok(
		"slack: stays twisted, about the slack",
		final > SLACK - math.rad(3) and final <= SLACK + math.rad(0.1),
		`{Check.show(math.deg(final))} degrees`
	)
	local steepest = 0
	for index = 2, #slack do
		local turned = Math.shortestAngle(slack[index] - slack[index - 1])
		steepest = math.max(steepest, math.abs(turned) * REFERENCE_FPS)
	end
	Check.ok(
		"slack: the body never jumps",
		steepest < math.rad(500),
		`fastest {Check.show(math.deg(steepest))} degrees a second`
	)

	local scenarios = {
		{ name = "following", viewAt = steadyView, slack = 0, expected = following },
		{ name = "little turns", viewAt = littleTurns, slack = 0, expected = little },
		{ name = "slack", viewAt = steadyView, slack = SLACK, expected = slack },
	}
	local runs = {
		Frames.fixed(30, DURATION),
		Frames.fixed(60, DURATION),
		Frames.fixed(144, DURATION),
		Frames.fixed(240, DURATION),
		Frames.jitter(7, 1 / 240, 1 / 30, DURATION),
	}
	local count = #reference.times
	for _, run in runs do
		for _, scenario in scenarios do
			local twists = play(run.times, scenario.viewAt, scenario.slack)
			local worst = 0
			local worstTime = 0
			for index, time in run.times do
				local first = math.clamp(math.ceil((time - run.longest) * REFERENCE_FPS), 1, count)
				local last = math.clamp(math.floor((time + run.longest) * REFERENCE_FPS), 1, count)
				local low, high = math.huge, -math.huge
				for frame = first, last do
					low = math.min(low, scenario.expected[frame])
					high = math.max(high, scenario.expected[frame])
				end
				local outside = math.max(low - twists[index], twists[index] - high, 0)
				if outside > worst then
					worst, worstTime = outside, time
				end
			end
			Check.ok(
				`{run.name}: {scenario.name} within a frame of {REFERENCE_FPS} fps`,
				worst <= WINDOW_ERROR,
				`off by {Check.show(math.deg(worst))} degrees at {Check.show(worstTime)} s`
			)
		end
	end

	local state = Turn.new()
	Check.near(
		"the first step faces the view",
		Turn.step(state, 1, SLACK, FREQUENCY, DAMPING, 1 / 60),
		1,
		0
	)
	Turn.reset(state, 0.5, 1)
	Check.near(
		"reset keeps the feet where they are",
		Turn.step(state, 1, SLACK, FREQUENCY, DAMPING, 1 / 60),
		0.5,
		1e-12
	)
end
