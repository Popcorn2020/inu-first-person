--!strict
-- Turn: standing still, the feet hold until the view passes the threshold,
-- then swing round; moving, the body swings round and locks to the view.
-- A steady turn gives the same twist at any frame rate, through the ±180
-- degree wrap.

local Check = require("../check")
local Frames = require("../frames")

local THRESHOLD = math.rad(50)
local LIMIT = math.rad(70)
local SWING_TIME = 0.12
local RATE = math.rad(90)
local START = math.rad(170)
local TURN_UNTIL = 1.2
local DURATION = 1.5

return function(load: (string) -> any)
	local Math = load("Math")
	local Turn = load("Turn")
	Check.section("Turn")

	local function viewAt(time: number): number
		return Math.shortestAngle(START + RATE * math.min(time, TURN_UNTIL))
	end

	-- The twist at each multiple of 1/6 second.
	local function play(run: any, follow: (number) -> boolean, threshold: number): { number }
		local state = Turn.new()
		Turn.reset(state, 0, viewAt(0))
		local marks = {}
		local last = 0
		for _, time in run.times do
			local twist = Turn.step(
				state,
				viewAt(time),
				follow(time),
				threshold,
				LIMIT,
				SWING_TIME,
				time - last
			)
			last = time
			local mark = time * Frames.GRID
			if math.abs(mark - math.round(mark)) < 1e-9 then
				marks[math.round(mark)] = twist
			end
		end
		return marks
	end

	local runs = {
		Frames.fixed(30, DURATION),
		Frames.fixed(60, DURATION),
		Frames.fixed(144, DURATION),
		Frames.fixed(240, DURATION),
		Frames.jitter(7, 1 / 240, 1 / 30, DURATION),
	}
	local standing = function(_time: number): boolean
		return false
	end
	local reference = play(Frames.fixed(960, DURATION), standing, THRESHOLD)

	-- Worked out by hand: the twist reaches 50 degrees at 5/9 s, the swing
	-- ends 0.12 s later, and the twist then grows again until the view stops.
	local firstSwing = 50 / 90
	Check.near("holds until the threshold", math.deg(reference[3]), -45, 1e-9)
	Check.near(
		"grows again after the swing",
		math.deg(reference[6]),
		-(1 - firstSwing - SWING_TIME) * 90,
		1e-9
	)
	Check.near(
		"holds once the view stops",
		math.deg(reference[9]),
		-(TURN_UNTIL - firstSwing - SWING_TIME) * 90,
		1e-9
	)

	for _, run in runs do
		local marks = play(run, standing, THRESHOLD)
		local worst = 0
		for mark, twist in reference do
			worst = math.max(worst, math.abs((marks[mark] or math.huge) - twist))
		end
		Check.ok(
			`{run.name}: standing turn matches 960 fps`,
			worst < 1e-9,
			`off by {Check.show(math.deg(worst))} degrees`
		)

		-- Starting to move at 0.25 s: the body swings round and then turns
		-- with the view exactly.
		local moving = play(run, function(time: number): boolean
			return time > 0.25
		end, THRESHOLD)
		Check.near(`{run.name}: locked to the view while moving`, moving[3], 0, 0)
		Check.near(`{run.name}: still locked`, moving[7], 0, 0)

		-- A threshold past the limit: the feet are pulled round at the limit.
		local pulled = play(run, standing, math.rad(120))
		Check.near(`{run.name}: held at the limit`, math.deg(pulled[6]), -70, 1e-9)
	end

	local state = Turn.new()
	Check.near(
		"the first step faces the view",
		Turn.step(state, 1, false, THRESHOLD, LIMIT, SWING_TIME, 1 / 60),
		0,
		0
	)
	Turn.reset(state, math.rad(30), 1)
	Check.near(
		"reset keeps the feet where they are",
		Turn.step(state, 1 + math.rad(10), false, THRESHOLD, LIMIT, SWING_TIME, 1 / 60),
		math.rad(20),
		1e-12
	)
	Turn.reset(state, math.rad(90), 0)
	local swung = Turn.step(state, 0, false, THRESHOLD, LIMIT, SWING_TIME, 1 / 60)
	Check.ok(
		"reset past the threshold swings round from the limit",
		swung < LIMIT and swung > LIMIT * 0.9,
		`twist {Check.show(math.deg(swung))}`
	)
end
