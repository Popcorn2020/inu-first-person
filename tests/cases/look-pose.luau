--!strict
-- LookPose: the head takes a look at once and the waist its share a moment
-- later; the neck stops at its limit until the waist catches up; a look past
-- the let-go angle, or past what the head reaches, lets the head go back to
-- the front rather than holding it at the limit, and it takes the look up
-- again only well inside that angle.

local Check = require("../check")

local DT = 1 / 240

return function(load: (string) -> any)
	local LookPose = load("LookPose")
	Check.section("LookPose")

	local settings = {
		neckYawLimit = math.rad(75),
		lookAwayAngle = math.rad(100),
		headPitchShare = 0.6,
		waistShare = 0.3,
		waistLag = 0.08,
	}
	local function hold(
		state: any,
		yaw: number,
		pitch: number,
		seconds: number,
		hasWaist: boolean?,
		given: any?
	)
		for _ = 1, math.round(seconds / DT) do
			LookPose.step(state, yaw, pitch, given or settings, hasWaist ~= false, false, 1, DT)
		end
	end
	local deg = math.deg

	local state = LookPose.new()
	hold(state, math.rad(60), 0, DT)
	Check.near("the head takes a look at once", deg(state.headYaw), 60, 1e-9)
	Check.ok("the waist is still behind", deg(state.waistYaw) < 1, `{deg(state.waistYaw)}`)
	hold(state, math.rad(60), 0, 1)
	Check.near("the waist then takes its share", deg(state.waistYaw), 18, 1e-3)
	Check.near("the neck takes the rest", deg(state.neckYaw), 42, 1e-3)

	local flick = LookPose.new()
	hold(flick, math.rad(95), 0, DT)
	Check.near("a quick wide look stops the neck at its limit", deg(flick.neckYaw), 75, 1e-9)
	Check.ok("and the head waits", deg(flick.headYaw) < 95, `{deg(flick.headYaw)}`)
	hold(flick, math.rad(95), 0, 1)
	Check.near("the head gets there once the waist turns", deg(flick.headYaw), 95, 1e-3)

	local reach = deg(LookPose.getReach(settings, true))
	Check.near("the reach is the neck's plus the waist's share", reach, 75 / 0.7, 1e-9)

	local far = LookPose.new()
	hold(far, math.rad(110), 0, 0.6)
	Check.ok("past the angle the head goes back to the front", math.abs(deg(far.headYaw)) < 2)
	hold(far, math.rad(90), 0, 0.6)
	Check.ok("just inside the angle it stays at the front", math.abs(deg(far.headYaw)) < 2)
	hold(far, math.rad(70), 0, 2)
	Check.near("well inside, it takes the look up again", deg(far.headYaw), 70, 1e-2)

	local wide = table.clone(settings)
	wide.lookAwayAngle = math.rad(180)
	local pinned = LookPose.new()
	hold(pinned, math.rad(115), 0, 0.6, true, wide)
	Check.ok(
		"past the reach it lets go whatever the angle, never held at the limit",
		math.abs(deg(pinned.headYaw)) < 2,
		`{deg(pinned.headYaw)}`
	)

	local r6 = LookPose.new()
	hold(r6, math.rad(70), 0, 1, false)
	Check.near("without a waist the neck alone turns", deg(r6.headYaw), 70, 1e-9)
	Check.near("and takes all of it", deg(r6.neckYaw), 70, 1e-9)
	hold(r6, math.rad(80), 0, 0.6, false)
	Check.ok("and lets go past its own reach", math.abs(deg(r6.headYaw)) < 2, `{deg(r6.headYaw)}`)

	local tilt = LookPose.new()
	hold(tilt, 0, math.rad(-50), 1)
	Check.near("the head takes its share of a look down", deg(tilt.headPitch), -30, 1e-3)
	Check.near("others see the waist bend", deg(tilt.waistPitch), -9, 1e-3)
	local own = LookPose.new()
	for _ = 1, 240 do
		LookPose.step(own, 0, math.rad(-50), settings, true, true, 1, DT)
	end
	Check.near("the player's own waist stays upright", deg(own.waistPitch), 0, 0)
	Check.near("and the neck takes the tilt", deg(own.neckPitch), -30, 1e-9)

	local faded = LookPose.new()
	LookPose.step(faded, math.rad(40), 0, settings, true, false, 0.5, DT)
	Check.near("a scale fades the pose", deg(faded.headYaw), 20, 1e-9)
end
