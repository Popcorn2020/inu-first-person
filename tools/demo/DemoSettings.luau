--!strict
-- The settings the demo starts with, where they differ from the module's
-- defaults. A slider starts at its value here, and Reset puts the module's
-- default back, so a slider started away from its default shows orange.

return {
	camera = {
		-- Bigger than the default, so its slider is the one orange row and
		-- draws the eye to the motion first.
		motionScale = 1.5,
	},
	-- The cost of each frame, written to the module's attribute for the panel.
	debug = {
		measure = true,
	},
}
