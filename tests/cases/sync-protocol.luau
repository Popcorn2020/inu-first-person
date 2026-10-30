--!strict
-- SyncProtocol: angles survive the trip to int16 within a step, pitch stays
-- within straight up and down, and looks sit side by side in a buffer.

local Check = require("../check")

return function(load: (string) -> any)
	local SyncProtocol = load("SyncProtocol")
	Check.section("SyncProtocol")

	local step = math.pi / 32767
	for _, angle in { 0, 0.3, -1.2, math.pi - 1e-6, -math.pi + 1e-6 } do
		Check.near(
			`{angle} round trip`,
			SyncProtocol.angle(SyncProtocol.quantize(angle)),
			angle,
			step / 2 + 1e-12
		)
	end
	Check.near("past half a turn is held", SyncProtocol.quantize(4), 32767, 0)

	local data = buffer.create(2 * SyncProtocol.LOOK_SIZE)
	SyncProtocol.write(data, 0, SyncProtocol.quantize(0.5), SyncProtocol.quantize(-0.25))
	SyncProtocol.write(data, 1, SyncProtocol.quantize(-2), SyncProtocol.quantize(3))
	local yaw0, pitch0 = SyncProtocol.read(data, 0)
	local yaw1, pitch1 = SyncProtocol.read(data, 1)
	Check.near("first yaw", SyncProtocol.angle(yaw0), 0.5, step)
	Check.near("first pitch", SyncProtocol.angle(pitch0), -0.25, step)
	Check.near("second yaw", SyncProtocol.angle(yaw1), -2, step)
	Check.near("pitch held to straight up", SyncProtocol.angle(pitch1), math.pi / 2, step)

	-- A sender may put anything in the buffer; reading still holds pitch.
	buffer.writei16(data, 2, -32768)
	local _, wild = SyncProtocol.read(data, 0)
	Check.near("a wild pitch is held", SyncProtocol.angle(wild), -math.pi / 2, step)
end
