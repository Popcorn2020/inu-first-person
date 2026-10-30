--!strict
-- Every setting, with its default. A game changes them by passing a table of
-- overrides to InuFirstPerson.start (or, while running, to
-- InuFirstPerson.configure); only the keys it names change, so
-- `{ sprint = { runMultiplier = 1.4 } }` leaves the rest as below. A key that
-- does not exist here, or a value of the wrong type, is an error, so a typo
-- shows up when the game starts instead of silently doing nothing.
--
-- Units: distances in studs, speeds in studs per second, times in seconds,
-- angles in degrees. A "response time" is a time constant: the gap to the
-- target shrinks to about a third every response time, and 0 snaps at once.

local SyncProtocol = require(script.Parent.SyncProtocol)

local DEFAULTS = {
	camera = {
		-- "start" begins zoomed into first person and lets the player zoom out
		-- to third person (mouse wheel, pinch) and back. "lock" keeps the camera
		-- in first person (Player.CameraMode LockFirstPerson). "keep" leaves the
		-- camera mode and zoom to the game. "start" leaves Player.CameraMode as
		-- the game set it; "lock" puts the old mode back on stop.
		--
		-- In third person the walking motion (bob, tilt, sway, breathing,
		-- landing, step smoothing) and the eye are off, and the character turns
		-- as the Humanoid turns it, since the camera orbits it. Field of view
		-- offsets, kicks, the look of the head, sprinting and stamina carry on.
		-- A Scriptable camera, or one on another subject, gets no motion, kicks
		-- or offsets at all.
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
		-- Where the eye sits in first person: this far above the neck joint and
		-- this far in front of it, for a standard avatar (both scale with it).
		-- Looking ahead, that is about where the default camera puts the eye.
		-- The eye turns about the neck with the head (look.headPitchShare), so
		-- looking down it moves out over the chest and the body below is in
		-- view.
		eyeHeight = 0.6,
		eyeForward = 0.3,
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

	-- Characters pop up and down steps in a frame or two; the view climbs them
	-- at a steady pace instead. A rise the floor under the character explains
	-- (a slope, or a lift moved by physics) is followed as it is.
	stepSmoothing = {
		enabled = true,
		-- The view catches up with the character at the character's horizontal
		-- speed plus this, so it keeps pace on stairs up to about 45 degrees.
		catchUpSpeed = 4,
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

	-- InuFirstPerson.camera.kick: a quick snap with a slow settle under it,
	-- and a fine shake that dies away.
	kick = {
		-- The snap: a stiff spring that throws the view out and swings back a
		-- little past rest. Cycles per second, and damping (1 settles without
		-- overshoot, lower swings past more).
		frequency = 6,
		damping = 0.45,
		-- Share of each kick carried instead by a slow spring that eases the
		-- view back after the snap, the tail of the kick.
		settleShare = 0.35,
		settleFrequency = 1.4,
		settleDamping = 1,
		-- How much each kick shakes the view: at 1, a kick of 10 degrees shakes
		-- it fully. 0 turns the shake off.
		shake = 1,
		-- The shake at full, in degrees: X pitch, Y yaw, Z roll.
		shakeDegrees = Vector3.new(0.45, 0.45, 0.7),
		-- Cycles per second of the shake's noise.
		shakeFrequency = 16,
		-- A full shake dies away in 1 / shakeDecay seconds. It fades as the
		-- square of what is left, so the end is soft.
		shakeDecay = 1.2,
		-- Each kick's yaw and roll vary by up to this share of its size, so
		-- repeated kicks differ. Changing the seed changes how.
		variation = 0.3,
		seed = 0,
	},

	-- The player's own body in first person.
	body = {
		-- Shows the real character, all but the head and what is worn on it,
		-- which the default camera hides in first person.
		enabled = true,
	},

	-- Where each character looks: the head, waist and right arm turn toward
	-- the player's view on top of the animation, and in first person the
	-- character turns with the view.
	look = {
		enabled = true,
		-- Standing still in first person, the feet stay put until the view
		-- turns this far from them; then the body swings round to the view.
		turnThreshold = 50,
		-- How long the body takes to swing round to the view, standing or on
		-- starting to move. Moving or holding a Tool, it then turns with the
		-- view exactly, so the body and the tool never trail the camera.
		turnTime = 0.12,
		-- The head turns at most this far from the body. Past it, a standing
		-- body is pulled round; a seated or climbing one stays and the head
		-- stops.
		neckYawLimit = 70,
		-- Share of the view's tilt up and down that the head takes; the eyes
		-- take the rest, as people's do. The first-person eye moves with the
		-- head, so this also sets how far it swings out when looking down.
		headPitchShare = 0.6,
		-- Share of the head's turn and tilt the waist takes, the neck taking the
		-- rest (R6 has no waist, so its neck takes all). The player's own view
		-- never bends the waist forward or back, which would push the chest
		-- into the eye; the others see it.
		waistShare = 0.3,
		-- While a Tool is held, the right arm aims it where the player looks.
		toolAim = true,
		-- The arm trails the view by about this long, so the tool swings a
		-- little behind fast turns while the sway, bob and kicks move the view
		-- around it.
		toolAimLag = 0.05,
	},

	-- Sends where each player looks to the others, so they see the heads and
	-- arms turn. It needs the server half started (see the README); without
	-- it, each player sees only their own.
	sync = {
		enabled = true,
		-- At most this many updates a second, only while the angles change. The
		-- server takes up to 30.
		sendRate = 12,
		-- How quickly another player's head follows their updates.
		smoothTime = 0.1,
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
		-- do not reach Input Action System contexts of lower priority. The
		-- default player scripts' Shift lock still sees Shift; turn off
		-- StarterPlayer.EnableMouseLockOption.
		priority = 2000,
		sink = true,
	},

	ui = {
		enabled = true,
		-- A ScreenGui to use instead of the bundled one, laid out like
		-- Assets.InuFirstPersonUi: a Frame named Gauge holding a Frame named
		-- Fill (whose ExhaustedColor attribute, if any, colors it while
		-- exhausted), and optionally a GuiButton named SprintButton. Keep it out
		-- of StarterGui, which would show a second copy. false uses the bundled
		-- one.
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
	["kick.seed"] = true,
	["input.priority"] = true,
}
-- Numbers with an upper bound.
local MAXIMUMS: { [string]: number } = {
	["kick.settleShare"] = 1,
	["look.neckYawLimit"] = 180,
	["look.headPitchShare"] = 1,
	["look.waistShare"] = 1,
	["sync.sendRate"] = SyncProtocol.MAX_SEND_RATE,
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
		local maximum = MAXIMUMS[path]
		if maximum and value > maximum then
			fail(path, `takes {maximum} or less`)
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

-- `base` (the defaults, or the settings in use) with `overrides` merged in.
-- Types are checked against the defaults, whose lists are never empty.
local function merge(
	path: string,
	defaults: { [string]: any },
	base: { [string]: any },
	overrides: { [any]: any }
): { [string]: any }
	local result = table.clone(base)
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
			result[key] = merge(keyPath, default, base[key], value)
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

-- `base` (the defaults if nil) with `overrides` merged in, frozen. Errors on
-- an unknown key or a value of the wrong type; `caller` names the function in
-- the error for a value that is not a table.
function Config.resolve(overrides: { [any]: any }?, base: Config?, caller: string?): Config
	if overrides ~= nil and typeof(overrides) ~= "table" then
		error(`InuFirstPerson: {caller or "start"} takes a table of settings`, 0)
	end
	local resolved = merge("", DEFAULTS :: any, (base or DEFAULTS) :: any, overrides or {})
	deepFreeze(resolved)
	return (resolved :: any) :: Config
end

Config.defaults = Config.resolve(nil)

return Config
