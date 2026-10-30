--!strict
-- Lets the player see their own body when looking down. First person hides
-- the real character, so a copy of its visible parts is kept on this client,
-- under the camera, and each frame every copied part takes its source's pose
-- relative to the root. That works for any joints (Motor6D or
-- AnimationConstraint) and any rig of separate parts, R6 and R15 alike; a
-- single skinned mesh driven by bones would not follow.
--
-- The copy faces where the camera faces (a moment late on fast turns) and
-- sits a little behind the real character, so the camera is not inside its
-- chest. In third person it stops and hides, since the real character shows.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Character = require(script.Parent.Character)
local Math = require(script.Parent.Math)
local Shared = require(script.Parent.Shared)
local TurnLag = require(script.Parent.TurnLag)

local STEP_NAME = "InuFirstPersonBody"
-- After the camera's layer, so the body follows the final camera.
local STEP_PRIORITY = Enum.RenderPriority.Camera.Value + 5
local COPY_NAME = "InuFirstPersonBody"
local MAX_DT = 0.1
-- How long the body takes to swing between facing the camera and facing the
-- root (sitting down, grabbing a ladder).
local FACING_SWITCH_TIME = 0.12

-- Humanoid states in which the character turns with the camera. In the others
-- (seated, climbing, swimming, ragdolled) the body faces its root.
local CAMERA_FACING_STATES: { [Enum.HumanoidStateType]: true } = {
	[Enum.HumanoidStateType.Running] = true,
	[Enum.HumanoidStateType.RunningNoPhysics] = true,
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.Landed] = true,
}
-- The arm a Tool is held in, for R15 and R6.
local TOOL_ARM_PARTS: { [string]: true } = {
	RightUpperArm = true,
	RightLowerArm = true,
	RightHand = true,
	["Right Arm"] = true,
}
local HEADWEAR: { [Enum.AccessoryType]: true } = {
	[Enum.AccessoryType.Hat] = true,
	[Enum.AccessoryType.Hair] = true,
	[Enum.AccessoryType.Face] = true,
	[Enum.AccessoryType.Eyebrow] = true,
	[Enum.AccessoryType.Eyelash] = true,
}

type Pair = {
	source: BasePart,
	copy: BasePart,
	-- Drawn where the real part is while a Tool is held.
	toolArm: boolean,
	hidden: boolean,
}

export type PoseCallback = (model: Model, placed: CFrame) -> ()

local Body = {}

local running = false
local enabled = true
local poseCallback: PoseCallback? = nil

local sourceCharacter: Model? = nil
local watchConnections: { RBXScriptConnection } = {}
-- The copy is rebuilt once the source has been quiet for rebuildDelay.
local dirty = true
local quietTime = 0

local copy: Model? = nil
local pairList: { Pair } = {}
local copyParts: { BasePart } = {}
local targetCFrames: { CFrame } = {}
local shown = false
local turn = TurnLag.new()
local facingCamera = 1

local function isVisual(descendant: Instance): boolean
	if descendant:IsA("Tool") or descendant:FindFirstAncestorOfClass("Tool") then
		return false
	end
	return descendant:IsA("BasePart")
		or descendant:IsA("Accessory")
		or descendant:IsA("Clothing")
		or descendant:IsA("ShirtGraphic")
		or descendant:IsA("BodyColors")
		or descendant:IsA("CharacterMesh")
		or descendant:IsA("DataModelMesh")
		or descendant:IsA("Decal")
		or descendant:IsA("SurfaceAppearance")
		or descendant:IsA("BaseWrap")
end

local function markDirty()
	dirty = true
	quietTime = 0
end

local function unwatch()
	for _, connection in watchConnections do
		connection:Disconnect()
	end
	watchConnections = {}
	sourceCharacter = nil
end

local function watch(character: Model)
	unwatch()
	sourceCharacter = character
	local function changed(descendant: Instance)
		if isVisual(descendant) then
			markDirty()
		end
	end
	watchConnections = {
		character.DescendantAdded:Connect(changed),
		character.DescendantRemoving:Connect(changed),
	}
	markDirty()
end

local function destroyCopy()
	if copy then
		copy:Destroy()
	end
	copy = nil
	pairList = {}
	copyParts = {}
	targetCFrames = {}
	shown = false
end

local function setShown(visible: boolean)
	if shown == visible then
		return
	end
	shown = visible
	if not visible then
		TurnLag.reset(turn)
	end
	for _, pair in pairList do
		pair.copy.LocalTransparencyModifier = if visible and not pair.hidden then 0 else 1
	end
end

-- Clones even what is marked not Archivable, leaving the source as it was.
-- Descendants marked not Archivable are left out, as Clone does.
local function cloneOf(instance: Instance): Instance
	local wasArchivable = instance.Archivable
	instance.Archivable = true
	local clone = instance:Clone()
	instance.Archivable = wasArchivable
	return clone
end

-- Strips a cloned descendant of what would act like a second character or
-- fight the per-frame pose. The source is never touched.
local function sanitize(descendant: Instance)
	-- Tags left on the copy would make tag-driven code treat it as the real one.
	for _, tag in CollectionService:GetTags(descendant) do
		CollectionService:RemoveTag(descendant, tag)
	end
	if
		descendant:IsA("BaseScript")
		or descendant:IsA("Sound")
		or descendant:IsA("Animator")
		or descendant:IsA("JointInstance")
		or descendant:IsA("Constraint")
		or descendant:IsA("WeldConstraint")
		or descendant:IsA("NoCollisionConstraint")
		or descendant:IsA("Light")
		or descendant:IsA("ParticleEmitter")
		or descendant:IsA("Trail")
		or descendant:IsA("Beam")
		or descendant:IsA("Fire")
		or descendant:IsA("Smoke")
		or descendant:IsA("Sparkles")
		or descendant:IsA("Highlight")
		or descendant:IsA("LayerCollector")
		or descendant:IsA("ProximityPrompt")
		or descendant:IsA("ClickDetector")
	then
		-- Every part is anchored and placed each frame, so no joint is needed.
		-- Effects, lights and labels carried on the character are not doubled.
		descendant:Destroy()
	elseif descendant:IsA("BasePart") then
		descendant.Anchored = true
		descendant.CanCollide = false
		descendant.CanTouch = false
		descendant.CanQuery = false
		descendant.CastShadow = false
		descendant.Massless = true
		descendant.LocalTransparencyModifier = 1
	end
end

local function sanitizeTree(root: Instance)
	sanitize(root)
	for _, descendant in root:GetDescendants() do
		if descendant.Parent then
			sanitize(descendant)
		end
	end
end

-- The body part an accessory's handle is welded to.
local function findWeldedPart(handle: BasePart, character: Model): BasePart?
	for _, child in handle:GetChildren() do
		if
			child:IsA("JointInstance")
			or child:IsA("WeldConstraint")
			or child:IsA("RigidConstraint")
		then
			for _, key in { "Part0", "Part1" } do
				local other = (child :: any)[key]
				if
					typeof(other) == "Instance"
					and other:IsA("BasePart")
					and other ~= handle
					and other.Parent == character
				then
					return other
				end
			end
		end
	end
	return nil
end

local function isHeadwear(accessory: Accessory, handle: BasePart, character: Model): boolean
	if HEADWEAR[accessory.AccessoryType] then
		return true
	end
	local welded = findWeldedPart(handle, character)
	return welded ~= nil and welded.Name == "Head"
end

-- Copies the character's visible parts one by one, so each copy is paired
-- with its source exactly, whatever the names.
local function build(rig: Character.Rig, camera: Camera)
	destroyCopy()
	dirty = false
	local character = rig.character
	local model = Instance.new("Model")
	model.Name = COPY_NAME
	local built: { Pair } = {}

	for _, child in character:GetChildren() do
		if child:IsA("BasePart") then
			-- The root is invisible, and without it the copy's Humanoid has no
			-- root to run its collision rules from.
			if child ~= rig.root then
				local part = cloneOf(child) :: BasePart
				sanitizeTree(part)
				-- The camera sits inside the head.
				local isHead = child.Name == "Head"
				if isHead then
					part.Transparency = 1
					for _, decal in part:GetDescendants() do
						if decal:IsA("Decal") then
							decal.Transparency = 1
						end
					end
				end
				part.Parent = model
				table.insert(built, {
					source = child,
					copy = part,
					toolArm = TOOL_ARM_PARTS[child.Name] == true,
					hidden = isHead,
				})
			end
		elseif child:IsA("Accessory") then
			local handle = child:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") and not isHeadwear(child, handle, character) then
				local welded = findWeldedPart(handle, character)
				local accessory = cloneOf(child)
				local copiedHandle = accessory:FindFirstChild("Handle")
				if copiedHandle and copiedHandle:IsA("BasePart") then
					sanitizeTree(accessory)
					accessory.Parent = model
					table.insert(built, {
						source = handle,
						copy = copiedHandle,
						toolArm = welded ~= nil and TOOL_ARM_PARTS[welded.Name] == true,
						hidden = false,
					})
				else
					accessory:Destroy()
				end
			end
		elseif
			child:IsA("Humanoid")
			or child:IsA("Clothing")
			or child:IsA("ShirtGraphic")
			or child:IsA("BodyColors")
			or child:IsA("CharacterMesh")
		then
			-- Classic clothing and body colors render through a Humanoid.
			local clone = cloneOf(child)
			sanitizeTree(clone)
			if clone:IsA("Humanoid") then
				clone.EvaluateStateMachine = false
				clone.AutomaticScalingEnabled = false
				clone.RequiresNeck = false
				clone.BreakJointsOnDeath = false
				clone.PlatformStand = true
				clone.AutoRotate = false
				clone.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				clone.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			end
			clone.Parent = model
		end
	end

	model.Parent = camera
	-- A Humanoid can switch collisions back on as it takes its parts in.
	for _, pair in built do
		pair.copy.CanCollide = false
	end

	copy = model
	pairList = built
	for index, pair in built do
		copyParts[index] = pair.copy
		targetCFrames[index] = pair.copy.CFrame
	end
	shown = false
	TurnLag.reset(turn)
end

local function cameraFacing(rig: Character.Rig): boolean
	local humanoid = rig.humanoid
	return humanoid.AutoRotate
		and not humanoid.Sit
		and not humanoid.PlatformStand
		and CAMERA_FACING_STATES[humanoid:GetState()] == true
end

local function pose(rig: Character.Rig, camera: Camera, dt: number)
	local settings = Shared.config.body
	local root = rig.root
	local _, cameraYaw = camera.CFrame:ToEulerAnglesYXZ()
	local yaw = TurnLag.step(turn, cameraYaw, settings.turnLag, math.rad(settings.maxTurnLag), dt)
	facingCamera =
		Math.approach(facingCamera, if cameraFacing(rig) then 1 else 0, FACING_SWITCH_TIME, dt)
	local rotation = root.CFrame.Rotation:Lerp(CFrame.Angles(0, yaw, 0), facingCamera)
	local placed = CFrame.new(root.Position + Vector3.new(0, Shared.bodyHeight, 0))
		* rotation
		* CFrame.new(settings.offset * Character.getScale(rig))

	local holdingTool = settings.toolArm and rig.character:FindFirstChildOfClass("Tool") ~= nil
	local rootInverse = root.CFrame:Inverse()
	for index, pair in pairList do
		local source = pair.source
		if source.Parent then
			local sourceCFrame = source.CFrame
			targetCFrames[index] = if holdingTool and pair.toolArm
				then sourceCFrame
				else placed * (rootInverse * sourceCFrame)
		end
	end
	workspace:BulkMoveTo(copyParts, targetCFrames, Enum.BulkMoveMode.FireCFrameChanged)

	local callback = poseCallback
	local model = copy
	if callback and model then
		callback(model, placed)
	end
end

local function step(rawDt: number)
	debug.profilebegin("InuFirstPerson.Body")
	local started = os.clock()
	local dt = math.min(rawDt, MAX_DT)
	local rig = Character.get()
	local camera = workspace.CurrentCamera

	if not rig or not camera then
		unwatch()
		destroyCopy()
	else
		if rig.character ~= sourceCharacter then
			watch(rig.character)
			destroyCopy()
		end
		quietTime += dt

		local wanted = enabled
			and Shared.config.body.enabled
			and Shared.firstPerson
			and not UserInputService.VREnabled
			and rig.humanoid.Health > 0
		if not wanted then
			setShown(false)
		else
			if dirty and quietTime >= Shared.config.body.rebuildDelay then
				build(rig, camera)
			end
			local model = copy
			if model and model.Parent == nil then
				-- Destroyed from outside, as with the camera it was under.
				destroyCopy()
				markDirty()
			elseif model then
				if model.Parent ~= camera then
					model.Parent = camera
				end
				pose(rig, camera, dt)
				setShown(true)
			end
		end
	end

	if Shared.measuring then
		Shared.spentTime += os.clock() - started
	end
	debug.profileend()
end

function Body.start()
	running = true
	enabled = true
	RunService:BindToRenderStep(STEP_NAME, STEP_PRIORITY, step)
end

function Body.stop()
	if not running then
		return
	end
	running = false
	RunService:UnbindFromRenderStep(STEP_NAME)
	unwatch()
	destroyCopy()
	poseCallback = nil
end

function Body.setEnabled(on: boolean)
	enabled = on
end

function Body.isEnabled(): boolean
	return enabled
end

-- The copy, or nil until it is built (and while there is no character).
function Body.getModel(): Model?
	return copy
end

-- Rebuilds the copy once the character has been quiet for rebuildDelay, for
-- changes it cannot see (a recolored part, a resized avatar).
function Body.rebuild()
	markDirty()
end

function Body.setPoseCallback(callback: PoseCallback?)
	poseCallback = callback
end

return Body
