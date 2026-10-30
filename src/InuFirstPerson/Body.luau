--!strict
-- Lets the player see their own body in first person. Zoomed in, the default
-- camera hides the character (LocalTransparencyModifier 1 on every part);
-- right after it, this shows everything again but the head and what is worn
-- on it. The body is the real one, so sitting, climbing, a held Tool, emotes
-- and vehicles show as they are, and its whole shadow falls. The camera sits
-- in front of the neck (Camera), which keeps it out of the chest.
--
-- Run from Camera's step, after the default camera, every frame: the
-- default camera writes the parts only when its own fade changes, and a
-- part streamed out and back in loses what this wrote.

local UserInputService = game:GetService("UserInputService")

local Character = require(script.Parent.Character)
local Shared = require(script.Parent.Shared)

-- Worn on the head, and hidden with it.
local HEADWEAR: { [Enum.AccessoryType]: true } = {
	[Enum.AccessoryType.Hat] = true,
	[Enum.AccessoryType.Hair] = true,
	[Enum.AccessoryType.Face] = true,
	[Enum.AccessoryType.Eyebrow] = true,
	[Enum.AccessoryType.Eyelash] = true,
}

local Body = {}

local running = false
local enabled = true

local watched: Model? = nil
local watchConnections: { RBXScriptConnection } = {}
local dirty = true
-- The parts and their decals to show (the default camera hides both), and
-- whether this has shown them since the default camera last hid them.
local parts: { BasePart } = {}
local decals: { Decal } = {}
local shown = false

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

-- The default camera leaves a held Tool alone, and so does this.
local function collect(rig: Character.Rig): ({ BasePart }, { Decal })
	local character = rig.character
	local found: { BasePart } = {}
	for _, child in character:GetChildren() do
		if child:IsA("BasePart") then
			if child.Name ~= "Head" then
				table.insert(found, child)
			end
		elseif child:IsA("Accessory") then
			local handle = child:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") and not isHeadwear(child, handle, character) then
				for _, descendant in child:GetDescendants() do
					if descendant:IsA("BasePart") then
						table.insert(found, descendant)
					end
				end
			end
		end
	end
	local foundDecals: { Decal } = {}
	for _, part in found do
		for _, child in part:GetChildren() do
			if child:IsA("Decal") then
				table.insert(foundDecals, child)
			end
		end
	end
	return found, foundDecals
end

local function unwatch()
	for _, connection in watchConnections do
		connection:Disconnect()
	end
	watchConnections = {}
	watched = nil
	parts = {}
	decals = {}
	shown = false
end

local function watch(character: Model)
	unwatch()
	watched = character
	dirty = true
	local function changed(descendant: Instance)
		if descendant:IsA("BasePart") or descendant:IsA("Accessory") or descendant:IsA("Decal") then
			dirty = true
		end
	end
	watchConnections = {
		character.DescendantAdded:Connect(changed),
		character.DescendantRemoving:Connect(changed),
	}
end

-- Puts back what the default camera shows in first person.
local function hide()
	if not shown then
		return
	end
	shown = false
	for _, part in parts do
		part.LocalTransparencyModifier = 1
	end
	for _, decal in decals do
		decal.LocalTransparencyModifier = 1
	end
end

-- Each frame from Camera, after the default camera.
function Body.step(rig: Character.Rig?)
	if not running then
		return
	end
	if not rig then
		unwatch()
		return
	end
	if rig.character ~= watched then
		watch(rig.character)
	end
	local wanted = enabled
		and Shared.config.body.enabled
		and Shared.firstPerson
		and not UserInputService.VREnabled
		and rig.humanoid.Health > 0
	if not wanted then
		-- In third person the default camera has already shown the body.
		if Shared.firstPerson then
			hide()
		end
		shown = false
		return
	end
	if dirty then
		dirty = false
		parts, decals = collect(rig)
	end
	for _, part in parts do
		if part.LocalTransparencyModifier ~= 0 then
			part.LocalTransparencyModifier = 0
		end
	end
	for _, decal in decals do
		if decal.LocalTransparencyModifier ~= 0 then
			decal.LocalTransparencyModifier = 0
		end
	end
	shown = true
end

function Body.start()
	running = true
	enabled = true
end

function Body.stop()
	if not running then
		return
	end
	running = false
	if Shared.firstPerson then
		hide()
	end
	unwatch()
end

function Body.setEnabled(on: boolean)
	enabled = on
end

function Body.isEnabled(): boolean
	return enabled
end

return Body
