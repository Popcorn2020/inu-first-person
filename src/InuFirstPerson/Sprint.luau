--!strict
-- Walking and sprinting speed, and stamina. While running, this module owns
-- Humanoid.WalkSpeed and writes it before every physics step, so a game
-- changes speeds through the API instead of writing the Humanoid.

local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

local Character = require(script.Parent.Character)
local Math = require(script.Parent.Math)
local Shared = require(script.Parent.Shared)
local SprintInput = require(script.Parent.SprintInput)
local StaminaModel = require(script.Parent.StaminaModel)
local Ui = require(script.Parent.Ui)

local MAX_DT = 0.1
-- Below this MoveDirection length the character counts as standing.
local STOPPED_INPUT = 0.1
-- A toggled sprint ends after standing this long, so changing keys from W to
-- D, which passes through no input for a frame, does not end it.
local STOP_GRACE = 0.2

local NO_SPRINT_STATES: { [Enum.HumanoidStateType]: true } = {
	[Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.Swimming] = true,
	[Enum.HumanoidStateType.Seated] = true,
	[Enum.HumanoidStateType.Dead] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
	[Enum.HumanoidStateType.Physics] = true,
	[Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.GettingUp] = true,
}

local Sprint = {}

local running = false
local enabled = true
local walkSpeedOverride: number? = nil
local multipliers: { [string]: number } = {}
local multiplierProduct = 1

local stamina = StaminaModel.new(Shared.config.stamina)
local sprinting = false
local speed = 0
local stoppedTime = 0
local lastRig: Character.Rig? = nil
local lastState: Enum.HumanoidStateType? = nil
local reportedValue = -1
local reportedExhausted = false
local warnedController = false
local connection: RBXScriptConnection? = nil

local function getBaseWalkSpeed(): number
	local override = walkSpeedOverride
	if override then
		return override
	end
	local configured = Shared.config.sprint.walkSpeed
	return if configured > 0 then configured else StarterPlayer.CharacterWalkSpeed
end

local function setSprinting(on: boolean)
	if sprinting == on then
		return
	end
	sprinting = on
	Shared.signals.sprintingChanged:Fire(on)
end

local function isFacingCamera(moveDirection: Vector3): boolean
	local maxAngle = Shared.config.sprint.maxAngle
	local camera = workspace.CurrentCamera
	if not Shared.firstPerson or maxAngle >= 180 or not camera then
		return true
	end
	local look = camera.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 1e-3 then
		return true
	end
	return flatLook.Unit:Dot(moveDirection.Unit) >= math.cos(math.rad(maxAngle))
end

local function decide(
	rig: Character.Rig,
	state: Enum.HumanoidStateType,
	walking: number,
	dt: number
): boolean
	local settings = Shared.config
	local humanoid = rig.humanoid
	local moveDirection = humanoid.MoveDirection

	stoppedTime = if moveDirection.Magnitude < STOPPED_INPUT then stoppedTime + dt else 0
	local exhausted = settings.stamina.enabled and stamina.exhausted
	if stoppedTime > STOP_GRACE or exhausted then
		SprintInput.clearToggles()
	end

	if not enabled or not settings.sprint.enabled or exhausted or stoppedTime > 0 then
		return false
	end
	if not SprintInput.wantsSprint() or humanoid.Sit or NO_SPRINT_STATES[state] then
		return false
	end
	if state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping then
		-- The run carries on through a jump, and does not start in the air.
		return sprinting
	end
	local velocity = rig.root.AssemblyLinearVelocity
	if
		Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		< walking * settings.sprint.minSpeedShare
	then
		return false
	end
	return isFacingCamera(moveDirection)
end

local function report()
	local settings = Shared.config.stamina
	local value = stamina.value
	Shared.fatigue = if settings.enabled then 1 - value / settings.max else 0
	if value ~= reportedValue then
		reportedValue = value
		Shared.signals.staminaChanged:Fire(value, settings.max)
	end
	if stamina.exhausted ~= reportedExhausted then
		reportedExhausted = stamina.exhausted
		Shared.signals.exhaustedChanged:Fire(stamina.exhausted)
	end
end

local function step(rawDt: number)
	debug.profilebegin("InuFirstPerson.Sprint")
	local started = os.clock()
	local dt = math.min(rawDt, MAX_DT)
	local settings = Shared.config
	local rig = Character.get()
	local walking = getBaseWalkSpeed() * multiplierProduct
	Shared.walkingSpeed = walking
	Shared.runningSpeed = walking * settings.sprint.runMultiplier

	if rig ~= lastRig then
		lastRig = rig
		setSprinting(false)
		speed = walking
		stoppedTime = 0
		lastState = nil
		if rig and settings.stamina.resetOnSpawn then
			StaminaModel.refill(stamina, settings.stamina)
		end
		if
			rig
			and not warnedController
			and rig.character:FindFirstChildOfClass("ControllerManager")
		then
			warnedController = true
			warn(
				"InuFirstPerson: this character uses a ControllerManager (Character Controller Library). "
					.. "Sprinting writes Humanoid.WalkSpeed; see the README for whether it moves this character."
			)
		end
	end

	if rig then
		local humanoid = rig.humanoid
		local state = humanoid:GetState()
		if
			settings.stamina.enabled
			and state == Enum.HumanoidStateType.Jumping
			and lastState ~= state
		then
			StaminaModel.spend(stamina, settings.stamina, settings.stamina.jumpCost)
		end
		lastState = state

		setSprinting(decide(rig, state, walking, dt))
		local target = if sprinting then Shared.runningSpeed else walking
		local responseTime = if target > speed
			then settings.sprint.accelerationTime
			else settings.sprint.decelerationTime
		speed = Math.approach(speed, target, responseTime, dt)
		humanoid.WalkSpeed = speed
	else
		setSprinting(false)
	end

	if settings.stamina.enabled then
		StaminaModel.step(stamina, settings.stamina, sprinting, dt)
	end
	report()
	Ui.update(
		stamina.value / settings.stamina.max,
		settings.stamina.enabled and stamina.exhausted,
		enabled and settings.sprint.enabled and rig ~= nil,
		dt
	)

	if Shared.measuring then
		Shared.spentTime += os.clock() - started
	end
	debug.profileend()
end

function Sprint.start()
	running = true
	enabled = true
	walkSpeedOverride = nil
	table.clear(multipliers)
	multiplierProduct = 1
	stamina = StaminaModel.new(Shared.config.stamina)
	sprinting = false
	lastRig = nil
	reportedValue = -1
	reportedExhausted = false
	connection = RunService.PreSimulation:Connect(step)
end

function Sprint.stop()
	if not running then
		return
	end
	running = false
	if connection then
		connection:Disconnect()
		connection = nil
	end
	local rig = Character.get()
	if rig then
		rig.humanoid.WalkSpeed = getBaseWalkSpeed()
	end
	setSprinting(false)
	lastRig = nil
	Shared.fatigue = 0
end

function Sprint.setEnabled(on: boolean)
	enabled = on
end

function Sprint.isEnabled(): boolean
	return enabled
end

function Sprint.isSprinting(): boolean
	return sprinting
end

-- nil goes back to Config.sprint.walkSpeed (or StarterPlayer.CharacterWalkSpeed).
function Sprint.setWalkSpeed(walkSpeed: number?)
	walkSpeedOverride = walkSpeed
end

-- The walking speed before multipliers.
function Sprint.getWalkSpeed(): number
	return getBaseWalkSpeed()
end

function Sprint.setSpeedMultiplier(key: string, multiplier: number?)
	if multiplier then
		multipliers[key] = multiplier
	else
		multipliers[key] = nil
	end
	local product = 1
	for _, value in multipliers do
		product *= value
	end
	multiplierProduct = product
end

function Sprint.getStamina(): number
	return stamina.value
end

function Sprint.setStamina(value: number)
	StaminaModel.set(stamina, Shared.config.stamina, value)
end

function Sprint.isExhausted(): boolean
	return stamina.exhausted
end

return Sprint
