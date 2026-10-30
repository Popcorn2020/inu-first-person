--!strict
-- A small reporter: a check prints only when it fails, and finish() prints
-- the totals and exits with 1 if anything failed.

local process = require("@lune/process")

local Check = {}

local passed = 0
local failed = 0
local section = ""

local function show(value: number): string
	return string.format("%.6g", value)
end

function Check.section(name: string)
	section = name
end

function Check.ok(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
		return
	end
	failed += 1
	print(`FAIL [{section}] {name}{if detail then ": " .. detail else ""}`)
end

function Check.near(name: string, actual: number, expected: number, tolerance: number)
	Check.ok(
		name,
		math.abs(actual - expected) <= tolerance,
		`got {show(actual)}, expected {show(expected)} within {show(tolerance)}`
	)
end

-- Runs `action` and checks that it errors with a message containing `part`.
function Check.errors(name: string, part: string, action: () -> ())
	local ok, message = pcall(action)
	if ok then
		Check.ok(name, false, "did not error")
		return
	end
	local text = tostring(message)
	Check.ok(name, string.find(text, part, 1, true) ~= nil, `error was: {text}`)
end

function Check.show(value: number): string
	return show(value)
end

function Check.finish()
	print(`{passed} passed, {failed} failed`)
	process.exit(if failed > 0 then 1 else 0)
end

return Check
