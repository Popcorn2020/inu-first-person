--!strict
-- Layers CameraMotion on top of what the default camera did this frame. The
-- default camera keeps the looking around, zoom and input; this only adds
-- motion. It reads its orientation back from Camera.CFrame, so last frame's
-- layer comes off just before it runs and the new layer goes on just after.
-- Left on, the sway's pitch and yaw would add up frame after frame.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CameraMotion = require(script.Parent.CameraMotion)
local Character = require(script.Parent.Character)
local Shared = require(script.Parent.Shared)

local REVERT_STEP = "InuFirstPersonCameraRevert"
local APPLY_STEP = "InuFirstPersonCameraApply"
local CAMERA_PRIORITY = Enum.RenderPriority.Camera.Value
-- The camera counts as first person while the default camera puts it this
-- close to its focus; zoomed all the way in, it is 0.5 studs.
local FIRST_PERSON_DISTANCE = 1
-- The longest frame the motion is stepped by, so a hitch is not played back
-- as a lurch.
local MAX_DT = 0.1
-- In "start" mode, how long the zoom in may take before it is let go.
local ZOOM_IN_TIMEOUT = 3
-- The field of view reads back as a float; closer than this is unchanged.
local FOV_EPSILON = 1e-3
-- How far below the bottom of the legs the floor is looked for, in studs on a
-- standard avatar.
local FLOOR_PROBE_MARGIN = 1.5
-- Surfaces steeper than this (the Y of their normal) are walls or edges, not
-- floors with a slope to climb.
local FLOOR_MIN_NORMAL_Y = 0.2

local Camera = {}

local player = Players.LocalPlayer
local motion = CameraMotion.new()
local input = CameraMotion.newInput()

local running = false
local enabled = true
local connections: { RBXScriptConnection } = {}
local lastRig: Character.Rig? = nil

-- What the layer put on the camera last frame, taken off before the default
-- camera runs: (camera + height) * layer.
local appliedCamera: Camera? = nil
local appliedLayer = CFrame.identity
local appliedHeight = 0
-- The field of view as the layer left it (read back) and as it was before.
local writtenFov: number? = nil
local fovBefore = 0

local fovOffsets: { [string]: number } = {}
local fovOffsetTotal = 0
local offsets: { [string]: CFrame } = {}
local offsetTotal = CFrame.identity

local savedCameraMode: Enum.CameraMode? = nil
local savedFieldOfView: number? = nil
local savedMaxZoom: number? = nil
local zoomInLeft: number? = nil

local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Exclude
floorParams.RespectCanCollide = true

local function getMotionScale(): number
	local settings = Shared.config.camera
	local scale = settings.motionScale
	if GuiService.ReducedMotionEnabled then
		scale *= settings.reducedMotionScale
	end
	if UserInputService.VREnabled then
		scale *= settings.vrScale
	end
	return scale
end

local function isSubject(camera: Camera, rig: Character.Rig): boolean
	local subject = camera.CameraSubject
	return subject ~= nil
		and (subject == rig.humanoid or subject == rig.root or subject == rig.head)
end

-- Judged on the default camera's own result, before the layer goes on.
local function judgeFirstPerson(camera: Camera?, rig: Character.Rig?): boolean
	if
		not camera
		or not rig
		or camera.CameraType ~= Enum.CameraType.Custom
		or not isSubject(camera, rig)
	then
		return false
	end
	return (camera.CFrame.Position - camera.Focus.Position).Magnitude < FIRST_PERSON_DISTANCE
end

local function revert()
	local camera = appliedCamera
	appliedCamera = nil
	if camera then
		camera.CFrame = camera.CFrame * appliedLayer:Inverse() - Vector3.new(0, appliedHeight, 0)
		local written = writtenFov
		-- Left alone if something else set the field of view since, so a
		-- game's own zoom is kept.
		if written and math.abs(camera.FieldOfView - written) < FOV_EPSILON then
			camera.FieldOfView = fovBefore
		end
	end
	appliedLayer = CFrame.identity
	appliedHeight = 0
	writtenFov = nil
end

local function finishZoomIn()
	local maxZoom = savedMaxZoom
	if maxZoom then
		player.CameraMaxZoomDistance = maxZoom
	end
	savedMaxZoom = nil
	zoomInLeft = nil
end

-- "start" mode zooms in by holding the farthest zoom at the nearest until the
-- camera arrives (or gives up), then gives the player the full range again.
local function stepZoomIn(dt: number, firstPerson: boolean, rig: Character.Rig?)
	local left = zoomInLeft
	if not left or not rig then
		return
	end
	left -= dt
	if firstPerson or left <= 0 then
		finishZoomIn()
	else
		zoomInLeft = left
	end
end

-- How fast the floor under the root carries it up (CameraMotion.Input's
-- floorRiseSpeed). With no floor in reach, the root's own vertical speed.
local function getFloorRiseSpeed(rig: Character.Rig, velocity: Vector3): number
	local root = rig.root
	local legs = math.max(rig.humanoid.HipHeight, root.Size.Y)
	local reach = root.Size.Y / 2 + legs + FLOOR_PROBE_MARGIN * Character.getScale(rig)
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), floorParams)
	if not hit then
		return velocity.Y
	end
	local normal = hit.Normal
	local floorVelocity = hit.Instance:GetVelocityAtPosition(hit.Position)
	if normal.Y < FLOOR_MIN_NORMAL_Y then
		return floorVelocity.Y
	end
	local across = velocity - floorVelocity
	return floorVelocity.Y - (normal.X * across.X + normal.Z * across.Z) / normal.Y
end

local function fillInput(camera: Camera, rig: Character.Rig, firstPerson: boolean)
	local humanoid, root = rig.humanoid, rig.root
	local velocity = root.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local state = humanoid:GetState()
	local climbing = state == Enum.HumanoidStateType.Climbing
	local airborne = state == Enum.HumanoidStateType.Freefall
		or state == Enum.HumanoidStateType.Jumping
	local moveDirection = humanoid.MoveDirection

	local speed = 0
	if climbing then
		speed = math.abs(velocity.Y)
	elseif
		not humanoid.Sit
		and state ~= Enum.HumanoidStateType.Swimming
		and state ~= Enum.HumanoidStateType.Dead
	then
		-- Held to the walking input, so pushing into a wall or riding a moving
		-- floor does not bob.
		speed = math.min(horizontalSpeed, humanoid.WalkSpeed * moveDirection.Magnitude)
	end

	local right = camera.CFrame.RightVector
	local flatRight = Vector3.new(right.X, 0, right.Z)

	input.speed = speed
	input.horizontalSpeed = horizontalSpeed
	input.walkSpeed = Shared.walkingSpeed
	input.runSpeed = Shared.runningSpeed
	input.strafe = if flatRight.Magnitude > 1e-3 then moveDirection:Dot(flatRight.Unit) else 0
	input.grounded = not airborne and not climbing and humanoid.FloorMaterial ~= Enum.Material.Air
	input.climbing = climbing
	input.airborne = airborne
	input.verticalSpeed = velocity.Y
	input.height = root.Position.Y
	input.floorRiseSpeed = getFloorRiseSpeed(rig, velocity)
	input.gravity = workspace.Gravity
	input.fatigue = Shared.fatigue
	input.motionScale = getMotionScale()
	input.firstPerson = firstPerson
end

local function apply(rawDt: number)
	debug.profilebegin("InuFirstPerson.Camera")
	local started = os.clock()
	local dt = math.min(rawDt, MAX_DT)
	local camera = workspace.CurrentCamera
	local rig = Character.get()
	if rig ~= lastRig then
		lastRig = rig
		CameraMotion.reset(motion)
		floorParams.FilterDescendantsInstances = if rig then { rig.character } else {}
	end

	local firstPerson = judgeFirstPerson(camera, rig)
	if firstPerson ~= Shared.firstPerson then
		Shared.firstPerson = firstPerson
		Shared.signals.firstPersonChanged:Fire(firstPerson)
	end
	stepZoomIn(dt, firstPerson, rig)

	Shared.bodyHeight = 0
	if
		enabled
		and camera
		and rig
		and camera.CameraType == Enum.CameraType.Custom
		and isSubject(camera, rig)
	then
		fillInput(camera, rig, firstPerson)
		CameraMotion.step(motion, Shared.config, input, dt)

		local rotation = motion.localRotation
		local layer = offsetTotal
			* CFrame.new(motion.localPosition)
			* CFrame.fromEulerAnglesYXZ(rotation.X, rotation.Y, rotation.Z)
		camera.CFrame = (camera.CFrame + Vector3.new(0, motion.worldHeight, 0)) * layer
		appliedCamera = camera
		appliedLayer = layer
		appliedHeight = motion.worldHeight
		Shared.bodyHeight = motion.bodyHeight

		local fovOffset = motion.fovOffset + fovOffsetTotal
		if fovOffset ~= 0 then
			fovBefore = camera.FieldOfView
			camera.FieldOfView = fovBefore + fovOffset
			writtenFov = camera.FieldOfView
		end
	end

	if Shared.measuring then
		Shared.spentTime += os.clock() - started
	end
	debug.profileend()
end

local function setUpFieldOfView()
	local fieldOfView = Shared.config.camera.fieldOfView
	local camera = workspace.CurrentCamera
	if camera and fieldOfView > 0 then
		camera.FieldOfView = fieldOfView
	end
end

function Camera.start()
	running = true
	enabled = true
	lastRig = nil
	CameraMotion.reset(motion)

	local mode = Shared.config.camera.firstPerson
	if mode == "lock" then
		savedCameraMode = player.CameraMode
		player.CameraMode = Enum.CameraMode.LockFirstPerson
	elseif mode == "start" then
		savedMaxZoom = player.CameraMaxZoomDistance
		player.CameraMaxZoomDistance = player.CameraMinZoomDistance
		zoomInLeft = ZOOM_IN_TIMEOUT
	end

	local camera = workspace.CurrentCamera
	savedFieldOfView = if camera then camera.FieldOfView else nil
	setUpFieldOfView()
	table.insert(
		connections,
		workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(setUpFieldOfView)
	)

	RunService:BindToRenderStep(REVERT_STEP, CAMERA_PRIORITY - 1, revert)
	RunService:BindToRenderStep(APPLY_STEP, CAMERA_PRIORITY + 1, apply)
end

function Camera.stop()
	if not running then
		return
	end
	running = false
	RunService:UnbindFromRenderStep(REVERT_STEP)
	RunService:UnbindFromRenderStep(APPLY_STEP)
	revert()
	for _, connection in connections do
		connection:Disconnect()
	end
	connections = {}

	finishZoomIn()
	local mode = savedCameraMode
	if mode then
		player.CameraMode = mode
	end
	savedCameraMode = nil
	local camera = workspace.CurrentCamera
	local fieldOfView = savedFieldOfView
	if camera and fieldOfView and Shared.config.camera.fieldOfView > 0 then
		camera.FieldOfView = fieldOfView
	end
	savedFieldOfView = nil

	table.clear(fovOffsets)
	fovOffsetTotal = 0
	table.clear(offsets)
	offsetTotal = CFrame.identity
	if Shared.firstPerson then
		Shared.firstPerson = false
		Shared.signals.firstPersonChanged:Fire(false)
	end
	Shared.bodyHeight = 0
end

function Camera.setEnabled(on: boolean)
	enabled = on
end

function Camera.isEnabled(): boolean
	return enabled
end

function Camera.kick(rotationDegrees: Vector3, position: Vector3?)
	CameraMotion.kick(motion, Shared.config, rotationDegrees, position or Vector3.zero)
end

function Camera.setFovOffset(key: string, degrees: number?)
	if degrees then
		fovOffsets[key] = degrees
	else
		fovOffsets[key] = nil
	end
	local total = 0
	for _, value in fovOffsets do
		total += value
	end
	fovOffsetTotal = total
end

function Camera.setOffset(key: string, offset: CFrame?)
	if offset then
		offsets[key] = offset
	else
		offsets[key] = nil
	end
	-- Multiplied in the order of their keys: CFrames do not commute, and a
	-- table's own order is not fixed.
	local keys = {}
	for name in offsets do
		table.insert(keys, name)
	end
	table.sort(keys)
	local total = CFrame.identity
	for _, name in keys do
		total *= offsets[name]
	end
	offsetTotal = total
end

-- The layer put on the camera this frame, in the camera's own space (the
-- world-up part, step smoothing and the landing dip, is not in it).
function Camera.getLayer(): CFrame
	return appliedLayer
end

return Camera
