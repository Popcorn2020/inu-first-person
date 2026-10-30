--!strict
-- The joints the look turns on a character: the neck, the waist (R15 only)
-- and the right shoulder, found by name on R15 and R6, as Motor6D or, with
-- StarterPlayer.AvatarJointUpgrade, AnimationConstraint. Also where the neck
-- sits at rest from the root: the pivot the first-person eye turns on, which
-- animations do not move, so the view does not shake with the head.
--
-- A turn goes on the joint's Transform, which the Animator writes each frame
-- before physics, so it lands on top of the animation. Where the Animator has
-- not written it since the last turn (no track on the joint, or evaluation
-- throttled), the turn goes on the Transform from before that turn instead,
-- so turns never pile up.

-- Joints by name, with the part each one moves.
local JOINT_CHILDREN: { [string]: string } = {
	Neck = "Head",
	Waist = "UpperTorso",
	RightShoulder = "RightUpperArm",
	["Right Shoulder"] = "Right Arm",
}
local SHOULDERS: { [string]: true } = {
	RightShoulder = true,
	["Right Shoulder"] = true,
}
-- The longest chain of joints from the root to the neck looked through.
local MAX_CHAIN = 8
-- A Transform this close to the one written is taken as not rewritten.
local REWRITE_EPSILON = 1e-4
-- How often joints still missing (a character still loading) are looked for.
local RETRY_PERIOD = 1

export type Joint = {
	instance: Motor6D | AnimationConstraint,
	-- The Transform as the animation left it, and as the turn last wrote it.
	base: CFrame,
	written: CFrame?,
}

export type Set = {
	character: Model,
	root: BasePart,
	neck: Joint?,
	waist: Joint?,
	shoulder: Joint?,
	-- The neck joint at rest in the root's space; nil without a neck joined
	-- to the root.
	neckOffset: Vector3?,
	-- The root's size when the joints were found, as rescaling moves them.
	rootSize: Vector3,
	-- os.clock() after which missing joints are looked for again.
	retryAt: number,
}

local Joints = {}

-- The parts a joint joins and its two frames (C0 on the first part, C1 on
-- the second), or nil while an attachment is missing.
local function getEnds(
	instance: Motor6D | AnimationConstraint
): (Instance?, Instance?, CFrame?, CFrame?)
	if instance:IsA("Motor6D") then
		return instance.Part0, instance.Part1, instance.C0, instance.C1
	end
	local constraint = instance :: AnimationConstraint
	local attachment0, attachment1 = constraint.Attachment0, constraint.Attachment1
	if not attachment0 or not attachment1 then
		return nil, nil, nil, nil
	end
	return attachment0.Parent, attachment1.Parent, attachment0.CFrame, attachment1.CFrame
end

-- Property writes do not type-check on a union of classes.
local function setTransform(instance: Motor6D | AnimationConstraint, transform: CFrame)
	if instance:IsA("Motor6D") then
		instance.Transform = transform
	else
		(instance :: AnimationConstraint).Transform = transform
	end
end

local function newJoint(instance: Motor6D | AnimationConstraint): Joint
	return { instance = instance, base = instance.Transform }
end

-- The pose of `part` at rest in the root's space, following the joints up to
-- the root, or nil if they do not reach it.
local function restFromRoot(
	part: Instance?,
	root: BasePart,
	byChild: { [Instance]: Motor6D | AnimationConstraint }
): CFrame?
	local offset = CFrame.identity
	local current = part
	for _ = 1, MAX_CHAIN do
		if current == nil then
			return nil
		elseif current == root then
			return offset
		end
		local joint = byChild[current]
		if not joint then
			return nil
		end
		local part0, _, c0, c1 = getEnds(joint)
		if not c0 or not c1 then
			return nil
		end
		offset = c0 * c1:Inverse() * offset
		current = part0
	end
	return nil
end

function Joints.find(character: Model, root: BasePart): Set
	local set: Set = {
		character = character,
		root = root,
		rootSize = root.Size,
		retryAt = os.clock() + RETRY_PERIOD,
	}
	-- Every joint by the part it moves, for walking from the neck to the root.
	-- Only for this call, so no Instance outlives it here.
	local byChild: { [Instance]: Motor6D | AnimationConstraint } = {}
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Motor6D") or descendant:IsA("AnimationConstraint") then
			local instance = descendant :: Motor6D | AnimationConstraint
			local _, part1 = getEnds(instance)
			if part1 then
				byChild[part1] = instance
				local childName = JOINT_CHILDREN[instance.Name]
				if childName and part1.Name == childName then
					if instance.Name == "Neck" then
						set.neck = newJoint(instance)
					elseif instance.Name == "Waist" then
						set.waist = newJoint(instance)
					elseif SHOULDERS[instance.Name] then
						set.shoulder = newJoint(instance)
					end
				end
			end
		end
	end
	local neck = set.neck
	if neck then
		local part0, _, c0 = getEnds(neck.instance)
		local torso = restFromRoot(part0, root, byChild)
		if torso and c0 then
			set.neckOffset = (torso * c0).Position
		end
	end
	return set
end

-- Whether a set found earlier still fits the character: the same root at
-- the same size, its joints still in place, and none missing that should
-- be looked for again.
function Joints.isCurrent(set: Set, root: BasePart): boolean
	if set.root ~= root or root.Size ~= set.rootSize then
		return false
	end
	local neck, waist, shoulder = set.neck, set.waist, set.shoulder
	if
		(neck and neck.instance.Parent == nil)
		or (waist and waist.instance.Parent == nil)
		or (shoulder and shoulder.instance.Parent == nil)
	then
		return false
	end
	return (neck ~= nil and shoulder ~= nil) or os.clock() < set.retryAt
end

-- Turns the joint by `yaw` (left) and then `pitch` (up), in radians, about
-- the axes of the part it hangs from, on top of the animation.
function Joints.turn(joint: Joint, yaw: number, pitch: number)
	if yaw == 0 and pitch == 0 then
		Joints.release(joint)
		return
	end
	local instance = joint.instance
	local _, _, c0 = getEnds(instance)
	if not c0 then
		return
	end
	local current = instance.Transform
	local written = joint.written
	local base = if written and current:FuzzyEq(written, REWRITE_EPSILON)
		then joint.base
		else current
	local frame = c0.Rotation
	local result = frame:Inverse() * CFrame.fromEulerAnglesYXZ(pitch, yaw, 0) * frame * base
	joint.base = base
	joint.written = result
	setTransform(instance, result)
end

-- Takes the turn off, if the animation has not already written over it.
function Joints.release(joint: Joint)
	local written = joint.written
	if not written then
		return
	end
	joint.written = nil
	local instance = joint.instance
	if instance.Parent and instance.Transform:FuzzyEq(written, REWRITE_EPSILON) then
		setTransform(instance, joint.base)
	end
end

local function adoptOne(joint: Joint?)
	if joint and joint.written then
		joint.written = joint.instance.Transform
	end
end

-- Takes what is on the joints now as the turn's own, after other code wrote
-- on top of the turn, so the next turn goes on the animation, not on that.
function Joints.adopt(set: Set)
	adoptOne(set.neck)
	adoptOne(set.waist)
	adoptOne(set.shoulder)
end

function Joints.releaseAll(set: Set)
	local neck, waist, shoulder = set.neck, set.waist, set.shoulder
	if neck then
		Joints.release(neck)
	end
	if waist then
		Joints.release(waist)
	end
	if shoulder then
		Joints.release(shoulder)
	end
end

return Joints
