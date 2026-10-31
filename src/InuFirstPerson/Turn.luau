--!strict
-- Which way a character's body faces while it turns with the camera in first
-- person. The view (the eyes) turns first and the body follows it on a
-- spring, so it lags a quick turn and swings a little past, as a body with
-- weight does; the neck and waist take up the difference (Look).
--
-- A slack lets the feet stay put while the view turns within it either side;
-- the turn beyond it drags the body round on the same spring, so even a slow
-- turn moves the body smoothly rather than in steps.
--
-- The spring is solved exactly for a view that turns steadily through a
-- step, so a steady turn leaves the same lag at any frame rate. Requires
-- only Math, so the Lune tests can load it outside Roblox.

local Math = require(script.Parent.Math)

export type State = {
	-- The body's yaw (radians) and how fast it turns; nil until the first
	-- step.
	yaw: number?,
	speed: number,
	-- The view's yaw at the last step.
	lastView: number,
}

local Turn = {}

function Turn.new(): State
	return { speed = 0, lastView = 0 }
end

-- The next step starts with the body at rest facing `yaw` and the view at
-- `view` (radians), as when the character is taken over where it stands.
function Turn.reset(state: State, yaw: number, view: number)
	state.yaw = yaw
	state.speed = 0
	state.lastView = view
end

-- Advances to the view's `view` and returns the body's yaw (radians, within
-- ±pi). `slack` is radians, 0 for a body that follows the view itself;
-- `frequency` is Hz.
function Turn.step(
	state: State,
	view: number,
	slack: number,
	frequency: number,
	damping: number,
	dt: number
): number
	local yaw = state.yaw
	if yaw == nil then
		Turn.reset(state, view, view)
		return view
	end
	-- Both ends of the view's turn this step, unwrapped near the body.
	local turned = Math.shortestAngle(view - state.lastView)
	local viewAfter = yaw + Math.shortestAngle(view - yaw)
	local viewBefore = viewAfter - turned
	state.lastView = view

	local twist = viewAfter - yaw
	local speed = state.speed
	if math.abs(twist) <= slack then
		-- Within the slack the feet stay: nothing pulls, and what turn is left
		-- dies away.
		yaw, speed = Math.coast(yaw, speed, frequency, damping, dt)
	else
		-- The body is pulled to the slack's edge on the side the view is, which
		-- moves with the view.
		local edge = if twist > 0 then slack else -slack
		yaw, speed =
			Math.springFollow(yaw, speed, viewBefore - edge, viewAfter - edge, frequency, damping, dt)
	end

	local wrapped = Math.shortestAngle(yaw)
	state.yaw = wrapped
	state.speed = speed
	return wrapped
end

return Turn
