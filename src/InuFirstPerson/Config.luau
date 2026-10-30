--!strict
-- Every setting, with its default. A game changes them by passing a table of
-- overrides to InuFirstPerson.start; only the keys it names change, so
-- `{ sprint = { runMultiplier = 1.4 } }` leaves the rest as below. A key that
-- does not exist here, or a value of the wrong type, is an error, so a typo
-- shows up when the game starts instead of silently doing nothing.
--
-- Units: distances in studs, speeds in studs per second, times in seconds,
-- angles in degrees. A "response time" is a time constant: the gap to the
-- target shrinks to about a third every response time, and 0 snaps at once.

local DEFAULTS = {
	camera = {
		-- "start" begins zoomed into first person and lets the player zoom out
		-- to third person (mouse wheel, pinch) and back. "lock" keeps the camera
		-- in first person (Player.CameraMode LockFirstPerson). "keep" leaves the
		-- camera mode and zoom to the game. What was there comes back on stop.
		--
		-- In third person the body copy stops and hides and the walking motion
		-- (bob, tilt, sway, breathing, landing, step smoothing) is off, since the
		-- real character shows and the camera orbits it. Field of view offsets,
		-- kicks, sprinting and stamina carry on.
		firstPerson = "start" :: "start" | "lock" | "keep",
		-- How quickly the walking motion fades back in after zooming into first
		-- person.
		transitionTime = 0.2,
		-- Camera.FieldOfView set on start. 0 keeps the camera's own value.
		fieldOfView = 70,
		-- Multiplies every camera motion below (bob, tilt, sway, breathing,
		-- landing, sprint field of view, kicks). 0 keeps the view still.
		motionScale = 1,
		-- Extra multiplier while the player's Reduce Motion setting is on.
		reducedMotionScale = 0.5,
		-- Extra multiplier in VR. 0 keeps the view still against motion sickness.
		vrScale = 0,
	},

	-- The head's rise and fall and side to side sway while walking.
	bob = {
		-- Full cycles (two steps) per second at referenceSpeed.
		frequency = 1.4,
		-- Speed at which the bob runs at `frequency` and at its full walking size.
		-- Slower walking bobs slower and smaller.
		referenceSpeed = 16,
		-- How the step rate grows with speed: frequency * (speed /
		-- referenceSpeed) ^ cadencePower. 0.5 lengthens the strides as well as
		-- quickening them, as people do; 1 only quickens them.
		cadencePower = 0.5,
		-- X sways left and right once per cycle; Y dips once per step.
		amplitude = Vector3.new(0.035, 0.07, 0),
		-- Roll at the side of each sway.
		rollDegrees = 0.2,
		-- Size multiplier at full sprinting speed.
		sprintScale = 1.7,
		-- Size multiplier while climbing, where the climbing speed drives the bob.
		climbScale = 0.5,
		-- How quickly the bob eases in when walking starts and out when it stops.
		responseTime = 0.12,
	},

	-- The view leans into sideways movement.
	strafeTilt = {
		-- Roll at full sideways input.
		degrees = 1,
		responseTime = 0.2,
	},

	-- A slow drift and a fine jitter, as if the camera were held by hand. The
	-- sum of both bands is what shows.
	sway = {
		-- Changing it changes the path of the sway.
		seed = 0,
		drift = {
			-- Cycles per second of the noise.
			frequency = 0.4,
			position = Vector3.new(0.01, 0.01, 0.01),
			-- X pitch, Y yaw, Z roll.
			rotationDegrees = Vector3.new(0.16, 0.16, 0.2),
		},
		jitter = {
			frequency = 0.85,
			position = Vector3.new(0.006, 0.006, 0.006),
			rotationDegrees = Vector3.new(0.05, 0.05, 0.05),
		},
		-- Multiplier on the sway when stamina is empty; it fades back to 1 as
		-- stamina refills.
		tiredScale = 2,
	},

	-- Breathing: barely there at rest, heavy after sprinting.
	breathing = {
		-- Breaths per second at rest and with empty stamina.
		rate = 0.25,
		tiredRate = 0.85,
		-- Pitch nod of each breath at rest and with empty stamina.
		pitchDegrees = 0.05,
		tiredPitchDegrees = 0.5,
		-- Rise of each breath at rest and with empty stamina.
		height = 0.004,
		tiredHeight = 0.03,
		-- How quickly the breathing follows the stamina as it drains and refills.
		responseTime = 0.6,
	},

	-- The view dips and springs back when the character lands.
	landing = {
		-- Falling speed at which landings start to dip, and at which the dip is
		-- full. A normal jump lands at about 50.
		minSpeed = 10,
		maxSpeed = 100,
		-- The dip at maxSpeed: how far the view drops and how far it nods down.
		drop = 0.5,
		pitchDegrees = 3,
		-- The spring that carries the dip: cycles per second, and damping (1
		-- settles without overshoot, lower bounces a little).
		frequency = 2.2,
		damping = 0.55,
	},

	-- Characters pop up steps in a frame or two; the view rises smoothly instead.
	stepSmoothing = {
		-- How quickly the view catches up with the character. 0 turns it off.
		responseTime = 0.08,
		-- Vertical speed, on top of the walking speed, that passes without
		-- smoothing, so walking up and down slopes is not delayed.
		allowance = 20,
		-- The most the view can trail the character.
		maxOffset = 2,
		-- A jump in height bigger than this in one frame is a teleport, which
		-- is not smoothed.
		teleportDistance = 4,
	},

	-- The field of view widens a little while sprinting.
	sprintFov = {
		-- Degrees added at full sprinting speed.
		degrees = 5,
		responseTime = 0.2,
	},

	-- The springs that carry InuFirstPerson.camera.kick.
	kick = {
		frequency = 5,
		damping = 0.6,
	},

	-- The player's own body, seen when looking down.
	body = {
		enabled = true,
		-- Where the body sits from the character's root, in the camera's facing
		-- (X right, Y up, Z back), for a root 2 studs tall; it scales with the
		-- avatar. Pushing the body back keeps the camera out of the chest.
		offset = Vector3.new(0, 0.15, 1.25),
		-- The body trails fast camera turns by about this long. 0 turns with the
		-- camera exactly.
		turnLag = 0.07,
		-- The most the body can trail behind the camera.
		maxTurnLag = 10,
		-- While a Tool is held, draws the right arm where the real arm is, so
		-- the hand meets the tool, which first person shows at the real hand.
		toolArm = true,
		-- The copy is rebuilt once the character has had no visible parts added
		-- or removed for this long, since appearances load over several frames.
		rebuildDelay = 0.15,
	},

	sprint = {
		enabled = true,
		-- Walking speed. 0 uses StarterPlayer.CharacterWalkSpeed. While running,
		-- this module owns Humanoid.WalkSpeed; change it through
		-- InuFirstPerson.sprint.setWalkSpeed, not by writing the Humanoid.
		walkSpeed = 0,
		-- Sprinting speed as a multiple of the walking speed.
		runMultiplier = 1.6,
		-- How long the speed takes to rise to sprinting and fall back to walking.
		accelerationTime = 0.12,
		decelerationTime = 0.18,
		-- In first person, sprinting only works while moving within this angle
		-- of where the camera faces. 180 allows any direction. In third person
		-- the character turns to where it runs, so any direction works.
		maxAngle = 50,
		-- Share of the walking speed the character must be moving at to sprint,
		-- so a thumbstick pushed part way, or pushing into a wall, walks.
		minSpeedShare = 0.5,
	},

	stamina = {
		-- false lets sprinting go on forever and hides the gauge.
		enabled = true,
		max = 100,
		-- Used per second while sprinting (8 seconds from full).
		drainRate = 12.5,
		-- Refilled per second (5 seconds from empty).
		regenRate = 20,
		-- Wait after sprinting stops before refilling starts.
		regenDelay = 1,
		-- After running out, sprinting waits until stamina is back to this share
		-- of max. Holding the sprint input resumes sprinting then.
		recoverShare = 0.3,
		-- Used by each jump. 0 makes jumping free.
		jumpCost = 0,
		-- Refills stamina when the character respawns.
		resetOnSpawn = true,
	},

	input = {
		keyboard = { Enum.KeyCode.LeftShift } :: { Enum.KeyCode },
		gamepad = { Enum.KeyCode.ButtonL3 } :: { Enum.KeyCode },
		-- "hold" sprints while held; "toggle" starts sprinting on a press and
		-- stops on the next press, when the character stops moving or when
		-- stamina runs out.
		keyboardMode = "hold" :: "hold" | "toggle",
		gamepadMode = "toggle" :: "hold" | "toggle",
		touchMode = "hold" :: "hold" | "toggle",
		-- The InputContext's Priority and Sink. With Sink on, the sprint keys
		-- do not reach lower contexts, such as the default player scripts' Shift
		-- lock toggle.
		priority = 2000,
		sink = true,
	},

	ui = {
		enabled = true,
		-- A ScreenGui to use instead of the bundled one. It needs the same
		-- named children as Assets.InuFirstPersonUi (see the README). false
		-- uses the bundled one.
		template = false :: ScreenGui | false,
		-- The sprint button for touch screens: "auto" shows it while touch is
		-- the player's preferred input, "always" and "never" do what they say.
		sprintButton = "auto" :: "auto" | "always" | "never",
		-- The gauge stays this long after stamina is full again, then fades.
		hideDelay = 1.5,
		fadeTime = 0.25,
	},

	debug = {
		-- Writes the average time this module took per frame, in milliseconds,
		-- to the attribute InuFirstPersonFrameMs on the module, once a second.
		measure = false,
	},
}

export type Config = typeof(DEFAULTS)

-- Settings that take a choice of strings.
local CHOICES: { [string]: { string } } = {
	["camera.firstPerson"] = { "start", "lock", "keep" },
	["input.keyboardMode"] = { "hold", "toggle" },
	["input.gamepadMode"] = { "hold", "toggle" },
	["input.touchMode"] = { "hold", "toggle" },
	["ui.sprintButton"] = { "auto", "always", "never" },
}
-- Settings whose default false stands for "none", and the class they take.
local INSTANCE_SETTINGS: { [string]: string } = {
	["ui.template"] = "ScreenGui",
}
-- Numbers that may be negative. Every other number must be 0 or more.
local SIGNED_SETTINGS: { [string]: true } = {
	["sway.seed"] = true,
	["input.priority"] = true,
}

local Config = {}

local function fail(path: string, message: string): never
	error(`InuFirstPerson: setting '{path}' {message}`, 0)
end

local function checkLeaf(path: string, default: any, value: any)
	local instanceClass = INSTANCE_SETTINGS[path]
	if instanceClass then
		if value ~= false and not (typeof(value) == "Instance" and value:IsA(instanceClass)) then
			fail(path, `takes a {instanceClass} or false`)
		end
		return
	end

	local expected = typeof(default)
	if typeof(value) ~= expected then
		fail(path, `takes a {expected}, got a {typeof(value)}`)
	end
	if expected == "number" then
		if not math.isfinite(value) then
			fail(path, "takes a finite number")
		end
		if value < 0 and not SIGNED_SETTINGS[path] then
			fail(path, "takes 0 or more")
		end
	elseif expected == "string" then
		local choices = CHOICES[path]
		if choices and not table.find(choices, value) then
			fail(path, `takes one of "{table.concat(choices, '", "')}"`)
		end
	elseif expected == "EnumItem" then
		if value.EnumType ~= default.EnumType then
			fail(path, `takes a {tostring(default.EnumType)}`)
		end
	end
end

local function isList(value: { [any]: any }): boolean
	return #value > 0
end

local function merge(
	path: string,
	defaults: { [string]: any },
	overrides: { [any]: any }
): { [string]: any }
	local result = table.clone(defaults)
	for key, value in overrides do
		local keyPath = if path == "" then tostring(key) else `{path}.{key}`
		local default = if typeof(key) == "string" then defaults[key] else nil
		if default == nil then
			fail(keyPath, "does not exist")
		end
		if typeof(default) ~= "table" then
			checkLeaf(keyPath, default, value)
			result[key] = value
		elseif typeof(value) ~= "table" then
			fail(keyPath, `takes a table, got a {typeof(value)}`)
		elseif isList(default) then
			-- Lists are replaced whole.
			for index, item in value do
				if typeof(index) ~= "number" then
					fail(keyPath, "takes a list")
				end
				checkLeaf(`{keyPath}[{index}]`, default[1], item)
			end
			result[key] = table.clone(value)
		else
			result[key] = merge(keyPath, default, value)
		end
	end
	return result
end

local function deepFreeze(value: { [any]: any })
	for _, child in value do
		if typeof(child) == "table" and not table.isfrozen(child) then
			deepFreeze(child)
		end
	end
	table.freeze(value)
end

-- The defaults with `overrides` merged in, frozen. Errors on an unknown key
-- or a value of the wrong type.
function Config.resolve(overrides: { [any]: any }?): Config
	if overrides ~= nil and typeof(overrides) ~= "table" then
		error("InuFirstPerson: start takes a table of settings or nothing", 0)
	end
	local resolved = merge("", DEFAULTS :: any, overrides or {})
	deepFreeze(resolved)
	return (resolved :: any) :: Config
end

Config.defaults = Config.resolve(nil)

return Config
