--!strict
-- InuFirstPerson: a first-person base for any Roblox experience. It puts the
-- camera at the eye and moves it like a head (bob, lean, sway, breathing,
-- landing, smooth steps, kicks), shows the player's own body, turns heads,
-- waists and arms to where players look, and adds sprinting with stamina, a
-- gauge and a touch button. It runs on the client:
--
--     local InuFirstPerson = require(ReplicatedStorage.InuFirstPerson)
--     InuFirstPerson.start({ sprint = { runMultiplier = 1.5 } })
--
-- Others see where each player looks once the server half,
-- InuFirstPersonServer, is started too. Config.luau lists every setting with
-- its default; the functions below are the whole API.

local RunService = game:GetService("RunService")

local Body = require(script.Body)
local Camera = require(script.Camera)
local Config = require(script.Config)
local Look = require(script.Look)
local Shared = require(script.Shared)
local Sprint = require(script.Sprint)
local SprintInput = require(script.SprintInput)
local Ui = require(script.Ui)
local Version = require(script.Version)

local MEASURE_ATTRIBUTE = "InuFirstPersonFrameMs"
local MEASURE_PERIOD = 1

local running = false
local measureConnection: RBXScriptConnection? = nil

local function requireRunning(name: string)
	if not running then
		error(`InuFirstPerson.{name} needs InuFirstPerson.start() first`, 3)
	end
end

local function checkNumber(name: string, value: any, allowNegative: boolean?)
	if
		typeof(value) ~= "number"
		or not math.isfinite(value)
		or (not allowNegative and value < 0)
	then
		error(
			`InuFirstPerson.{name} takes a finite number{if allowNegative
				then ""
				else " of 0 or more"}`,
			3
		)
	end
end

local function checkKey(name: string, key: any)
	if typeof(key) ~= "string" then
		error(`InuFirstPerson.{name} takes a string key first`, 3)
	end
end

local function startMeasuring()
	local frames = 0
	local elapsed = 0
	Shared.spentTime = 0
	measureConnection = RunService.Heartbeat:Connect(function(dt)
		frames += 1
		elapsed += dt
		if elapsed >= MEASURE_PERIOD then
			script:SetAttribute(MEASURE_ATTRIBUTE, Shared.spentTime / frames * 1000)
			Shared.spentTime = 0
			frames = 0
			elapsed = 0
		end
	end)
end

local InuFirstPerson = {}

InuFirstPerson.version = Version

-- Starts everything for the local player. `overrides` changes settings by
-- naming only what differs from Config.luau; an unknown key or a wrong type
-- is an error. Errors if already running or called on the server.
function InuFirstPerson.start(overrides: { [any]: any }?)
	if not RunService:IsClient() then
		error(
			"InuFirstPerson runs on the client: start it from a LocalScript or a Client Script",
			2
		)
	end
	if running then
		error("InuFirstPerson is already running; call stop() first", 2)
	end
	local config = Config.resolve(overrides)
	Shared.config = config
	Shared.measuring = config.debug.measure

	local button = Ui.start()
	SprintInput.start(button)
	Sprint.start()
	Body.start()
	Look.start()
	Camera.start()
	if config.debug.measure then
		startMeasuring()
	end
	running = true
end

-- Stops everything and puts back what start changed (camera mode, zoom,
-- field of view, AutoRotate, the joints it turned); the character keeps
-- walking at its walking speed, without sprinting or multipliers. What the
-- functions below set is cleared.
function InuFirstPerson.stop()
	if not running then
		return
	end
	running = false
	-- The body first, while the camera still knows it is in first person.
	Body.stop()
	Look.stop()
	Camera.stop()
	Sprint.stop()
	SprintInput.stop()
	Ui.stop()
	if measureConnection then
		measureConnection:Disconnect()
		measureConnection = nil
		script:SetAttribute(MEASURE_ATTRIBUTE, nil)
	end
	Shared.measuring = false
	Shared.config = Config.defaults
end

function InuFirstPerson.isRunning(): boolean
	return running
end

-- The settings in use (the defaults while stopped). Frozen.
function InuFirstPerson.getConfig(): Config.Config
	return Shared.config
end

-- Changes settings while running, naming only what differs from the
-- settings in use, checked as start checks them. Most take effect at once;
-- those read only on start (camera.firstPerson, camera.fieldOfView, input,
-- ui.enabled, ui.template, ui.sprintButton, debug) wait for the next start.
function InuFirstPerson.configure(overrides: { [any]: any })
	requireRunning("configure")
	Shared.config = Config.resolve(overrides, Shared.config, "configure")
	Sprint.applyConfig()
end

InuFirstPerson.camera = {
	-- Fires with true on zooming into first person and false on leaving it.
	FirstPersonChanged = Shared.signals.firstPersonChanged.event,

	-- Turns the camera motion off and on. The camera mode stays as it is.
	setEnabled = function(enabled: boolean)
		requireRunning("camera.setEnabled")
		Camera.setEnabled(enabled == true)
	end,
	isEnabled = function(): boolean
		return running and Camera.isEnabled()
	end,
	-- Whether the camera is at the character's head this frame.
	isFirstPerson = function(): boolean
		return Shared.firstPerson
	end,
	-- A jolt that swings out to `rotationDegrees` (X pitch up, Y yaw left,
	-- Z roll left) and `position` (studs, in camera space) and springs back,
	-- as for recoil or a hit. Kicks add up.
	kick = function(rotationDegrees: Vector3, position: Vector3?)
		requireRunning("camera.kick")
		if
			typeof(rotationDegrees) ~= "Vector3"
			or (position ~= nil and typeof(position) ~= "Vector3")
		then
			error(
				"InuFirstPerson.camera.kick takes a Vector3 of degrees and an optional Vector3 of studs",
				2
			)
		end
		Camera.kick(rotationDegrees, position)
	end,
	-- Holds an offset on the camera, in its own space, under `key` until set
	-- again or cleared with nil (a lean, an aim). Offsets multiply together
	-- in the order of their keys.
	setOffset = function(key: string, offset: CFrame?)
		requireRunning("camera.setOffset")
		checkKey("camera.setOffset", key)
		if offset ~= nil and typeof(offset) ~= "CFrame" then
			error("InuFirstPerson.camera.setOffset takes a CFrame or nil", 2)
		end
		Camera.setOffset(key, offset)
	end,
	-- Adds degrees to the field of view under `key` until cleared with nil.
	-- Offsets add up, on top of the sprint widening.
	setFovOffset = function(key: string, degrees: number?)
		requireRunning("camera.setFovOffset")
		checkKey("camera.setFovOffset", key)
		if degrees ~= nil then
			checkNumber("camera.setFovOffset", degrees, true)
		end
		Camera.setFovOffset(key, degrees)
	end,
	-- The motion put on the camera this frame, in its own space. Something
	-- that should sway with the view, like a lamp, can follow it. Read it
	-- after Enum.RenderPriority.Camera.Value + 1.
	getLayer = function(): CFrame
		return Camera.getLayer()
	end,
	-- How much each part of the motion turns the view this frame, in
	-- degrees: bob, sway, breath, tilt, landing, kick (the springs), shake
	-- (the kicks' shake) and rotation (all of it); position, how far the
	-- motion moves the view, in studs; fatigue, 0 with full stamina to 1
	-- with none; fovOffset, degrees. All 0 while the motion is off. A new
	-- table each call.
	getMotion = function(): Camera.Motion
		return Camera.getMotion()
	end,
}

InuFirstPerson.body = {
	-- Hides the body in first person, as the default camera does, or shows
	-- it again.
	setEnabled = function(enabled: boolean)
		requireRunning("body.setEnabled")
		Body.setEnabled(enabled == true)
	end,
	isEnabled = function(): boolean
		return running and Body.isEnabled()
	end,
}

InuFirstPerson.look = {
	-- Turns off, or back on, everything this client does about where
	-- characters look: turning the local character with the view in first
	-- person (Humanoid.AutoRotate is the game's again), and the head, waist
	-- and arm of every character. Others still see the local player's look
	-- fade to straight ahead.
	setEnabled = function(enabled: boolean)
		requireRunning("look.setEnabled")
		Look.setEnabled(enabled == true)
	end,
	isEnabled = function(): boolean
		return running and Look.isEnabled()
	end,
	-- `callback(character, player)` runs every frame right after the look
	-- turns a character's joints: the local character, and each other one
	-- whose look shows. It runs before physics, where the Animator has written
	-- the pose, so it may write joints' Transform on top (an IK that brings
	-- the left hand to a held Tool, say). What it writes on the neck, waist
	-- and right shoulder is redone each frame from the animation. It must not
	-- yield. nil removes it.
	setPoseCallback = function(callback: Look.PoseCallback?)
		requireRunning("look.setPoseCallback")
		if callback ~= nil and typeof(callback) ~= "function" then
			error("InuFirstPerson.look.setPoseCallback takes a function or nil", 2)
		end
		Look.setPoseCallback(callback)
	end,
	-- Where `player` (the local player if nil) looks as this client shows
	-- it, in degrees relative to their character's facing: yaw (left
	-- positive), then pitch (up positive). nil, nil while nothing is known.
	getAngles = function(player: Player?): (number?, number?)
		if player ~= nil and (typeof(player) ~= "Instance" or not player:IsA("Player")) then
			error("InuFirstPerson.look.getAngles takes a Player or nothing", 2)
		end
		if not running then
			return nil, nil
		end
		return Look.getAngles(player)
	end,
}

InuFirstPerson.sprint = {
	-- Fires with true when sprinting starts and false when it stops.
	Changed = Shared.signals.sprintingChanged.event,

	-- Allows sprinting or not. Stamina keeps refilling while it is off.
	setEnabled = function(enabled: boolean)
		requireRunning("sprint.setEnabled")
		Sprint.setEnabled(enabled == true)
	end,
	isEnabled = function(): boolean
		return running and Sprint.isEnabled()
	end,
	isSprinting = function(): boolean
		return running and Sprint.isSprinting()
	end,
	-- Sets the walking speed. nil goes back to the setting.
	setWalkSpeed = function(walkSpeed: number?)
		requireRunning("sprint.setWalkSpeed")
		if walkSpeed ~= nil then
			checkNumber("sprint.setWalkSpeed", walkSpeed)
		end
		Sprint.setWalkSpeed(walkSpeed)
	end,
	-- The walking speed before multipliers.
	getWalkSpeed = function(): number
		return Sprint.getWalkSpeed()
	end,
	-- Multiplies walking and sprinting speed under `key` until cleared with
	-- nil (carrying something heavy, a slowing hit). Multipliers multiply.
	setSpeedMultiplier = function(key: string, multiplier: number?)
		requireRunning("sprint.setSpeedMultiplier")
		checkKey("sprint.setSpeedMultiplier", key)
		if multiplier ~= nil then
			checkNumber("sprint.setSpeedMultiplier", multiplier)
		end
		Sprint.setSpeedMultiplier(key, multiplier)
	end,
}

InuFirstPerson.stamina = {
	-- Fires with (value, max) whenever stamina changes.
	Changed = Shared.signals.staminaChanged.event,
	-- Fires with true on running out and false once sprinting is allowed again.
	ExhaustedChanged = Shared.signals.exhaustedChanged.event,

	get = function(): number
		return if running then Sprint.getStamina() else Shared.config.stamina.max
	end,
	getMax = function(): number
		return Shared.config.stamina.max
	end,
	-- Sets stamina, clamped to 0..max.
	set = function(value: number)
		requireRunning("stamina.set")
		checkNumber("stamina.set", value, true)
		Sprint.setStamina(value)
	end,
	-- Adds to stamina (negative takes away), clamped to 0..max.
	add = function(amount: number)
		requireRunning("stamina.add")
		checkNumber("stamina.add", amount, true)
		Sprint.setStamina(Sprint.getStamina() + amount)
	end,
	isExhausted = function(): boolean
		return running and Sprint.isExhausted()
	end,
}

return InuFirstPerson
