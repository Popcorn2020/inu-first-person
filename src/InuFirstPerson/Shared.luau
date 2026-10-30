--!strict
-- Values the parts pass to each other while running, and the API's signals.
-- Each value has one writer, named beside it; the others only read. The
-- signals live here, made once, so connections survive stop and start.

local Config = require(script.Parent.Config)
local Signal = require(script.Parent.Signal)

local Shared = {
	-- Written by init on start and configure.
	config = Config.defaults,

	-- Written by Camera: the camera is at the character's head this frame.
	firstPerson = false,
	-- Written by Camera: where the default camera looks this frame, before
	-- the motion goes on (radians: yaw, left positive, and pitch, up
	-- positive), and whether it follows the character at all.
	viewYaw = 0,
	viewPitch = 0,
	viewOnCharacter = false,

	-- Written by Sprint: walking and full sprinting speed after multipliers.
	walkingSpeed = 16,
	runningSpeed = 16,
	-- Written by Sprint: 0 with full stamina, 1 with none.
	fatigue = 0,

	-- Written by init: whether the steps time themselves (Config.debug.measure).
	measuring = false,
	-- Added to by every step while measuring, emptied by init once a second.
	spentTime = 0,

	signals = {
		firstPersonChanged = Signal.new() :: Signal.Signal<boolean>,
		sprintingChanged = Signal.new() :: Signal.Signal<boolean>,
		staminaChanged = Signal.new() :: Signal.Signal<number, number>,
		exhaustedChanged = Signal.new() :: Signal.Signal<boolean>,
	},
}

return Shared
