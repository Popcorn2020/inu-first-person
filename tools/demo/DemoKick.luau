--!strict
-- The demo's camera kick, shared by F and by using the tool.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- The demo place is built by tools/build-demo.luau, so its Instances are not
-- on disk for the type checker; each is narrowed where it is taken.
local InuFirstPerson = require(ReplicatedStorage:FindFirstChild("InuFirstPerson") :: ModuleScript)

local random = Random.new()

return function()
	if not InuFirstPerson.isRunning() then
		return
	end
	InuFirstPerson.camera.kick(
		Vector3.new(4.6, random:NextNumber(-1.725, 1.725), random:NextNumber(-1.15, 1.15)),
		Vector3.new(0, 0, 0.23)
	)
end
