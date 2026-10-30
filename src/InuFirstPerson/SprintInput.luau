--!strict
-- The sprint input through the Input Action System. Keys, gamepad buttons
-- and the touch button each get their own action, so each can hold or toggle
-- as Config.input says.

local UserInputService = game:GetService("UserInputService")

local Shared = require(script.Parent.Shared)

local CONTEXT_NAME = "InuFirstPersonInput"

type Device = "keyboard" | "gamepad" | "touch"

local ACTION_NAMES: { [Device]: string } = {
	keyboard = "SprintKeyboard",
	gamepad = "SprintGamepad",
	touch = "SprintTouch",
}

local SprintInput = {}

local held: { [string]: boolean } = { keyboard = false, gamepad = false, touch = false }
local toggled: { [string]: boolean } = { keyboard = false, gamepad = false, touch = false }
local context: InputContext? = nil
local connections: { RBXScriptConnection } = {}

local function modeOf(device: Device): "hold" | "toggle"
	local settings = Shared.config.input
	if device == "keyboard" then
		return settings.keyboardMode
	elseif device == "gamepad" then
		return settings.gamepadMode
	end
	return settings.touchMode
end

local function onPressed(device: Device)
	-- Shift while typing in chat is not a sprint.
	if device == "keyboard" and UserInputService:GetFocusedTextBox() then
		return
	end
	if modeOf(device) == "toggle" then
		toggled[device] = not toggled[device]
	else
		held[device] = true
	end
end

local function releaseAll()
	for device in held do
		held[device] = false
	end
end

local function addAction(
	parent: InputContext,
	device: Device,
	keys: { Enum.KeyCode },
	button: GuiButton?
)
	local action = Instance.new("InputAction")
	action.Name = ACTION_NAMES[device]
	action.Type = Enum.InputActionType.Bool
	for _, key in keys do
		local binding = Instance.new("InputBinding")
		binding.KeyCode = key
		binding.Parent = action
	end
	if button then
		local binding = Instance.new("InputBinding")
		binding.UIButton = button
		binding.Parent = action
	end
	action.Parent = parent
	table.insert(
		connections,
		action.Pressed:Connect(function()
			onPressed(device)
		end)
	)
	table.insert(
		connections,
		action.Released:Connect(function()
			held[device] = false
		end)
	)
end

-- `button` is the touch button to bind, if the UI has one.
function SprintInput.start(button: GuiButton?)
	local settings = Shared.config.input
	local newContext = Instance.new("InputContext")
	newContext.Name = CONTEXT_NAME
	newContext.Priority = settings.priority
	newContext.Sink = settings.sink
	addAction(newContext, "keyboard", settings.keyboard, nil)
	addAction(newContext, "gamepad", settings.gamepad, nil)
	if button then
		addAction(newContext, "touch", {}, button)
	end
	newContext.Parent = script.Parent
	context = newContext

	-- A key let go while the window is away would stay held.
	table.insert(connections, UserInputService.WindowFocusReleased:Connect(releaseAll))
	table.insert(
		connections,
		UserInputService.TextBoxFocused:Connect(function()
			held.keyboard = false
		end)
	)
end

function SprintInput.stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	connections = {}
	if context then
		context:Destroy()
		context = nil
	end
	releaseAll()
	SprintInput.clearToggles()
end

-- Whether any device asks to sprint now.
function SprintInput.wantsSprint(): boolean
	for device, isHeld in held do
		if isHeld or toggled[device] then
			return true
		end
	end
	return false
end

-- Whether the touch button is pressed or toggled on, for how it looks.
function SprintInput.isTouchActive(): boolean
	return held.touch or toggled.touch
end

-- Ends every toggled sprint, as when the character stops or runs out.
function SprintInput.clearToggles()
	for device in toggled do
		toggled[device] = false
	end
end

return SprintInput
