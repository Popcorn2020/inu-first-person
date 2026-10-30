--!strict
-- The camera motion monitor: what each motion adds to the camera now, from
-- InuFirstPerson.camera.getMotion(). The bars follow every frame; each number
-- is the largest value of the last tenth of a second, steady enough to read.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- The demo place is built by tools/build-demo.luau, so its Instances are not
-- on disk for the type checker; each is narrowed where it is taken.
local InuFirstPerson = require(ReplicatedStorage:FindFirstChild("InuFirstPerson") :: ModuleScript)
local gui = script.Parent :: ScreenGui
local form = require(gui:FindFirstChild("DemoForm") :: ModuleScript)
local monitor = gui:FindFirstChild("Motion") :: Frame
local rowsFrame = monitor:FindFirstChild("Rows") :: Frame

local STEP_NAME = "InuFirstPersonDemoMotion"
local TEXT_PERIOD = 0.1

type Row = {
	field: string,
	format: string,
	full: number,
	linear: boolean,
	valueLabel: TextLabel,
	fill: Frame,
	-- The value furthest from 0 since the number was last written.
	peak: number,
}

local rows: { Row } = {}
for _, frame in rowsFrame:GetChildren() do
	local field = frame:GetAttribute("Field")
	if field == nil then
		continue
	end
	local format = frame:GetAttribute("Format")
	local full = frame:GetAttribute("Full")
	local linear = frame:GetAttribute("Linear")
	assert(
		typeof(field) == "string"
			and typeof(format) == "string"
			and typeof(full) == "number"
			and full > 0
			and typeof(linear) == "boolean",
		`Demo: the motion row {frame.Name} needs the attributes Field, Format, Full and Linear`
	)
	table.insert(rows, {
		field = field,
		format = format,
		full = full,
		linear = linear,
		valueLabel = frame:FindFirstChild("Value") :: TextLabel,
		fill = (frame:FindFirstChild("Bar") :: Frame):FindFirstChild("Fill") :: Frame,
		peak = 0,
	})
end

if form.touch then
	monitor.Parent = gui:FindFirstChild("TouchSlot") :: Frame
end

local sinceText = 0
-- After the camera motion is applied, at RenderPriority.Camera + 1.
RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Last.Value, function(dt: number)
	local motion = InuFirstPerson.camera.getMotion()
	sinceText += dt
	local writeText = sinceText >= TEXT_PERIOD
	if writeText then
		sinceText = 0
	end
	for _, row in rows do
		local value = motion[row.field]
		if typeof(value) ~= "number" then
			RunService:UnbindFromRenderStep(STEP_NAME)
			error(`Demo: InuFirstPerson.camera.getMotion() has no number {row.field}`)
		end
		local share = math.clamp(math.abs(value) / row.full, 0, 1)
		row.fill.Size = UDim2.fromScale(if row.linear then share else math.sqrt(share), 1)
		if math.abs(value) > math.abs(row.peak) then
			row.peak = value
		end
		if writeText then
			row.valueLabel.Text = string.format(row.format, row.peak)
			row.peak = 0
		end
	end
end)
