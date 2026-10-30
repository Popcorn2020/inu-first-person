--!strict
-- TurnLag: a steady turn is trailed by the same angle at any frame rate,
-- through the ±180 degree wrap, and never by more than the cap.

local Check = require("../check")
local Frames = require("../frames")

return function(load: (string) -> any)
	local Math = load("Math")
	local TurnLag = load("TurnLag")
	Check.section("TurnLag")

	local runs = {
		Frames.fixed(30, 3),
		Frames.fixed(60, 3),
		Frames.fixed(144, 3),
		Frames.fixed(240, 3),
		Frames.jitter(11, 1 / 240, 1 / 30, 3),
	}
	local lagTime = 0.07
	local maxLag = math.rad(10)

	for _, run in runs do
		-- 90 degrees a second, starting near +180 so the yaw wraps to -180.
		local state = TurnLag.new()
		local last = 0
		local start = math.rad(170)
		local rate = math.rad(90)
		local jumps = 0
		local previous: number? = nil
		local lag = 0
		for _, time in run.times do
			local yaw = Math.shortestAngle(start + rate * time)
			local trailing = TurnLag.step(state, yaw, lagTime, maxLag, time - last)
			last = time
			if previous and math.abs(trailing - previous) > rate * run.longest * 1.01 then
				jumps += 1
			end
			previous = trailing
			lag = Math.shortestAngle(yaw - trailing)
		end
		Check.ok(`{run.name}: no jump through the wrap`, jumps == 0, `{jumps} jumps`)
		Check.near(
			`{run.name}: trails a steady turn by rate * lagTime`,
			math.deg(lag),
			90 * lagTime,
			1e-6
		)

		-- 360 degrees a second would trail by 25.2 degrees; the cap holds it
		-- to 10.
		local fast = TurnLag.new()
		last = 0
		for _, time in run.times do
			local yaw = Math.shortestAngle(math.rad(360) * time)
			local trailing = TurnLag.step(fast, yaw, lagTime, maxLag, time - last)
			last = time
			lag = Math.shortestAngle(yaw - trailing)
		end
		Check.near(`{run.name}: the cap`, math.deg(lag), 10, 1e-9)
	end

	local state = TurnLag.new()
	TurnLag.step(state, 0, lagTime, maxLag, 1 / 60)
	TurnLag.step(state, 0.5, lagTime, maxLag, 1 / 60)
	TurnLag.reset(state)
	Check.near(
		"reset snaps to the next yaw",
		TurnLag.step(state, 1.5, lagTime, maxLag, 1 / 60),
		1.5,
		0
	)
end
