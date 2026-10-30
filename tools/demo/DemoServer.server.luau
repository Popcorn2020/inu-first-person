--!strict
-- The demo's server side: starts InuFirstPerson's server half, rebuilds a
-- player's character as R15 or R6 when the panel asks, and moves the lift
-- up and down.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local LIFT_HEIGHTS = { 0, 16 }
local LIFT_WAIT = 5

local RIG_TYPES: { [string]: Enum.HumanoidRigType } = {
	R15 = Enum.HumanoidRigType.R15,
	R6 = Enum.HumanoidRigType.R6,
}

-- The demo place is built by tools/build-demo.luau, so its Instances are not
-- on disk for the type checker; each is narrowed where it is taken.
local InuFirstPersonServer =
	require(ServerScriptService:FindFirstChild("InuFirstPersonServer") :: ModuleScript)
InuFirstPersonServer.start(ReplicatedStorage:FindFirstChild("InuFirstPerson") :: ModuleScript)

local rigRemote = ReplicatedStorage:FindFirstChild("DemoRig") :: RemoteEvent
local lift = workspace:FindFirstChild("Lift") :: Model
local base = lift:FindFirstChild("Base") :: BasePart
local prismatic = base:FindFirstChild("Prismatic") :: PrismaticConstraint

local rebuilding: { [Player]: true } = {}

local function rebuild(player: Player, rigType: Enum.HumanoidRigType)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 or humanoid.RigType == rigType then
		return
	end
	local description = humanoid:GetAppliedDescription()
	local pivot = character:GetPivot()
	-- Yields while the avatar's assets load.
	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, rigType)
	end)
	if not ok then
		warn(`Demo: could not build the {rigType.Name} character: {result}`)
		return
	end
	local model = result :: Model
	-- The player may have left or respawned while the model was built.
	if player.Parent ~= Players or player.Character ~= character then
		model:Destroy()
		return
	end
	model.Name = player.Name
	model:PivotTo(pivot)
	player.Character = model
	model.Parent = workspace
	character:Destroy()
end

rigRemote.OnServerEvent:Connect(function(player, name)
	local rigType = if typeof(name) == "string" then RIG_TYPES[name] else nil
	if not rigType or rebuilding[player] then
		return
	end
	rebuilding[player] = true
	rebuild(player, rigType)
	rebuilding[player] = nil
end)

Players.PlayerRemoving:Connect(function(player)
	rebuilding[player] = nil
end)

task.spawn(function()
	local index = 1
	while true do
		task.wait(LIFT_WAIT)
		index = index % #LIFT_HEIGHTS + 1
		prismatic.TargetPosition = LIFT_HEIGHTS[index]
	end
end)
