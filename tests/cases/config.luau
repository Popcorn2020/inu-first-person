--!strict
-- Config: overrides change only what they name, the result is frozen, and a
-- mistake in a setting is an error that names it.

local Check = require("../check")
local roblox = require("@lune/roblox") :: any

local Enum = roblox.Enum
local Vector3 = roblox.Vector3

return function(load: (string) -> any)
	local Config = load("Config")
	Check.section("Config")

	local defaults = Config.defaults
	Check.ok("defaults are frozen", table.isfrozen(defaults) and table.isfrozen(defaults.sprint))
	Check.ok(
		"a list in the defaults is frozen",
		table.isfrozen(defaults.input.keyboard)
			and defaults.input.keyboard[1] == Enum.KeyCode.LeftShift
	)

	local resolved = Config.resolve({ sprint = { runMultiplier = 1.4 }, sway = { seed = -5 } })
	Check.ok("an override applies", resolved.sprint.runMultiplier == 1.4)
	Check.ok(
		"its neighbours keep their defaults",
		resolved.sprint.maxAngle == defaults.sprint.maxAngle
	)
	Check.ok("other sections keep their defaults", resolved.camera.firstPerson == "start")
	Check.ok("a negative seed is allowed", resolved.sway.seed == -5)
	Check.ok("the result is frozen", table.isfrozen(resolved) and table.isfrozen(resolved.sprint))
	Check.ok("the defaults are untouched", defaults.sprint.runMultiplier == 1.6)

	local keys =
		Config.resolve({ input = { keyboard = { Enum.KeyCode.LeftControl, Enum.KeyCode.C } } })
	Check.ok(
		"a list is replaced whole",
		#keys.input.keyboard == 2 and keys.input.keyboard[2] == Enum.KeyCode.C
	)
	Check.ok(
		"an empty list turns the keys off",
		#Config.resolve({ input = { keyboard = {} } }).input.keyboard == 0
	)
	Check.ok(
		"a choice",
		Config.resolve({ camera = { firstPerson = "lock" } }).camera.firstPerson == "lock"
	)
	Check.ok("template false", Config.resolve({ ui = { template = false } }).ui.template == false)
	Check.ok(
		"a Vector3",
		Config.resolve({ bob = { amplitude = Vector3.new(0, 0, 1) } }).bob.amplitude
			== Vector3.new(0, 0, 1)
	)

	-- configure merges onto the settings in use, not the defaults.
	local base = Config.resolve({ look = { turnDamping = 0.2 }, input = { keyboard = {} } })
	local configured = Config.resolve({ kick = { shake = 0.5 } }, base, "configure")
	Check.ok(
		"an override on a base keeps the base's overrides",
		configured.look.turnDamping == 0.2 and configured.kick.shake == 0.5
	)
	Check.ok("an empty list in the base is kept", #configured.input.keyboard == 0)
	Check.ok(
		"a list can be set on a base whose list is empty",
		#Config.resolve({ input = { keyboard = { Enum.KeyCode.Q } } }, base).input.keyboard == 1
	)
	Check.ok("the base is untouched", base.kick.shake == defaults.kick.shake)

	local function resolving(overrides: any): () -> ()
		return function()
			Config.resolve(overrides)
		end
	end
	Check.errors(
		"an unknown key",
		"setting 'sprint.runMultipler' does not exist",
		resolving({ sprint = { runMultipler = 1.4 } })
	)
	Check.errors(
		"an unknown section",
		"setting 'sprinting' does not exist",
		resolving({ sprinting = {} })
	)
	Check.errors("a key that is not a string", "setting '1' does not exist", resolving({ [1] = 5 }))
	Check.errors(
		"a wrong type",
		"setting 'sprint.runMultiplier' takes a number, got a string",
		resolving({ sprint = { runMultiplier = "fast" } })
	)
	Check.errors(
		"a negative number",
		"setting 'stamina.max' takes 0 or more",
		resolving({ stamina = { max = -1 } })
	)
	Check.errors(
		"NaN",
		"setting 'stamina.max' takes a finite number",
		resolving({ stamina = { max = 0 / 0 } })
	)
	Check.errors(
		"infinity",
		"setting 'stamina.max' takes a finite number",
		resolving({ stamina = { max = math.huge } })
	)
	Check.errors(
		"a choice that does not exist",
		"setting 'camera.firstPerson' takes one of",
		resolving({ camera = { firstPerson = "third" } })
	)
	Check.errors(
		"a section given a number",
		"setting 'sprint' takes a table",
		resolving({ sprint = 5 })
	)
	Check.errors(
		"a list given a map",
		"setting 'input.keyboard' takes a list",
		resolving({ input = { keyboard = { x = Enum.KeyCode.A } } })
	)
	Check.errors(
		"a list item of the wrong enum",
		"setting 'input.keyboard[1]' takes a",
		resolving({ input = { keyboard = { Enum.UserInputType.MouseButton1 } } })
	)
	Check.errors(
		"a template that is not a ScreenGui",
		"setting 'ui.template' takes a ScreenGui or false",
		resolving({ ui = { template = "gui" } })
	)
	Check.errors(
		"a table for a Vector3",
		"setting 'bob.amplitude' takes a Vector3, got a table",
		resolving({ bob = { amplitude = { 0, 0, 1 } } })
	)
	Check.errors(
		"past an upper bound",
		"setting 'look.waistShare' takes 1 or less",
		resolving({ look = { waistShare = 1.5 } })
	)
	Check.errors(
		"a head that tilts past the view",
		"setting 'look.headPitchShare' takes 1 or less",
		resolving({ look = { headPitchShare = 1.2 } })
	)
	Check.errors(
		"the server's rate",
		"setting 'sync.sendRate' takes 30 or less",
		resolving({ sync = { sendRate = 60 } })
	)
	Check.errors("settings that are not a table", "start takes a table", resolving(5))
	Check.errors("configure names itself", "configure takes a table", function()
		Config.resolve(5 :: any, defaults, "configure")
	end)
end
