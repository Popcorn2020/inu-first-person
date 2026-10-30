--!strict
-- Frame times for playing the same seconds at different frame rates. Every
-- run passes exactly through each multiple of 1/6 second, where 30, 60, 144
-- and 240 frames per second all have a frame, so an event placed there
-- starts a frame in every run.

export type Run = {
	name: string,
	-- The end time of each frame. The first frame starts at 0.
	times: { number },
	-- The longest frame.
	longest: number,
}

local GRID = 6

local Frames = {}

Frames.GRID = GRID

function Frames.fixed(fps: number, duration: number): Run
	local times = {}
	for frame = 1, math.round(duration * fps) do
		table.insert(times, frame / fps)
	end
	return { name = `{fps} fps`, times = times, longest = 1 / fps }
end

-- Frame lengths drawn evenly between `shortest` and `longest` from a fixed
-- seed, each cut short at the next multiple of 1/6 second.
function Frames.jitter(seed: number, shortest: number, longest: number, duration: number): Run
	local state = seed
	local function draw(): number
		-- A linear congruential generator, so a run is the same on every PC.
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end

	local times = {}
	local time = 0
	local mark = 1
	while mark <= duration * GRID do
		local nextTime = time + shortest + (longest - shortest) * draw()
		local markTime = mark / GRID
		if nextTime >= markTime then
			time = markTime
			mark += 1
		else
			time = nextTime
		end
		table.insert(times, time)
	end
	return { name = `jitter {seed}`, times = times, longest = longest }
end

return Frames
