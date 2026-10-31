--!strict
-- The demo's start: one call, with the demo's own settings (DemoSettings).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- The demo place is built by tools/build-demo.luau, so its Instances are not
-- on disk for the type checker; each is narrowed where it is taken.
local InuFirstPerson = require(ReplicatedStorage:FindFirstChild("InuFirstPerson") :: ModuleScript)
local demoSettings = require(ReplicatedStorage:FindFirstChild("DemoSettings") :: ModuleScript)

InuFirstPerson.start(demoSettings)
