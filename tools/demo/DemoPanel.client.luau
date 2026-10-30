--!strict
-- The demo panel: the frame rate, the module's cost per frame and the rig,
-- the R15 and R6 buttons, and F to kick the camera.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- The demo place is built by tools/build-demo.luau, so its Instances are not
-- on disk for the type checker; each is narrowed where it is taken.
local module = ReplicatedStorage:FindFirstChild("InuFirstPerson") :: ModuleScript
local InuFirstPerson = require(module)

local STATS_PERIOD = 0.5

local rigRemote = ReplicatedStorage:FindFirstChild("DemoRig") :: RemoteEvent
local panel = (script.Parent :: Instance):FindFirstChild("Panel") :: Frame
local stats = panel:FindFirstChild("Stats") :: TextLabel
local rigs = panel:FindFirstChild("Rigs") :: Frame
local random = Random.new()

for _, name in { "R15", "R6" } do
	local button = rigs:FindFirstChild(name)
	if button and button:IsA("GuiButton") then
		button.Activated:Connect(function()
			rigRemote:FireServer(name)
		end)
	end
end

local frames = 0
local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
	frames += 1
	elapsed += dt
	if elapsed < STATS_PERIOD then
		return
	end
	local cost = module:GetAttribute("InuFirstPersonFrameMs")
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	stats.Text = string.format(
		"%d fps  ·  %s  ·  %s",
		math.round(frames / elapsed),
		if typeof(cost) == "number" then string.format("%.3f ms a frame", cost) else "- ms",
		if humanoid then humanoid.RigType.Name else "no character"
	)
	frames = 0
	elapsed = 0
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.KeyCode ~= Enum.KeyCode.F or not InuFirstPerson.isRunning() then
		return
	end
	InuFirstPerson.camera.kick(
		Vector3.new(4, random:NextNumber(-1.5, 1.5), random:NextNumber(-1, 1)),
		Vector3.new(0, 0, 0.2)
	)
end)
