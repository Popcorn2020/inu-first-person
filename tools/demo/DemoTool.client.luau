--!strict
-- Using the demo's tool (a click, or a tap on a touch screen, while it is
-- held) kicks the camera, as F does.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- The demo place is built by tools/build-demo.luau, so its Instances are not
-- on disk for the type checker; each is narrowed where it is taken.
local kick = require(ReplicatedStorage:FindFirstChild("DemoKick") :: ModuleScript)
local tool = script.Parent :: Tool

tool.Activated:Connect(kick)
