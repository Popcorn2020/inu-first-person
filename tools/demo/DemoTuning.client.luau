--!strict
-- The setting sliders: each changes one setting through
-- InuFirstPerson.configure while the demo runs, with the setting's default in
-- the middle, or at the low end for a row with a High attribute (a default at
-- the setting's floor). Reset puts every one back. Holding Left Alt shows a cursor in
-- first person, where the mouse is otherwise locked to the middle.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- The demo place is built by tools/build-demo.luau, so its Instances are not
-- on disk for the type checker; each is narrowed where it is taken.
local InuFirstPerson = require(ReplicatedStorage:FindFirstChild("InuFirstPerson") :: ModuleScript)
local gui = script.Parent :: ScreenGui
local form = require(gui:FindFirstChild("DemoForm") :: ModuleScript)
local left = gui:FindFirstChild("Left") :: Frame
local leftLayout = left:FindFirstChildOfClass("UIListLayout") :: UIListLayout
local panel = left:FindFirstChild("Panel") :: Frame
local tuning = left:FindFirstChild("Tuning") :: Frame
local headerButtons = (tuning:FindFirstChild("Header") :: Frame):FindFirstChild("Buttons") :: Frame
local toggleButton = headerButtons:FindFirstChild("Toggle") :: TextButton
local resetButton = headerButtons:FindFirstChild("Reset") :: TextButton
local rows = tuning:FindFirstChild("Rows") :: Frame
local cursor = gui:FindFirstChild("Cursor") :: TextButton

local CURSOR_KEY = Enum.KeyCode.LeftAlt
-- About a hundred steps from end to end.
local STEPS = 100
-- Within this share of the width from the default, a drag lands on it.
local DEFAULT_SNAP = 0.02
local DEFAULT_COLOR = Color3.fromRGB(230, 232, 236)
local CHANGED_COLOR = Color3.fromRGB(232, 168, 56)

type Slider = {
	group: string,
	key: string,
	default: number,
	low: number,
	high: number,
	decimals: number,
	value: number,
	track: GuiButton,
	fill: Frame,
	knob: Frame,
	valueLabel: TextLabel,
}

type Drag = {
	slider: Slider,
	input: InputObject,
}

local sliders: { Slider } = {}
local drag: Drag? = nil
local cursorKeyHeld = false
local open = not form.touch

local function readDefault(group: string, key: string): number
	local groupSettings = InuFirstPerson.getConfig()[group]
	local value = if typeof(groupSettings) == "table" then groupSettings[key] else nil
	if typeof(value) ~= "number" then
		error(`Demo: InuFirstPerson has no number setting {group}.{key}`)
	end
	return value
end

-- Where `value` sits along the track, 0..1.
local function fractionOf(slider: Slider, value: number): number
	return (value - slider.low) / (slider.high - slider.low)
end

local function show(slider: Slider)
	local fraction = fractionOf(slider, slider.value)
	local home = fractionOf(slider, slider.default)
	slider.knob.Position = UDim2.fromScale(fraction, 0.5)
	local fillSize = slider.fill.Size
	slider.fill.Position = UDim2.fromScale(math.min(fraction, home), 0.5)
	slider.fill.Size = UDim2.new(math.abs(fraction - home), 0, fillSize.Y.Scale, fillSize.Y.Offset)
	slider.valueLabel.Text = string.format(`%.{slider.decimals}f`, slider.value)
	slider.valueLabel.TextColor3 = if slider.value == slider.default
		then DEFAULT_COLOR
		else CHANGED_COLOR
end

-- The value under screen position `x`, in steps counted from the default so
-- the default's place gives it exactly.
local function valueAt(slider: Slider, x: number): number
	local track = slider.track
	local fraction = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
	if math.abs(fraction - fractionOf(slider, slider.default)) < DEFAULT_SNAP then
		return slider.default
	end
	local raw = slider.low + fraction * (slider.high - slider.low)
	local scale = 10 ^ slider.decimals
	local stepped = slider.default + math.round((raw - slider.default) * scale) / scale
	return math.clamp(stepped, slider.low, slider.high)
end

local function apply(slider: Slider, value: number)
	if value == slider.value then
		return
	end
	slider.value = value
	show(slider)
	if InuFirstPerson.isRunning() then
		InuFirstPerson.configure({ [slider.group] = { [slider.key] = value } })
	end
end

local function resetAll()
	drag = nil
	local defaults: { [string]: { [string]: number } } = {}
	for _, slider in sliders do
		slider.value = slider.default
		show(slider)
		local group = defaults[slider.group] or {}
		group[slider.key] = slider.default
		defaults[slider.group] = group
	end
	if InuFirstPerson.isRunning() then
		InuFirstPerson.configure(defaults)
	end
end

local function updateCursor()
	cursor.Visible = cursorKeyHeld or drag ~= nil
end

local function setOpen(value: boolean)
	open = value
	rows.Visible = open
	toggleButton.Text = if open then "Hide" else "Show"
	-- The touch layout has no room for both under each other.
	if form.touch then
		panel.Visible = not open
	end
end

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function addSlider(row: Frame)
	local group = row:GetAttribute("Group")
	local key = row:GetAttribute("Key")
	local low = row:GetAttribute("Low")
	local givenHigh = row:GetAttribute("High")
	assert(
		typeof(group) == "string" and typeof(key) == "string" and typeof(low) == "number",
		`Demo: the slider row {row.Name} needs the attributes Group, Key and Low`
	)
	local default = readDefault(group, key)
	local high = if typeof(givenHigh) == "number" then givenHigh else 2 * default - low
	if default < low or default >= high or (givenHigh == nil and default == low) then
		error(`Demo: {group}.{key} defaults to {default}, outside its slider's {low} to {high}`)
	end
	local track = row:FindFirstChild("Track") :: GuiButton
	local slider: Slider = {
		group = group,
		key = key,
		default = default,
		low = low,
		high = high,
		decimals = math.max(0, math.ceil(-math.log10((high - low) / STEPS) - 1e-9)),
		value = default,
		track = track,
		fill = track:FindFirstChild("Fill") :: Frame,
		knob = track:FindFirstChild("Knob") :: Frame,
		valueLabel = row:FindFirstChild("Value") :: TextLabel,
	}
	show(slider)
	track.InputBegan:Connect(function(input: InputObject)
		if isPress(input) and not drag then
			drag = { slider = slider, input = input }
			updateCursor()
			apply(slider, valueAt(slider, input.Position.X))
		end
	end)
	table.insert(sliders, slider)
end

UserInputService.InputChanged:Connect(function(input: InputObject)
	local current = drag
	if not current then
		return
	end
	-- A mouse press and the mouse's movement come as different InputObjects.
	local follows = input == current.input
		or (
			input.UserInputType == Enum.UserInputType.MouseMovement
			and current.input.UserInputType == Enum.UserInputType.MouseButton1
		)
	if follows then
		apply(current.slider, valueAt(current.slider, input.Position.X))
	end
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if input.KeyCode == CURSOR_KEY and not processed then
		cursorKeyHeld = true
		updateCursor()
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.KeyCode == CURSOR_KEY then
		cursorKeyHeld = false
		updateCursor()
		return
	end
	local current = drag
	if not current then
		return
	end
	-- A touch ends with its own InputObject; another finger lifting does not end it.
	local ends = input == current.input
		or (
			input.UserInputType == Enum.UserInputType.MouseButton1
			and current.input.UserInputType == Enum.UserInputType.MouseButton1
		)
	if ends then
		drag = nil
		updateCursor()
	end
end)

-- Alt-Tab takes the focus with Alt still down, and its release never arrives.
UserInputService.WindowFocusReleased:Connect(function()
	cursorKeyHeld = false
	drag = nil
	updateCursor()
end)

toggleButton.Activated:Connect(function()
	setOpen(not open)
end)
resetButton.Activated:Connect(resetAll)

if form.touch then
	leftLayout.FillDirection = Enum.FillDirection.Vertical
end
setOpen(open)

for _, row in rows:GetChildren() do
	if row:IsA("Frame") then
		addSlider(row)
	end
end
