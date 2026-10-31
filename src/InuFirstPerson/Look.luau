--!strict
-- Where the characters look.
--
-- In first person the local character turns with the view, the view first
-- and the body after it on a spring (Turn), so a quick look to the side
-- shows the head go first and the body come round behind it. While it
-- stands, walks, jumps, falls, climbs or swims, this module turns
-- Humanoid.AutoRotate off and sets the root's facing right after the default
-- camera, in the same frame as the camera; left to the Humanoid, the root
-- turns a frame late and swings past in jerks. Seated or in third person,
-- the Humanoid turns the character as usual.
--
-- On every character it shows, the neck, waist and right shoulder turn
-- toward where that player looks, on top of the animation: LookPose shares
-- the look out between them and Joints turns them. That is done before
-- physics, the last moment the Animator leaves alone, so a turn shows from
-- the next frame. The local player's look comes from the camera, the
-- others' from Sync.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Character = require(script.Parent.Character)
local Joints = require(script.Parent.Joints)
local LookPose = require(script.Parent.LookPose)
local Math = require(script.Parent.Math)
local Shared = require(script.Parent.Shared)
local Sync = require(script.Parent.Sync)
local Turn = require(script.Parent.Turn)

local MAX_DT = 0.1
-- Below this MoveDirection length the character counts as standing.
local MOVING_INPUT = 0.1
-- Humanoid states in which the character turns with the view in first person.
-- Climbing and swimming are kept here, not handed back: given AutoRotate in
-- first person, the Humanoid faces the character along the line from the
-- camera to it, and the eye sits in front of the character, so it would turn
-- the character round, off the ladder, and back again each time it took it.
local FACING_STATES: { [Enum.HumanoidStateType]: true } = {
	[Enum.HumanoidStateType.Running] = true,
	[Enum.HumanoidStateType.RunningNoPhysics] = true,
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.Landed] = true,
	[Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.Swimming] = true,
}
-- Characters farther than this from the camera keep their animation as is.
local LOOK_DISTANCE = 150
-- A look this small (radians) is taken as none, so a fading look ends.
local LOOK_EPSILON = 1e-4
-- The root's facing is rewritten only when it is off by more than this.
local FACING_EPSILON = 1e-5

export type PoseCallback = (character: Model, player: Player) -> ()

type Entry = {
	-- The character the look was last shown on (others only; the local
	-- entry goes by its joints' character).
	character: Model?,
	joints: Joints.Set?,
	pose: LookPose.State,
	-- The look, in radians relative to the root: yaw left, pitch up. The
	-- others' ease toward what Sync last brought, at these speeds.
	yaw: number,
	pitch: number,
	yawSpeed: number,
	pitchSpeed: number,
}

local Look = {}

local player = Players.LocalPlayer

local running = false
local enabled = true
local connections: { RBXScriptConnection } = {}

local turn = Turn.new()
-- The Humanoid whose AutoRotate this module has turned off.
local ownedHumanoid: Humanoid? = nil

local function newEntry(): Entry
	return { pose = LookPose.new(), yaw = 0, pitch = 0, yawSpeed = 0, pitchSpeed = 0 }
end

local own = newEntry()
-- 0..1: how much of the local look shows, easing with the camera's mode.
local ownWeight = 0
-- Where a held Tool aims, trailing the view: world yaw (unwrapped near the
-- view's) and pitch, and the view they trailed at the last step.
local aimYaw = 0
local aimPitch = 0
local aimViewYaw: number? = nil
local aimViewPitch = 0

local others: { [Player]: Entry } = {}
local poseCallback: PoseCallback? = nil

-- The look settings in LookPose's units, refreshed each step.
local poseSettings: LookPose.Settings = {
	neckYawLimit = 0,
	lookAwayAngle = 0,
	headPitchShare = 0,
	waistShare = 0,
	waistLag = 0,
}

local function facesView(humanoid: Humanoid): boolean
	return not humanoid.Sit
		and not humanoid.PlatformStand
		and FACING_STATES[humanoid:GetState()] == true
end

local function releaseRoot()
	local humanoid = ownedHumanoid
	if not humanoid then
		return
	end
	ownedHumanoid = nil
	if humanoid.Parent then
		humanoid.AutoRotate = true
	end
end

-- Each frame from Camera, right after the default camera and before the
-- eye is placed.
function Look.face(rig: Character.Rig?, firstPerson: boolean, dt: number)
	if not running then
		return
	end
	local humanoid = if rig then rig.humanoid else nil
	if ownedHumanoid and ownedHumanoid ~= humanoid then
		releaseRoot()
	end
	if not rig or not humanoid then
		return
	end
	local settings = Shared.config.look
	local owns = enabled
		and settings.enabled
		and firstPerson
		and Shared.viewOnCharacter
		and facesView(humanoid)
	if owns and ownedHumanoid == nil and not humanoid.AutoRotate then
		-- The game turned AutoRotate off, so it is turning the character.
		owns = false
	end
	if not owns then
		releaseRoot()
		return
	end

	local root = rig.root
	local viewYaw = Shared.viewYaw
	local _, rootYaw = root.CFrame:ToEulerAnglesYXZ()
	if ownedHumanoid == nil then
		ownedHumanoid = humanoid
		Turn.reset(turn, rootYaw, viewYaw)
	end
	if humanoid.AutoRotate then
		humanoid.AutoRotate = false
	end

	local follow = humanoid.MoveDirection.Magnitude > MOVING_INPUT
		or rig.character:FindFirstChildOfClass("Tool") ~= nil
	local yaw = Turn.step(
		turn,
		viewYaw,
		if follow then 0 else math.rad(settings.standTwist),
		settings.turnFrequency,
		settings.turnDamping,
		dt
	)
	if math.abs(Math.shortestAngle(yaw - rootYaw)) > FACING_EPSILON then
		root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
	end
	local spin = root.AssemblyAngularVelocity
	if spin.Y ~= 0 then
		root.AssemblyAngularVelocity = Vector3.new(spin.X, 0, spin.Z)
	end
end

-- A world view (yaw, pitch) relative to a root, as yaw and pitch again.
local function relativeTo(rootCFrame: CFrame, yaw: number, pitch: number): (number, number)
	local look = rootCFrame:VectorToObjectSpace(CFrame.fromEulerAnglesYXZ(pitch, yaw, 0).LookVector)
	return math.atan2(-look.X, -look.Z), math.asin(math.clamp(look.Y, -1, 1))
end

-- Takes the look off the character's joints, keeping them for next time,
-- and starts the pose over from the front.
local function unturn(entry: Entry)
	local set = entry.joints
	if set then
		Joints.releaseAll(set)
	end
	LookPose.reset(entry.pose)
end

local function forget(entry: Entry)
	unturn(entry)
	entry.joints = nil
end

local function jointsFor(entry: Entry, character: Model, root: BasePart): Joints.Set
	local set = entry.joints
	if set and set.character == character and Joints.isCurrent(set, root) then
		return set
	end
	forget(entry)
	local found = Joints.find(character, root)
	entry.joints = found
	return found
end

-- Turns a character's joints to its look, through LookPose, and with
-- `aiming` points the right arm at the aim. `ownView` keeps the waist from
-- bending forward or back; `scale` fades the whole pose.
local function pose(
	entry: Entry,
	character: Model,
	root: BasePart,
	aiming: boolean,
	aimRelativeYaw: number,
	aimRelativePitch: number,
	ownView: boolean,
	scale: number,
	dt: number
)
	local set = jointsFor(entry, character, root)
	local waist, neck, shoulder = set.waist, set.neck, set.shoulder
	local state = entry.pose
	local hasWaist = waist ~= nil
	LookPose.step(state, entry.yaw, entry.pitch, poseSettings, hasWaist, ownView, scale, dt)
	if waist then
		Joints.turn(waist, state.waistYaw, state.waistPitch)
	end
	if neck then
		Joints.turn(neck, state.neckYaw, state.neckPitch)
	end
	if shoulder then
		if aiming then
			-- The arm aims where the head does, letting go with it.
			local reach = LookPose.getReach(poseSettings, hasWaist)
			local weight = state.weight * scale
			Joints.turn(
				shoulder,
				math.clamp(aimRelativeYaw, -reach, reach) * weight - state.waistYaw,
				aimRelativePitch * weight - state.waistPitch
			)
		else
			Joints.release(shoulder)
		end
	end
end

-- Runs the game's callback on a character the look has just posed. What the
-- callback writes on the look's joints is taken as the look's own, so the
-- look goes on the animation next frame, not on top of the callback.
local function afterPose(entry: Entry, character: Model, owner: Player)
	local callback = poseCallback
	if not callback then
		return
	end
	-- An error is reported without stopping the step for the other characters.
	xpcall(callback, function(message: unknown)
		task.spawn(error, `InuFirstPerson look pose callback: {message}`, 0)
	end, character, owner)
	local set = entry.joints
	if set then
		Joints.adopt(set)
	end
end

local function isAiming(character: Model): boolean
	return Shared.config.look.toolAim and character:FindFirstChildOfClass("Tool") ~= nil
end

-- The Tool's aim trails the view by toolAimLag, exactly for a view that
-- turns steadily through the step, so the trail is the same at any frame
-- rate.
local function stepAim(dt: number)
	local viewYaw, viewPitch = Shared.viewYaw, Shared.viewPitch
	local lastViewYaw = aimViewYaw
	if lastViewYaw == nil then
		aimYaw, aimPitch = viewYaw, viewPitch
		aimViewYaw, aimViewPitch = viewYaw, viewPitch
		return
	end
	local lag = Shared.config.look.toolAimLag
	local unwrapped = lastViewYaw + Math.shortestAngle(viewYaw - lastViewYaw)
	aimYaw = Math.follow(aimYaw, lastViewYaw, unwrapped, lag, dt)
	aimPitch = Math.follow(aimPitch, aimViewPitch, viewPitch, lag, dt)
	-- Kept near the view's yaw so a long spin does not lose precision.
	local wrapped = Math.shortestAngle(unwrapped)
	aimYaw += wrapped - unwrapped
	aimViewYaw, aimViewPitch = wrapped, viewPitch
end

local function stepOwn(dt: number, on: boolean)
	local rig = Character.get()
	local wanted = if on and Shared.viewOnCharacter then 1 else 0
	ownWeight = Math.approach(ownWeight, wanted, Shared.config.camera.transitionTime, dt)
	if wanted == 0 and ownWeight < LOOK_EPSILON then
		ownWeight = 0
	end
	stepAim(dt)
	if not rig or ownWeight == 0 then
		own.yaw, own.pitch = 0, 0
		unturn(own)
		return
	end
	local rootCFrame = rig.root.CFrame
	own.yaw, own.pitch = relativeTo(rootCFrame, Shared.viewYaw, Shared.viewPitch)
	local aimRelativeYaw, aimRelativePitch = relativeTo(rootCFrame, aimYaw, aimPitch)
	pose(
		own,
		rig.character,
		rig.root,
		isAiming(rig.character),
		aimRelativeYaw,
		aimRelativePitch,
		Shared.firstPerson,
		ownWeight,
		dt
	)
	afterPose(own, rig.character, player)
end

-- Eases an entry's look toward the latest from Sync on a critically damped
-- spring, so the updates, a few a second, show as one smooth turn. The yaw
-- takes the short way round, as the look crosses behind the body.
local function easeLook(entry: Entry, targetYaw: number, targetPitch: number, dt: number)
	local smoothTime = Shared.config.sync.smoothTime
	if smoothTime <= 0 then
		entry.yaw, entry.pitch = targetYaw, targetPitch
		entry.yawSpeed, entry.pitchSpeed = 0, 0
		return
	end
	-- A critically damped spring at this frequency is about smoothTime late.
	local frequency = 1 / (math.pi * smoothTime)
	local goal = entry.yaw + Math.shortestAngle(targetYaw - entry.yaw)
	local yaw, yawSpeed = Math.spring(entry.yaw, entry.yawSpeed, goal, frequency, 1, dt)
	entry.yaw = Math.shortestAngle(yaw)
	entry.yawSpeed = yawSpeed
	entry.pitch, entry.pitchSpeed =
		Math.spring(entry.pitch, entry.pitchSpeed, targetPitch, frequency, 1, dt)
end

local function isShowing(entry: Entry): boolean
	local state = entry.pose
	return math.abs(entry.yaw) > LOOK_EPSILON
		or math.abs(entry.pitch) > LOOK_EPSILON
		or math.abs(state.waistYaw) > LOOK_EPSILON
		or math.abs(state.waistPitch) > LOOK_EPSILON
end

local function stepOthers(dt: number, on: boolean)
	local camera = workspace.CurrentCamera
	local cameraPosition = if camera then camera.CFrame.Position else nil
	local looks = Sync.getLooks()
	for other, look in looks do
		local entry = others[other]
		if not entry then
			entry = newEntry()
			others[other] = entry
		end
		easeLook(entry, if on then look.yaw else 0, if on then look.pitch else 0, dt)

		local character = other.Character
		if entry.character ~= character then
			forget(entry)
			entry.character = character
		end
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		local root = if humanoid then humanoid.RootPart else nil
		local near = root ~= nil
			and (not cameraPosition or (root.Position - cameraPosition).Magnitude < LOOK_DISTANCE)
		if character and root and near and isShowing(entry) then
			pose(entry, character, root, isAiming(character), entry.yaw, entry.pitch, false, 1, dt)
			afterPose(entry, character, other)
		else
			unturn(entry)
		end
	end
	for other, entry in others do
		if looks[other] == nil then
			forget(entry)
			others[other] = nil
		end
	end
end

local function step(rawDt: number)
	debug.profilebegin("InuFirstPerson.Look")
	local started = os.clock()
	local dt = math.min(rawDt, MAX_DT)
	local settings = Shared.config.look
	local on = enabled and settings.enabled
	poseSettings.neckYawLimit = math.rad(settings.neckYawLimit)
	poseSettings.lookAwayAngle = math.rad(settings.lookAwayAngle)
	poseSettings.headPitchShare = settings.headPitchShare
	poseSettings.waistShare = settings.waistShare
	poseSettings.waistLag = settings.waistLag

	stepOwn(dt, on)
	-- The look as it is, fading with first person; each client shares it out
	-- on its own side, letting the head go the same way.
	Sync.offer(own.yaw * ownWeight, own.pitch * ownWeight, dt)
	stepOthers(dt, on)

	if Shared.measuring then
		Shared.spentTime += os.clock() - started
	end
	debug.profileend()
end

function Look.start()
	running = true
	enabled = true
	ownWeight = 0
	aimViewYaw = nil
	Sync.start()
	connections = {
		RunService.PreSimulation:Connect(step),
		Players.PlayerRemoving:Connect(function(other: Player)
			local entry = others[other]
			if entry then
				forget(entry)
				others[other] = nil
			end
		end),
	}
end

function Look.stop()
	if not running then
		return
	end
	running = false
	for _, connection in connections do
		connection:Disconnect()
	end
	connections = {}
	Sync.sendStraight()
	Sync.stop()
	releaseRoot()
	forget(own)
	own.yaw, own.pitch = 0, 0
	for other, entry in others do
		forget(entry)
		others[other] = nil
	end
	poseCallback = nil
end

-- The local character's neck at rest in its root's space, the pivot of the
-- first-person eye; nil without a neck joined to the root.
function Look.getNeckOffset(rig: Character.Rig): Vector3?
	return jointsFor(own, rig.character, rig.root).neckOffset
end

function Look.setPoseCallback(callback: PoseCallback?)
	poseCallback = callback
end

function Look.setEnabled(on: boolean)
	enabled = on
end

function Look.isEnabled(): boolean
	return enabled
end

-- Where the head of `target` (the local player if nil) turns, in degrees
-- relative to their character's facing, or nil while none is known.
function Look.getAngles(target: Player?): (number?, number?)
	local entry = if target == nil or target == player then own else others[target]
	if not entry then
		return nil, nil
	end
	return math.deg(entry.pose.headYaw), math.deg(entry.pose.headPitch)
end

return Look
