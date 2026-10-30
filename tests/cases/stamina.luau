--!strict
-- StaminaModel: draining, the wait, refilling and exhaustion happen at the
-- same times at any frame rate.

local Check = require("../check")
local Frames = require("../frames")

return function(load: (string) -> any)
	local StaminaModel = load("StaminaModel")
	local Config = load("Config")
	local settings = Config.defaults.stamina
	Check.section("StaminaModel")

	local runs = {
		Frames.fixed(30, 14),
		Frames.fixed(60, 14),
		Frames.fixed(144, 14),
		Frames.fixed(240, 14),
		Frames.jitter(7, 1 / 240, 1 / 30, 14),
	}

	for _, run in runs do
		-- Holding sprint from full: it runs out at 8 s, waits 1 s, refills to
		-- 30% by 10.5 s, then sprints again, as Sprint does.
		local state = StaminaModel.new(settings)
		local last = 0
		local emptyAt: number? = nil
		local recoveredAt: number? = nil
		for _, time in run.times do
			local sprinting = not state.exhausted
			local wasExhausted = state.exhausted
			StaminaModel.step(state, settings, sprinting, time - last)
			last = time
			if state.exhausted and not wasExhausted and emptyAt == nil then
				emptyAt = time
			elseif wasExhausted and not state.exhausted and recoveredAt == nil then
				recoveredAt = time
			end
			if time >= 12 - 1e-9 and time <= 12 + 1e-9 then
				-- One frame each side of the two turns may differ.
				Check.near(
					`{run.name}: stamina at 12 s`,
					state.value,
					11.25,
					32.5 * run.longest + 1e-9
				)
			end
		end
		Check.near(`{run.name}: runs out at 8 s`, emptyAt or -1, 8, run.longest + 1e-9)
		Check.near(
			`{run.name}: sprint allowed at 10.5 s`,
			recoveredAt or -1,
			10.5,
			2 * run.longest + 1e-9
		)

		-- Refilling from empty follows 20 * (t - 1) exactly at every frame,
		-- since the step splits at the end of the wait.
		local refill = StaminaModel.new(settings)
		StaminaModel.spend(refill, settings, settings.max)
		last = 0
		local worst = 0
		for _, time in run.times do
			StaminaModel.step(refill, settings, false, time - last)
			last = time
			local expected =
				math.clamp(settings.regenRate * (time - settings.regenDelay), 0, settings.max)
			worst = math.max(worst, math.abs(refill.value - expected))
		end
		Check.near(`{run.name}: refill curve`, worst, 0, 1e-9)
	end

	-- set does not restart the wait; spend does; refill fills and clears.
	local state = StaminaModel.new(settings)
	StaminaModel.step(state, settings, true, 1)
	StaminaModel.step(state, settings, false, 0.5)
	StaminaModel.set(state, settings, 50)
	StaminaModel.step(state, settings, false, 0.75)
	Check.near("set keeps the wait going", state.value, 50 + 20 * 0.25, 1e-9)
	StaminaModel.spend(state, settings, 10)
	StaminaModel.step(state, settings, false, 0.5)
	Check.near("spend restarts the wait", state.value, 45, 1e-9)
	StaminaModel.set(state, settings, -5)
	Check.ok("set clamps to 0 and exhausts", state.value == 0 and state.exhausted)
	StaminaModel.refill(state, settings)
	Check.ok("refill", state.value == settings.max and not state.exhausted and state.waitLeft == 0)
end
