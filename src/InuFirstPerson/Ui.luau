--!strict
-- The stamina gauge and the touch sprint button. The layout lives in a
-- ScreenGui (Assets.InuFirstPersonUi, or the game's own through
-- Config.ui.template) so it can be seen and changed in Studio; this only
-- shows the state, fades the gauge, and sets the button just above the touch
-- jump button, whose place on the screen only the engine knows.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Shared = require(script.Parent.Shared)
local SprintInput = require(script.Parent.SprintInput)

-- How often the touch jump button is looked for and followed.
local JUMP_BUTTON_CHECK = 1
-- The sprint button's size against the jump button's, and the gap above it.
local BUTTON_SHARE = 0.8
local BUTTON_GAP = 10
local BUTTON_TEXT_SHARE = 0.28
-- The button's background while it is pressed or toggled on.
local ACTIVE_TRANSPARENCY = 0.15

local Ui = {}

local player = Players.LocalPlayer

type Look = {
	gauge: Frame,
	fill: Frame,
	button: GuiButton?,
	gaugeTransparency: number,
	fillTransparency: number,
	fillColor: Color3,
	exhaustedColor: Color3,
	buttonTransparency: number,
	buttonPosition: UDim2,
	buttonSize: UDim2,
	buttonAnchor: Vector2,
	buttonTextSize: number,
}

local screenGui: ScreenGui? = nil
local look: Look? = nil
local alpha = 0
local sinceFull = math.huge
local jumpButton: GuiObject? = nil
local jumpCheckLeft = 0
local lastShare = -1
local lastExhausted: boolean? = nil
local lastAlpha = -1
local lastButtonShown: boolean? = nil
local lastButtonActive: boolean? = nil

local function findChild(parent: Instance, name: string, className: string): Instance
	local child = parent:FindFirstChild(name)
	if not child or not child:IsA(className) then
		error(
			`InuFirstPerson: the UI template needs a {className} named {parent:GetFullName()}.{name}`,
			0
		)
	end
	return child
end

local function findJumpButton(): GuiObject?
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local touchGui = playerGui and playerGui:FindFirstChild("TouchGui")
	local frame = touchGui and touchGui:FindFirstChild("TouchControlFrame")
	local jump = frame and frame:FindFirstChild("JumpButton")
	return if jump and jump:IsA("GuiObject") then jump else nil
end

local function placeButton(current: Look, button: GuiButton)
	local jump = jumpButton
	local gui = screenGui
	if jump and gui and jump.Visible and jump.AbsoluteSize.X > 0 then
		-- The two ScreenGuis may have different insets, so measure from ours.
		local origin = gui.AbsolutePosition
		local size = math.floor(jump.AbsoluteSize.X * BUTTON_SHARE + 0.5)
		button.AnchorPoint = Vector2.new(0.5, 1)
		button.Position = UDim2.fromOffset(
			jump.AbsolutePosition.X + jump.AbsoluteSize.X / 2 - origin.X,
			jump.AbsolutePosition.Y - origin.Y - BUTTON_GAP
		)
		button.Size = UDim2.fromOffset(size, size)
		if button:IsA("TextButton") then
			button.TextSize = math.max(math.floor(size * BUTTON_TEXT_SHARE + 0.5), 1)
		end
	else
		button.AnchorPoint = current.buttonAnchor
		button.Position = current.buttonPosition
		button.Size = current.buttonSize
		if button:IsA("TextButton") then
			button.TextSize = current.buttonTextSize
		end
	end
end

local function wantsButton(available: boolean): boolean
	local mode = Shared.config.ui.sprintButton
	if not available or mode == "never" then
		return false
	end
	return mode == "always" or UserInputService.PreferredInput == Enum.PreferredInput.Touch
end

-- Puts the UI in the player's PlayerGui and returns the sprint button for
-- the input to bind, if the UI is on.
function Ui.start(): GuiButton?
	local settings = Shared.config.ui
	if not settings.enabled then
		return nil
	end
	local template = if settings.template
		then settings.template
		else script.Parent.Assets.InuFirstPersonUi
	local gui = template:Clone() :: ScreenGui
	gui.ResetOnSpawn = false

	local gauge = findChild(gui, "Gauge", "Frame") :: Frame
	local fill = findChild(gauge, "Fill", "Frame") :: Frame
	local buttonInstance = gui:FindFirstChild("SprintButton")
	local button = if buttonInstance and buttonInstance:IsA("GuiButton")
		then buttonInstance
		else nil
	local exhaustedColor = fill:GetAttribute("ExhaustedColor")

	local current: Look = {
		gauge = gauge,
		fill = fill,
		button = button,
		gaugeTransparency = gauge.BackgroundTransparency,
		fillTransparency = fill.BackgroundTransparency,
		fillColor = fill.BackgroundColor3,
		exhaustedColor = if typeof(exhaustedColor) == "Color3"
			then exhaustedColor
			else fill.BackgroundColor3,
		buttonTransparency = if button then button.BackgroundTransparency else 0,
		buttonPosition = if button then button.Position else UDim2.new(),
		buttonSize = if button then button.Size else UDim2.new(),
		buttonAnchor = if button then button.AnchorPoint else Vector2.zero,
		buttonTextSize = if button and button:IsA("TextButton") then button.TextSize else 0,
	}
	gauge.Visible = false
	if button then
		button.Visible = false
	end

	local playerGui = player:FindFirstChildOfClass("PlayerGui")
		or player:WaitForChild("PlayerGui", 10)
	if not playerGui then
		error("InuFirstPerson: the player has no PlayerGui to show the UI in", 0)
	end
	gui.Parent = playerGui

	screenGui = gui
	look = current
	alpha = 0
	sinceFull = math.huge
	jumpButton = nil
	jumpCheckLeft = 0
	lastShare, lastExhausted, lastAlpha = -1, nil, -1
	lastButtonShown, lastButtonActive = nil, nil
	return button
end

function Ui.stop()
	if screenGui then
		screenGui:Destroy()
	end
	screenGui = nil
	look = nil
	jumpButton = nil
end

local function updateGauge(current: Look, share: number, exhausted: boolean, dt: number)
	local settings = Shared.config
	sinceFull = if share < 1 then 0 else sinceFull + dt
	local target = if settings.stamina.enabled and sinceFull < settings.ui.hideDelay then 1 else 0
	local fadeTime = settings.ui.fadeTime
	alpha = if fadeTime > 0
		then math.clamp(alpha + (if target > alpha then dt else -dt) / fadeTime, 0, 1)
		else target

	if alpha ~= lastAlpha then
		lastAlpha = alpha
		current.gauge.Visible = alpha > 0
		current.gauge.BackgroundTransparency = 1 - (1 - current.gaugeTransparency) * alpha
		current.fill.BackgroundTransparency = 1 - (1 - current.fillTransparency) * alpha
	end
	if share ~= lastShare then
		lastShare = share
		current.fill.Size = UDim2.fromScale(math.clamp(share, 0, 1), 1)
	end
	if exhausted ~= lastExhausted then
		lastExhausted = exhausted
		current.fill.BackgroundColor3 = if exhausted
			then current.exhaustedColor
			else current.fillColor
	end
end

local function updateButton(current: Look, button: GuiButton, available: boolean, dt: number)
	local shown = wantsButton(available)
	if shown ~= lastButtonShown then
		lastButtonShown = shown
		button.Visible = shown
		jumpCheckLeft = 0
	end
	if not shown then
		return
	end

	jumpCheckLeft -= dt
	if jumpCheckLeft <= 0 then
		jumpCheckLeft = JUMP_BUTTON_CHECK
		jumpButton = findJumpButton()
		placeButton(current, button)
	end

	local active = SprintInput.isTouchActive()
	if active ~= lastButtonActive then
		lastButtonActive = active
		button.BackgroundTransparency = if active
			then ACTIVE_TRANSPARENCY
			else current.buttonTransparency
	end
end

-- Called by Sprint every step. `share` is stamina over max; `available` is
-- whether sprinting can be asked for now.
function Ui.update(share: number, exhausted: boolean, available: boolean, dt: number)
	local current = look
	if not current then
		return
	end
	updateGauge(current, share, exhausted, dt)
	local button = current.button
	if button then
		updateButton(current, button, available, dt)
	end
end

return Ui
