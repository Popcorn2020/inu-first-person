--!strict
-- Kicks: the view swings out to about the size asked and wobbles back on one
-- spring, every swing the same time apart and the same share of the one
-- before, so no part of the wobble runs slower than the rest; the shake ends
-- with the wobble, and repeated kicks vary in yaw the same way for the same
-- seed. The frame-rate checks are in camera-motion.luau.

local Check = require("../check")
local roblox = require("@lune/roblox") :: any

local Vector3 = roblox.Vector3

local DT = 1 / 960

return function(load: (string) -> any)
	local CameraMotion = load("CameraMotion")
	local Config = load("Config")
	Check.section("Kick")

	local settings = Config.defaults
	local input = CameraMotion.newInput()
	input.firstPerson = false

	-- The kick's pitch (degrees) and the shake's angle, every DT for
	-- `duration` seconds.
	local function play(state: any, duration: number): ({ number }, { number })
		local pitches, shakes = {}, {}
		for _ = 1, math.round(duration / DT) do
			CameraMotion.step(state, settings, input, DT)
			table.insert(pitches, math.deg(state.kickRotation.X))
			table.insert(shakes, state.shakeAngle)
		end
		return pitches, shakes
	end

	local state = CameraMotion.new()
	CameraMotion.kick(state, settings, Vector3.new(-3, 0, 0), Vector3.zero)
	local pitches, shakes = play(state, 3)

	-- Each turn of the wobble: when it came and how far from rest it was.
	local turnTimes, turnSizes = {}, {}
	for index = 2, #pitches - 1 do
		local value = pitches[index]
		local peak = (value < pitches[index - 1] and value <= pitches[index + 1])
			or (value > pitches[index - 1] and value >= pitches[index + 1])
		if peak and math.abs(value) > 1e-3 then
			table.insert(turnTimes, index * DT)
			table.insert(turnSizes, math.abs(value))
		end
	end
	Check.ok("wobbles at least three times", #turnSizes >= 3, `{#turnSizes} swings`)
	if #turnSizes < 3 then
		return
	end
	Check.ok(
		"swings out to about the size asked",
		pitches[math.round(turnTimes[1] / DT)] < -2.9 and turnSizes[1] < 3.1,
		`first swing {Check.show(turnSizes[1])}`
	)
	local ratio = turnSizes[2] / turnSizes[1]
	Check.near("every swing the same share of the last", turnSizes[3] / turnSizes[2], ratio, 0.01)
	Check.ok(
		"the second swing is a clear swing back",
		ratio > 0.25 and ratio < 0.5,
		`ratio {Check.show(ratio)}`
	)
	local gap = turnTimes[2] - turnTimes[1]
	Check.near("the swings come evenly", turnTimes[3] - turnTimes[2], gap, 2 * DT)
	local at = function(time: number): number
		return pitches[math.round(time / DT)]
	end
	Check.ok("comes to rest", math.abs(at(1.5)) < 0.01, `at 1.5 s {Check.show(at(1.5))}`)

	-- The shake is strongest at the kick and gone while the wobble still
	-- shows, rather than lingering after it.
	local strongest = 0
	for _, value in shakes do
		strongest = math.max(strongest, value)
	end
	Check.ok("the view shakes", strongest > 0)
	local thirdSwing = math.round(turnTimes[3] / DT)
	Check.ok(
		"the shake is nearly gone by the third swing",
		shakes[thirdSwing] < strongest * 0.05,
		`{Check.show(shakes[thirdSwing] / strongest * 100)}% of its strongest`
	)
	Check.ok("no shake once at rest", shakes[#shakes] < 1e-6, `{Check.show(shakes[#shakes])}`)

	local calm = Config.resolve({ kick = { shake = 0 } })
	local still = CameraMotion.new()
	CameraMotion.kick(still, calm, Vector3.new(-3, 0, 0), Vector3.zero)
	CameraMotion.step(still, calm, input, DT)
	Check.near("shake 0 shakes nothing", still.shakeAngle, 0, 0)

	local function yawsOf(seed: number): { number }
		local seeded = Config.resolve({ kick = { seed = seed } })
		local kicked = CameraMotion.new()
		local yaws = {}
		for _ = 1, 3 do
			local before = kicked.kickRotationVelocity.Y
			CameraMotion.kick(kicked, seeded, Vector3.new(-3, 0, 0), Vector3.zero)
			table.insert(yaws, kicked.kickRotationVelocity.Y - before)
		end
		return yaws
	end
	local first, again, other = yawsOf(0), yawsOf(0), yawsOf(4)
	Check.ok("kicks vary", first[1] ~= first[2] and first[2] ~= first[3])
	Check.ok(
		"the same seed varies the same way",
		first[1] == again[1] and first[2] == again[2] and first[3] == again[3]
	)
	Check.ok("another seed varies another way", first[1] ~= other[1])
end
