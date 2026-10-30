--!strict
-- The local player's character as the parts need it: the Humanoid, the root
-- and the head, looked up once per character and checked cheaply each frame.

local Players = game:GetService("Players")

export type Rig = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	-- nil for a character without a part named Head.
	head: BasePart?,
}

local Character = {}

local player = Players.LocalPlayer
local cached: Rig? = nil

-- The current character, or nil while there is none or it is missing its
-- Humanoid or root (between respawns, or a character a game builds by hand).
function Character.get(): Rig?
	local character = player.Character
	if not character or not character.Parent then
		cached = nil
		return nil
	end

	local rig = cached
	if
		rig
		and rig.character == character
		and rig.humanoid.Parent == character
		and rig.root.Parent == character
		and rig.humanoid.RootPart == rig.root
	then
		return rig
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not humanoid or not root then
		cached = nil
		return nil
	end
	local head = character:FindFirstChild("Head")
	local found: Rig = {
		character = character,
		humanoid = humanoid,
		root = root,
		head = if head and head:IsA("BasePart") then head else nil,
	}
	cached = found
	return found
end

-- How much bigger than a standard avatar the character is, from its root (2
-- studs tall on a standard R6 or R15 avatar).
function Character.getScale(rig: Rig): number
	return rig.root.Size.Y / 2
end

return Character
