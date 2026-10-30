--!strict
-- Stamina as plain numbers, stepped by time. It drains while sprinting,
-- refills after a short wait, and once empty stays exhausted until it is back
-- to a share of max. Each step splits at the end of the wait, so the result
-- does not depend on how the time is cut into frames. Requires nothing, so
-- the desk tests can load it outside Roblox.

export type Settings = {
	max: number,
	drainRate: number,
	regenRate: number,
	regenDelay: number,
	recoverShare: number,
}

export type State = {
	value: number,
	exhausted: boolean,
	-- Time left before refilling starts.
	waitLeft: number,
}

local StaminaModel = {}

function StaminaModel.new(settings: Settings): State
	return { value = settings.max, exhausted = false, waitLeft = 0 }
end

local function updateExhausted(state: State, settings: Settings)
	if state.value <= 0 then
		state.exhausted = true
	elseif state.exhausted and state.value >= settings.max * settings.recoverShare then
		state.exhausted = false
	end
end

-- Advances `dt` seconds, sprinting or not for all of it.
function StaminaModel.step(state: State, settings: Settings, sprinting: boolean, dt: number)
	if sprinting then
		state.value = math.max(state.value - settings.drainRate * dt, 0)
		state.waitLeft = settings.regenDelay
	else
		local waited = math.min(state.waitLeft, dt)
		state.waitLeft -= waited
		local refillTime = dt - waited
		if refillTime > 0 then
			state.value = math.min(state.value + settings.regenRate * refillTime, settings.max)
		end
	end
	updateExhausted(state, settings)
end

-- Sets the value directly (clamped), as for a pickup or a scripted drain.
-- Setting it does not restart the refill wait.
function StaminaModel.set(state: State, settings: Settings, value: number)
	state.value = math.clamp(value, 0, settings.max)
	updateExhausted(state, settings)
end

-- Spends `amount`, as a jump does, and restarts the refill wait.
function StaminaModel.spend(state: State, settings: Settings, amount: number)
	if amount <= 0 then
		return
	end
	state.value = math.max(state.value - amount, 0)
	state.waitLeft = settings.regenDelay
	updateExhausted(state, settings)
end

function StaminaModel.refill(state: State, settings: Settings)
	state.value = settings.max
	state.exhausted = false
	state.waitLeft = 0
end

return StaminaModel
