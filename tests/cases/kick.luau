--!strict
-- Kicks: the snap swings out to about the size asked and a little past rest,
-- the settle leaves a tail after it, the shake dies away, and repeated kicks
-- vary in yaw the same way for the same seed. The frame-rate checks are in
-- camera-motion.luau.

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

	-- The kick's pitch, in degrees, every DT for `duration` seconds.
	local function pitches(state: any, duration: number): { number }
		local out = {}
		for _ = 1, math.round(duration / DT) do
			CameraMotion.step(state, settings, input, DT)
			table.insert(out, math.deg(state.snapRotation.X + state.settleRotation.X))
		end
		return out
	end

	local state = CameraMotion.new()
	CameraMotion.kick(state, settings, Vector3.new(-3, 0, 0), Vector3.zero)
	local trace = pitches(state, 3)
	local lowest, highest = 0, 0
	for _, value in trace do
		lowest = math.min(lowest, value)
		highest = math.max(highest, value)
	end
	Check.ok(
		"swings out to about the size asked",
		lowest < -2.4 and lowest > -3.3,
		`peak {Check.show(lowest)}`
	)
	-- The snap swings past rest while the settle still holds the view down,
	-- so the view only slows; the settle then eases it back.
	local at = function(time: number): number
		return trace[math.round(time / DT)]
	end
	Check.ok("a tail after the snap", at(0.4) < -0.15, `at 0.4 s {Check.show(at(0.4))}`)
	Check.ok("eases back", math.abs(at(3)) < 0.01, `at 3 s {Check.show(at(3))}`)
	Check.ok("does not bounce far past rest", highest < 0.3, `highest {Check.show(highest)}`)

	local snapOnly = Config.resolve({ kick = { settleShare = 0 } })
	local snap = CameraMotion.new()
	CameraMotion.kick(snap, snapOnly, Vector3.new(-3, 0, 0), Vector3.zero)
	local snapHighest = 0
	for _ = 1, math.round(0.5 / DT) do
		CameraMotion.step(snap, snapOnly, input, DT)
		snapHighest = math.max(snapHighest, math.deg(snap.snapRotation.X))
	end
	Check.ok(
		"the snap alone swings past rest",
		snapHighest > 0.2,
		`highest {Check.show(snapHighest)}`
	)

	Check.ok("no trauma left after 3 s", state.trauma == 0)
	local shaken = CameraMotion.new()
	CameraMotion.kick(shaken, settings, Vector3.new(-3, 0, 0), Vector3.zero)
	Check.near("trauma is the share of a full shake", shaken.trauma, 0.3, 1e-12)
	local shakeSeen = 0
	for _ = 1, math.round(0.2 / DT) do
		CameraMotion.step(shaken, settings, input, DT)
		shakeSeen = math.max(shakeSeen, shaken.shakeAngle)
	end
	Check.ok("the view shakes", shakeSeen > 0)
	for _ = 1, math.round(0.3 / DT) do
		CameraMotion.step(shaken, settings, input, DT)
	end
	Check.near("the shake dies away", shaken.trauma, 0, 0)

	local function yawsOf(seed: number): { number }
		local seeded = Config.resolve({ kick = { seed = seed } })
		local kicked = CameraMotion.new()
		local yaws = {}
		for _ = 1, 3 do
			local before = kicked.settleRotationVelocity.Y
			CameraMotion.kick(kicked, seeded, Vector3.new(-3, 0, 0), Vector3.zero)
			table.insert(yaws, kicked.settleRotationVelocity.Y - before)
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
