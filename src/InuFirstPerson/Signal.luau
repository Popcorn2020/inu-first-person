--!strict
-- A small signal for the API's events. Each handler runs in its own thread,
-- as with Roblox's events: a handler may yield, and one that errors reports
-- the error without stopping the frame step that fired it or the other
-- handlers.

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
}

type Entry = {
	handler: (...any) -> (),
	connection: Connection,
}

type SignalObject = {
	-- Replaced, never edited, when a handler leaves, so a Fire that is going
	-- through the old list is not disturbed.
	entries: { Entry },
}

local Signal = {}

local function removeEntry(object: SignalObject, entry: Entry)
	local kept: { Entry } = {}
	for _, other in object.entries do
		if other ~= entry then
			table.insert(kept, other)
		end
	end
	object.entries = kept
end

local function connect(object: SignalObject, handler: (...any) -> (), once: boolean): Connection
	local entry: Entry
	local connection: Connection = {
		Connected = true,
		Disconnect = function(self: Connection)
			if not self.Connected then
				return
			end
			self.Connected = false
			removeEntry(object, entry)
		end,
	}
	local run = handler
	if once then
		run = function(...)
			connection:Disconnect()
			handler(...)
		end
	end
	entry = { handler = run, connection = connection }
	local entries = table.clone(object.entries)
	table.insert(entries, entry)
	object.entries = entries
	return connection
end

function Signal.new<T...>(): Signal<T...>
	local object: SignalObject = { entries = {} }
	local signal = {}

	function signal.Connect(_self: any, handler: (T...) -> ()): Connection
		return connect(object, handler :: any, false)
	end

	function signal.Once(_self: any, handler: (T...) -> ()): Connection
		return connect(object, handler :: any, true)
	end

	function signal.Fire(_self: any, ...: T...)
		for _, entry in object.entries do
			if entry.connection.Connected then
				task.spawn(entry.handler, ...)
			end
		end
	end

	function signal.DisconnectAll(_self: any)
		for _, entry in object.entries do
			entry.connection.Connected = false
		end
		object.entries = {}
	end

	return (signal :: any) :: Signal<T...>
end

return Signal
