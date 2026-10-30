--!strict
-- Loads the pure modules of src/InuFirstPerson outside Roblox. Each module is
-- given a stand-in `script` whose Parent hands back its siblings, and a
-- `require` that loads them the same way, so `require(script.Parent.Math)`
-- works unchanged. Roblox datatypes come from @lune/roblox.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any

local SOURCE = `{process.cwd}/src/InuFirstPerson`

local cache: { [string]: any } = {}

local load: (name: string) -> any

local function makeScript(name: string): any
	local parent = setmetatable({}, {
		__index = function(_, child: string)
			return { moduleName = child }
		end,
	})
	return { Name = name, Parent = parent }
end

load = function(name: string): any
	local cached = cache[name]
	if cached ~= nil then
		return cached
	end
	local source = fs.readFile(`{SOURCE}/{name}.luau`)
	local chunk = luau.load(source, {
		debugName = name,
		environment = {
			script = makeScript(name),
			require = function(target: any)
				return load(target.moduleName)
			end,
			Vector3 = roblox.Vector3,
			CFrame = roblox.CFrame,
			Color3 = roblox.Color3,
			Enum = roblox.Enum,
		},
	})
	local result = chunk()
	cache[name] = result
	return result
end

return load
