--!strict
-- Builds the demo place, dist/InuFirstPersonDemo.rbxl: the module from
-- dist/InuFirstPerson.rbxm, the scripts in tools/demo, a panel, and a course
-- with steps, slopes, a sprint corridor, ladders and drops, a seat, a lift
-- and a tool. From the repo root, after building the rbxm:
--
--     lune run tools/build-demo

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any

local Instance = roblox.Instance
local Enum = roblox.Enum
local Vector3 = roblox.Vector3
local Vector2 = roblox.Vector2
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local UDim = roblox.UDim
local UDim2 = roblox.UDim2
local Font = roblox.Font

local ROOT = process.cwd
local MODULE = `{ROOT}/dist/InuFirstPerson.rbxm`
local OUTPUT = `{ROOT}/dist/InuFirstPersonDemo.rbxl`
local SCRIPTS = `{ROOT}/tools/demo`

local GROUND = Color3.fromRGB(96, 100, 106)
local STONE = Color3.fromRGB(150, 154, 160)
local LIGHT = Color3.fromRGB(200, 203, 208)
local ACCENT = Color3.fromRGB(232, 168, 56)
local DARK = Color3.fromRGB(46, 49, 55)
local BUILDER_SANS = "rbxasset://fonts/families/BuilderSans.json"

-- Instances come from Lune's untyped roblox library, so these helpers return
-- what it returns.
local function new(className: string, properties: { [string]: any }, parent: any?)
	local instance = Instance.new(className)
	for name, value in properties do
		instance[name] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function block(
	parent: any,
	name: string,
	size: any,
	cframe: any,
	color: any,
	className: string?
)
	return new(className or "Part", {
		Name = name,
		Anchored = true,
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
	}, parent)
end

-- A sign with `text` on the side that faces the spawn at the origin.
local function sign(parent: any, text: string, position: any)
	local board = block(parent, `Sign {text}`, Vector3.new(10, 3, 0.4), CFrame.new(position), DARK)
	local gui = new("SurfaceGui", {
		-- Back faces +Z, Front faces -Z.
		Face = if position.Z < 0 then Enum.NormalId.Back else Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 40,
	}, board)
	new("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		-- A fixed size: TextScaled set from Lune did not reach the place file.
		TextSize = 72,
		FontFace = Font.new(BUILDER_SANS, Enum.FontWeight.Bold),
	}, gui)
end

local function readScript(name: string): string
	return fs.readFile(`{SCRIPTS}/{name}`)
end

local game = Instance.new("DataModel")
local workspace = game:GetService("Workspace")
local lighting = game:GetService("Lighting")
local replicatedStorage = game:GetService("ReplicatedStorage")
local serverScriptService = game:GetService("ServerScriptService")
local starterGui = game:GetService("StarterGui")
local starterPack = game:GetService("StarterPack")
local starterPlayer = game:GetService("StarterPlayer")

-- Settings of a new place that Lune's defaults predate, and the module's
-- advice: Shift sprints, so the Shift lock option is off.
workspace.StreamingEnabled = true
starterPlayer.CharacterUseJumpPower = false
starterPlayer.CharacterJumpHeight = 7.2
starterPlayer.CharacterWalkSpeed = 16
starterPlayer.EnableMouseLockOption = false
lighting.Technology = Enum.Technology.Future
lighting.ClockTime = 14.5
lighting.Brightness = 3
new("Atmosphere", { Density = 0.25, Haze = 1 }, lighting)

-- The module, as a game would put it in.
local module = roblox.deserializeModel(fs.readFile(MODULE))
assert(
	#module == 1 and module[1].Name == "InuFirstPerson",
	"dist/InuFirstPerson.rbxm holds the module"
)
module[1].Parent = replicatedStorage
new("RemoteEvent", { Name = "DemoRig" }, replicatedStorage)

-- Scripts.
local playerScripts = new("StarterPlayerScripts", {}, starterPlayer)
new("StarterCharacterScripts", {}, starterPlayer)
new(
	"LocalScript",
	{ Name = "InuFirstPersonDemo", Source = readScript("DemoClient.client.luau") },
	playerScripts
)
new(
	"Script",
	{ Name = "DemoServer", Source = readScript("DemoServer.server.luau") },
	serverScriptService
)

-- The panel, kept in StarterGui so it shows in Edit.
local panelGui = new("ScreenGui", {
	Name = "DemoPanel",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
}, starterGui)
local panel = new("Frame", {
	Name = "Panel",
	AnchorPoint = Vector2.new(0, 0),
	Position = UDim2.fromScale(0.01, 0.02),
	Size = UDim2.fromOffset(260, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = Color3.fromRGB(20, 22, 26),
	BackgroundTransparency = 0.25,
}, panelGui)
new("UICorner", { CornerRadius = UDim.new(0, 8) }, panel)
new("UIPadding", {
	PaddingTop = UDim.new(0, 10),
	PaddingBottom = UDim.new(0, 10),
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 12),
}, panel)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 6),
}, panel)

local function label(
	name: string,
	order: number,
	text: string,
	size: number,
	weight: any,
	color: any
)
	return new("TextLabel", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color,
		FontFace = Font.new(BUILDER_SANS, weight),
	}, panel)
end

label("Title", 1, "InuFirstPerson demo", 16, Enum.FontWeight.Bold, Color3.fromRGB(255, 255, 255))
label("Stats", 2, "- fps", 14, Enum.FontWeight.Medium, Color3.fromRGB(230, 232, 236))
local rigs = new("Frame", {
	Name = "Rigs",
	LayoutOrder = 3,
	Size = UDim2.new(1, 0, 0, 30),
	BackgroundTransparency = 1,
}, panel)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 6),
}, rigs)
for order, name in { "R15", "R6" } do
	local button = new("TextButton", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.new(0, 64, 1, 0),
		BackgroundColor3 = Color3.fromRGB(62, 66, 74),
		Text = name,
		TextSize = 14,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		FontFace = Font.new(BUILDER_SANS, Enum.FontWeight.Bold),
	}, rigs)
	new("UICorner", { CornerRadius = UDim.new(0, 6) }, button)
end
label(
	"Help",
	4,
	"Shift, L3 or RUN: sprint\nMouse wheel or pinch: third person\nF: kick the camera\nThe tool in the backpack shows the arm holding it",
	13,
	Enum.FontWeight.Regular,
	Color3.fromRGB(196, 200, 207)
)
new("LocalScript", { Name = "PanelScript", Source = readScript("DemoPanel.client.luau") }, panelGui)

-- A tool, to see the arm that holds it.
local tool = new("Tool", { Name = "Stick", CanBeDropped = false }, starterPack)
block(tool, "Handle", Vector3.new(0.4, 0.4, 2.4), CFrame.new(), ACCENT).Anchored = false

-- The course. The spawn faces -Z; stairs and slopes rise away from it.
local course = new("Folder", { Name = "Course" }, workspace)
block(course, "Ground", Vector3.new(512, 2, 512), CFrame.new(0, -1, 0), GROUND)
local spawn =
	block(course, "Spawn", Vector3.new(8, 1, 8), CFrame.new(0, 0.5, 0), LIGHT, "SpawnLocation")
spawn.Duration = 0

-- Stairs with risers of 0.5 to 2 studs: up eight steps, a landing, down eight.
local stairs = new("Model", { Name = "Stairs" }, course)
for index, riser in { 0.5, 1, 1.5, 2 } do
	local x = -30 + (index - 1) * 12
	local flight = new("Model", { Name = `Riser {riser}` }, stairs)
	local color = if index % 2 == 0 then STONE else LIGHT
	for step = 1, 8 do
		local height = riser * step
		block(
			flight,
			`Up {step}`,
			Vector3.new(8, height, 2),
			CFrame.new(x, height / 2, -15 - 2 * step),
			color
		)
		block(
			flight,
			`Down {step}`,
			Vector3.new(8, height, 2),
			CFrame.new(x, height / 2, -49 + 2 * step),
			color
		)
	end
	local top = riser * 8
	block(flight, "Landing", Vector3.new(8, top, 16), CFrame.new(x, top / 2, -40), color)
	sign(stairs, `Steps {riser}`, Vector3.new(x, 1.5 + top + 1, -40 - 8))
end

-- Slopes of 20, 35 and 50 degrees, each up to a platform. A WedgePart's
-- slope rises toward +Z, so it is turned to rise away from the spawn.
local slopes = new("Model", { Name = "Slopes" }, course)
for index, degrees in { 20, 35, 50 } do
	local x = -56 - (index - 1) * 12
	local length = 24
	local height = length * math.tan(math.rad(degrees))
	block(
		slopes,
		`Slope {degrees}`,
		Vector3.new(8, height, length),
		CFrame.new(x, height / 2, -15 - length / 2) * CFrame.Angles(0, math.pi, 0),
		STONE,
		"WedgePart"
	)
	block(
		slopes,
		`Top {degrees}`,
		Vector3.new(8, height, 8),
		CFrame.new(x, height / 2, -15 - length - 4),
		LIGHT
	)
	sign(slopes, `{degrees}°`, Vector3.new(x, height + 3, -15 - length - 8))
end

-- Towers of 6, 10 and 20 studs with a ladder on the side facing the spawn.
local drops = new("Model", { Name = "Drops" }, course)
for index, height in { 6, 10, 20 } do
	local x = 34 + (index - 1) * 14
	block(
		drops,
		`Tower {height}`,
		Vector3.new(10, height, 10),
		CFrame.new(x, height / 2, -30),
		STONE
	)
	block(
		drops,
		`Ladder {height}`,
		Vector3.new(2, height, 2),
		CFrame.new(x, height / 2, -24),
		DARK,
		"TrussPart"
	)
	sign(drops, `Drop {height}`, Vector3.new(x, height + 3, -35.4))
end

-- The sprint corridor, 300 studs south, with pillars every 10 studs.
local corridor = new("Model", { Name = "Corridor" }, course)
block(corridor, "Wall West", Vector3.new(1, 10, 300), CFrame.new(-7.5, 5, 174), STONE)
block(corridor, "Wall East", Vector3.new(1, 10, 300), CFrame.new(7.5, 5, 174), STONE)
for index = 0, 30 do
	local z = 24 + index * 10
	local color = if index % 2 == 0 then ACCENT else LIGHT
	block(
		corridor,
		`Pillar West {index}`,
		Vector3.new(1.5, 10, 1.5),
		CFrame.new(-6.25, 5, z),
		color
	)
	block(corridor, `Pillar East {index}`, Vector3.new(1.5, 10, 1.5), CFrame.new(6.25, 5, z), color)
end
sign(corridor, "Sprint", Vector3.new(0, 12, 22))

-- A chair by the spawn.
local chair = new("Model", { Name = "Chair" }, course)
block(chair, "Seat", Vector3.new(2, 1, 2), CFrame.new(12, 1.5, 6), ACCENT, "Seat")
block(chair, "Back", Vector3.new(2, 3, 0.4), CFrame.new(12, 3, 7.2), DARK)

-- A lift moved by a prismatic servo, next to a deck at its top height.
local lift = new("Model", { Name = "Lift" }, workspace)
local base = block(lift, "Base", Vector3.new(10, 1, 10), CFrame.new(-36, 0.5, 30), DARK)
local platform = block(lift, "Platform", Vector3.new(10, 1, 10), CFrame.new(-36, 1.5, 30), ACCENT)
platform.Anchored = false
-- Attachments whose X axis points up, the axis the prismatic slides along.
local up = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 1, 0), Vector3.new(-1, 0, 0))
local baseAttachment =
	new("Attachment", { Name = "Slide", CFrame = CFrame.new(0, 0.5, 0) * up }, base)
local platformAttachment =
	new("Attachment", { Name = "Slide", CFrame = CFrame.new(0, -0.5, 0) * up }, platform)
new("PrismaticConstraint", {
	Name = "Prismatic",
	Attachment0 = baseAttachment,
	Attachment1 = platformAttachment,
	ActuatorType = Enum.ActuatorType.Servo,
	ServoMaxForce = 1e7,
	Speed = 8,
	LinearResponsiveness = 45,
	LimitsEnabled = true,
	LowerLimit = 0,
	UpperLimit = 20,
	TargetPosition = 0,
}, base)
block(course, "Deck", Vector3.new(12, 17, 12), CFrame.new(-47, 8.5, 30), STONE)
sign(course, "Lift", Vector3.new(-36, 5, 24.6))

fs.writeFile(OUTPUT, roblox.serializePlace(game))
print(`Wrote {OUTPUT}`)
