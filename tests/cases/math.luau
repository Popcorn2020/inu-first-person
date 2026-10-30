--!strict
-- Math: the springs and eases give the same result however a span of time is
-- cut into frames, and a kick swings out exactly as far as asked.

local Check = require("../check")

return function(load: (string) -> any)
	local Math = load("Math")
	Check.section("Math")

	local cuts = { 1, 30, 144, 240, 1000 }

	-- A spring started off rest: every cut of 1.25 seconds ends in the same
	-- place, for under-, critically, over- and undamped springs.
	for _, spring in { { 2.2, 0.55 }, { 5, 1 }, { 3, 2.5 }, { 1, 0 } } do
		local frequency, damping = spring[1], spring[2]
		local reference: { number }? = nil
		for _, count in cuts do
			local position, velocity = 1, -3
			for _ = 1, count do
				position, velocity =
					Math.spring(position, velocity, 0, frequency, damping, 1.25 / count)
			end
			local expected = reference
			if expected == nil then
				reference = { position, velocity }
			else
				local name = `spring {frequency} Hz, damping {damping}, {count} steps`
				Check.near(name .. " position", position, expected[1], 1e-9)
				Check.near(name .. " velocity", velocity, expected[2], 1e-8)
			end
		end
	end

	-- springKickVelocity: a spring at rest given that velocity peaks at the
	-- asked size.
	for _, damping in { 0, 0.3, 0.55, 0.6, 1 } do
		local frequency = 2.2
		local velocity = Math.springKickVelocity(0.5, frequency, damping)
		local position = 0
		local peak = 0
		for _ = 1, 20000 do
			position, velocity = Math.spring(position, velocity, 0, frequency, damping, 1e-4)
			peak = math.max(peak, position)
		end
		Check.near(`kick peak, damping {damping}`, peak, 0.5, 5e-4)
	end

	-- follow: a steady ramp is trailed by speed * timeConstant at any frame
	-- rate, and the result does not depend on the cut.
	for _, count in cuts do
		local dt = 3 / count
		local value = 0
		local target = 0
		for _ = 1, count do
			local before = target
			target += 2 * dt
			value = Math.follow(value, before, target, 0.2, dt)
		end
		Check.near(`follow lag, {count} steps`, target - value, 0.4 * (1 - math.exp(-15)), 1e-9)
	end
	Check.near("follow with no time constant", Math.follow(0, 1, 2, 0, 0.1), 2, 0)

	-- approach toward a target that holds still.
	local once = Math.approach(5, 1, 0.3, 1)
	local stepped = 5
	for _ = 1, 240 do
		stepped = Math.approach(stepped, 1, 0.3, 1 / 240)
	end
	Check.near("approach cut into 240", stepped, once, 1e-12)

	-- shortestAngle wraps into [-pi, pi).
	Check.near("shortestAngle of 3 pi", Math.shortestAngle(3 * math.pi), -math.pi, 1e-12)
	Check.near("shortestAngle of 0.5", Math.shortestAngle(0.5), 0.5, 1e-12)
	Check.near("shortestAngle of -4", Math.shortestAngle(-4), 2 * math.pi - 4, 1e-12)
end
