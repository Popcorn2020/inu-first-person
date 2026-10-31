--!strict
-- Runs the tests of the modules that need no Roblox engine, at several frame
-- rates. From the repo root:
--
--     lune run tests/run

local Check = require("./check")
local load = require("./loader")

local cases = {
	require("./cases/math"),
	require("./cases/stamina"),
	require("./cases/turn"),
	require("./cases/look-pose"),
	require("./cases/sync-protocol"),
	require("./cases/kick"),
	require("./cases/config"),
	require("./cases/camera-motion"),
}

for _, case in cases do
	case(load)
end
Check.finish()
