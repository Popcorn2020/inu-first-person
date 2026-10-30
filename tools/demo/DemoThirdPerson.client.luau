--!strict
-- The third-person view: a copy of the local character's look, Tool
-- included, in the ViewportFrame's WorldModel. Each frame the copy's parts
-- take the real parts' CFrames, so the pose the module gives the neck, the
-- torso and the arms shows as others see it. The view's camera looks from a
-- fixed direction in the world and follows the root.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- The demo place is built by tools/build-demo.luau, so its Instances are not
-- on disk for the type checker; each is narrowed where it is taken.
local gui = script.Parent :: ScreenGui
local form = require(gui:FindFirstChild("DemoForm") :: ModuleScript)
local view = (gui:FindFirstChild("ViewSlot") :: Frame):FindFirstChild(
		"ThirdPerson"
	) :: ViewportFrame
local world = view:FindFirstChild("World") :: WorldModel
-- Made here: a Camera put in StarterGui does not replicate, so it never
-- reaches the PlayerGui copy.
local viewCamera = Instance.new("Camera")
viewCamera.Name = "Camera"
viewCamera.FieldOfView = 40
viewCamera.Parent = view

local STEP_NAME = "InuFirstPersonDemoThirdPerson"
-- In front of the spawn's facing (-Z), to the right and above.
local CAMERA_OFFSET = Vector3.new(5, 3.5, -10)
-- The root sits a little above the middle of the body.
local FOCUS_DROP = 0.4
-- An avatar loads part by part; the copy is made once the changes stop.
local REBUILD_QUIET = 0.1

local player = Players.LocalPlayer
local character: Model? = nil
local root: BasePart? = nil
local copy: Model? = nil
local sourceParts: { BasePart } = {}
local copyParts: { BasePart } = {}
local targetCFrames: { CFrame } = {}
local watchConnections: { RBXScriptConnection } = {}
local changedAt: number? = nil

local function isVisual(descendant: Instance): boolean
	return descendant:IsA("BasePart")
		or descendant:IsA("Accessory")
		or descendant:IsA("Tool")
		or descendant:IsA("Clothing")
		or descendant:IsA("ShirtGraphic")
		or descendant:IsA("BodyColors")
		or descendant:IsA("CharacterMesh")
		or descendant:IsA("DataModelMesh")
		or descendant:IsA("Decal")
		or descendant:IsA("SurfaceAppearance")
		or descendant:IsA("BaseWrap")
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

-- Pairs each BasePart under `source` with its counterpart under `clone` by
-- walking both trees together: Clone keeps the order of children and leaves
-- out the ones marked not Archivable.
local function pairTree(source: Instance, clone: Instance)
	local cloneChildren = clone:GetChildren()
	local index = 0
	for _, child in source:GetChildren() do
		if child.Archivable then
			index += 1
			local counterpart = cloneChildren[index]
			if child:IsA("BasePart") and counterpart and counterpart:IsA("BasePart") then
				table.insert(sourceParts, child)
				table.insert(copyParts, counterpart)
			end
			if counterpart then
				pairTree(child, counterpart)
			end
		end
	end
end

-- Strips a cloned descendant of what would act like a second character or
-- fight the per-frame pose.
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
		descendant:Destroy()
	elseif descendant:IsA("BasePart") then
		descendant.Anchored = true
		descendant.CanCollide = false
		descendant.CanTouch = false
		descendant.CanQuery = false
		descendant.Massless = true
		-- The real parts are hidden in first person; the copy is seen from outside.
		descendant.LocalTransparencyModifier = 0
	elseif descendant:IsA("Decal") then
		descendant.LocalTransparencyModifier = 0
	end
end

local function destroyCopy()
	if copy then
		copy:Destroy()
	end
	copy = nil
	root = nil
	sourceParts = {}
	copyParts = {}
	targetCFrames = {}
end

local function build()
	changedAt = nil
	destroyCopy()
	local current = character
	if not current then
		return
	end
	local currentRoot = current:FindFirstChild("HumanoidRootPart")
	if not (currentRoot and currentRoot:IsA("BasePart")) then
		return
	end
	local model = Instance.new("Model")
	model.Name = "ThirdPersonCopy"
	for _, child in current:GetChildren() do
		if
			(child:IsA("BasePart") and child ~= currentRoot)
			or child:IsA("Accessory")
			or child:IsA("Tool")
		then
			local clone = cloneOf(child)
			if child:IsA("BasePart") and clone:IsA("BasePart") then
				table.insert(sourceParts, child)
				table.insert(copyParts, clone)
			end
			pairTree(child, clone)
			if clone:IsA("Tool") then
				-- Only the look: a Tool beside a Humanoid counts as held by it.
				local holder = Instance.new("Model")
				holder.Name = clone.Name
				for _, toolChild in clone:GetChildren() do
					toolChild.Parent = holder
				end
				clone:Destroy()
				holder.Parent = model
			else
				clone.Parent = model
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
	for _, descendant in model:GetDescendants() do
		if descendant.Parent then
			sanitize(descendant)
		end
	end
	-- A pair whose copy went with a stripped ancestor has nothing to move.
	for index = #copyParts, 1, -1 do
		if not copyParts[index]:IsDescendantOf(model) then
			table.remove(copyParts, index)
			table.remove(sourceParts, index)
		end
	end
	model.Parent = world
	-- A Humanoid can switch collisions back on as it takes its parts in.
	for _, part in copyParts do
		part.CanCollide = false
	end
	copy = model
	root = currentRoot
end

local function watch(newCharacter: Model?)
	for _, connection in watchConnections do
		connection:Disconnect()
	end
	watchConnections = {}
	character = newCharacter
	changedAt = os.clock()
	if not newCharacter then
		return
	end
	local function changed(descendant: Instance)
		if isVisual(descendant) then
			changedAt = os.clock()
		end
	end
	watchConnections = {
		newCharacter.DescendantAdded:Connect(changed),
		newCharacter.DescendantRemoving:Connect(changed),
	}
end

view.CurrentCamera = viewCamera
if form.touch then
	view.Parent = gui:FindFirstChild("TouchSlot") :: Frame
end

player.CharacterAdded:Connect(watch)
player.CharacterRemoving:Connect(function(old: Model)
	if old == character then
		watch(nil)
	end
end)
watch(player.Character)

-- Last, after the animation, the default camera and the module's pose.
RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Last.Value, function()
	local since = changedAt
	if since and os.clock() - since >= REBUILD_QUIET then
		build()
	end
	local currentRoot = root
	if not currentRoot then
		return
	end
	for index, part in sourceParts do
		targetCFrames[index] = part.CFrame
	end
	world:BulkMoveTo(copyParts, targetCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	local focus = currentRoot.Position - Vector3.new(0, FOCUS_DROP, 0)
	viewCamera.CFrame = CFrame.lookAt(focus + CAMERA_OFFSET, focus)
end)
