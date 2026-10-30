--!strict
-- The demo's start: one call, with the cost of each frame written to the
-- module's attribute for the demo panel.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- The demo place is built by tools/build-demo.luau, so its Instances are not
-- on disk for the type checker; each is narrowed where it is taken.
local InuFirstPerson = require(ReplicatedStorage:FindFirstChild("InuFirstPerson") :: ModuleScript)

InuFirstPerson.start({ debug = { measure = true } })
