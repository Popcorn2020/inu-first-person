# InuFirstPerson

A first-person base for any Roblox experience. Put `InuFirstPerson.rbxm` in ReplicatedStorage, call `start()` from a client script, and the player gets a camera that moves like a head, their own body when they look down, and sprinting with stamina, on R15 and R6 alike and the same at 60 and 240 frames per second. A game tunes it with settings and drives it through the API; it does not edit the module.

## What it does

- Camera motion: a walking and sprinting bob, a lean into sideways movement, a hand-held sway, breathing that gets heavy when stamina runs low, a dip on landing that grows with the fall, smooth climbing of steps, and a wider field of view while sprinting. It works on top of Roblox's default camera, so mouse, touch and gamepad look and their sensitivity stay as Roblox makes them.
- The player's own body: a copy of the character's look follows the real pose every frame and sits a little behind the camera, so looking down shows arms and legs without the camera inside the head. While a Tool is held, the right arm is drawn where the real arm is, so the hand meets the tool.
- Sprinting: hold Left Shift on a keyboard, press L3 on a gamepad, or hold the RUN button on a touch screen. Stamina drains while sprinting and refills after a short wait; a gauge shows it and fades once it is full again.
- Third person: when the player zooms out (mouse wheel, pinch), during a cutscene, or whenever the camera is not at the character's head, the body copy stops and hides and the walking motion is off. Field of view offsets, kicks, sprinting and stamina carry on. Zooming back in eases the motion back in.

## Getting started

1. Insert `dist/InuFirstPerson.rbxm` into ReplicatedStorage. It brings one ModuleScript, `InuFirstPerson`.
2. Start it once per player from a LocalScript in StarterPlayerScripts (or a Script whose RunContext is Client). It follows respawns by itself.

	```lua
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local InuFirstPerson = require(ReplicatedStorage.InuFirstPerson)

	InuFirstPerson.start()
	```

3. Check these StarterPlayer properties:
	- `EnableMouseLockOption`: turn it off. Shift lock uses the Shift key that sprinting takes.
	- `CameraMinZoomDistance`: keep the default 0.5 so the camera can reach first person.
	- `CameraMaxZoomDistance`: how far players can zoom out into third person. `camera.firstPerson = "lock"` keeps them in first person instead.

## Settings

`start` takes a table that names only what differs from the defaults. Every setting, with its default, its unit and what it changes, is in `Config.luau` inside the module.

```lua
InuFirstPerson.start({
	camera = { firstPerson = "lock", fieldOfView = 80 },
	sprint = { walkSpeed = 12, runMultiplier = 1.8 },
	stamina = { drainRate = 20, jumpCost = 10 },
	input = { touchMode = "toggle" },
})
```

- An unknown key, a value of the wrong type, a negative number where it makes no sense, or a string outside its choices is an error when `start` runs, so a typo shows up at once.
- Lists, such as the sprint keys, are replaced whole.
- The resolved settings are frozen; `getConfig()` returns them. To change a setting, `stop()` and `start` again with new overrides. Values that change during play go through the API instead.

| Group | What it covers |
| --- | --- |
| `camera` | Whether the game starts in, locks to, or leaves alone first person; the field of view; overall motion scale, and the scale under Reduce Motion and in VR |
| `bob` | Step rate and size of the walking bob, its growth with speed and sprinting |
| `strafeTilt` | The lean into sideways movement |
| `sway` | The hand-held drift and jitter, and how much stronger they get when tired |
| `breathing` | Breathing at rest and when out of stamina |
| `landing` | The dip on landing: from which falling speed, how deep, how springy |
| `stepSmoothing` | How the view climbs steps |
| `sprintFov` | The field of view added while sprinting |
| `kick` | The springs behind `camera.kick` |
| `body` | The body copy: on or off, where it sits, how it trails fast turns, the Tool arm |
| `sprint` | Walking speed, sprinting speed, acceleration, the angle and speed needed to sprint |
| `stamina` | Size, drain, refill, the wait after running out, jump cost |
| `input` | Sprint keys, hold or toggle for each kind of input, the input context's priority |
| `ui` | The gauge and touch button: on or off, a game's own layout, when the button shows |
| `debug` | Writing the module's time per frame to an attribute |

## API

Everything is under the table `require` returns. Functions that change something error until `start()` has run; the ones that read work at any time. `stop()` clears what they set.

```lua
InuFirstPerson.version: string
InuFirstPerson.start(overrides: table?)    -- errors on the server, when already running, or on a bad setting
InuFirstPerson.stop()                      -- puts back camera mode, zoom and field of view; walks without sprinting
InuFirstPerson.isRunning(): boolean
InuFirstPerson.getConfig(): Config         -- the settings in use (the defaults while stopped)

-- camera
InuFirstPerson.camera.FirstPersonChanged   -- Event(isFirstPerson: boolean)
InuFirstPerson.camera.setEnabled(enabled: boolean)  -- motion on or off; the camera mode stays
InuFirstPerson.camera.isEnabled(): boolean
InuFirstPerson.camera.isFirstPerson(): boolean
InuFirstPerson.camera.kick(rotationDegrees: Vector3, position: Vector3?)
InuFirstPerson.camera.setOffset(key: string, offset: CFrame?)
InuFirstPerson.camera.setFovOffset(key: string, degrees: number?)
InuFirstPerson.camera.getLayer(): CFrame

-- body
InuFirstPerson.body.setEnabled(enabled: boolean)
InuFirstPerson.body.isEnabled(): boolean
InuFirstPerson.body.getModel(): Model?
InuFirstPerson.body.rebuild()
InuFirstPerson.body.setPoseCallback(callback: ((model: Model, placed: CFrame) -> ())?)

-- sprint
InuFirstPerson.sprint.Changed              -- Event(isSprinting: boolean)
InuFirstPerson.sprint.setEnabled(enabled: boolean)
InuFirstPerson.sprint.isEnabled(): boolean
InuFirstPerson.sprint.isSprinting(): boolean
InuFirstPerson.sprint.setWalkSpeed(walkSpeed: number?)
InuFirstPerson.sprint.getWalkSpeed(): number
InuFirstPerson.sprint.setSpeedMultiplier(key: string, multiplier: number?)

-- stamina
InuFirstPerson.stamina.Changed             -- Event(value: number, max: number)
InuFirstPerson.stamina.ExhaustedChanged    -- Event(isExhausted: boolean)
InuFirstPerson.stamina.get(): number
InuFirstPerson.stamina.getMax(): number
InuFirstPerson.stamina.set(value: number)
InuFirstPerson.stamina.add(amount: number)
InuFirstPerson.stamina.isExhausted(): boolean
```

- Events have `Connect`, `Once` and `Wait`, like Roblox's events. Handlers run in their own thread, so they may yield.
- `camera.kick` swings the view out to `rotationDegrees` (X pitch up, Y yaw left, Z roll left) and `position` (studs, in the camera's space) and springs back, as for recoil or a hit. Kicks add up.
- `camera.setOffset` holds a CFrame on the camera, in its own space, under a key, until set again or cleared with nil (a lean, an aim). Offsets multiply in the sorted order of their keys, since CFrames do not commute: name the keys so the order is the one you want.
- `camera.setFovOffset` adds degrees under a key; offsets add up, on top of the sprint widening.
- `camera.getLayer` is the motion put on the camera this frame, in the camera's space, for something that should sway with the view. The motion is applied at `Enum.RenderPriority.Camera.Value + 1`; read it after that.
- `body.setPoseCallback` runs every frame right after the copy takes its pose (at `Enum.RenderPriority.Camera.Value + 5`), so it may move the copy's parts, to reach for something, say. It must not yield.
- `body.rebuild` remakes the copy, for changes it cannot see: a recolored part, a resized avatar. Parts and accessories that are added or removed are picked up by themselves.
- `sprint.setWalkSpeed(nil)` goes back to `sprint.walkSpeed`, and a setting of 0 means `StarterPlayer.CharacterWalkSpeed`. Multipliers apply to walking and sprinting and multiply together (carrying something heavy, a slowing hit).
- `stamina.set` and `stamina.add` clamp to 0..max.

## Things to know in a game

- While running, the module owns `Humanoid.WalkSpeed` and writes it every frame. Change walking speed with `sprint.setWalkSpeed` and `sprint.setSpeedMultiplier`, not by writing the Humanoid.
- First person is judged from the default camera's own output: the camera type is Custom, the subject is the player's character, and the camera is within a stud of its focus. A cutscene that sets the camera type to Scriptable, or a camera on another subject, is third person to the module.
- With `camera.firstPerson = "start"` (the default), `start` zooms the camera in, and the player can zoom out and back as far as `CameraMaxZoomDistance` allows. `"lock"` sets `Player.CameraMode` to LockFirstPerson, and `"keep"` leaves camera mode and zoom to the game. `stop` puts back the camera mode it found.
- Steps: characters pop up a step in a frame or two, without a vertical velocity. The view takes those rises in and climbs them at the character's horizontal speed plus `stepSmoothing.catchUpSpeed`. Slopes and lifts driven by physics (constraints, velocities) carry a velocity and are followed as they are. A platform moved by setting its CFrame lifts the character without a velocity, so the view trails it by up to `stepSmoothing.maxOffset` until it stops; move such platforms with physics, or turn `stepSmoothing` off in that game.
- The player's Reduce Motion setting scales the motion by `camera.reducedMotionScale`. In VR the motion is scaled by `camera.vrScale` (0 by default) and the body copy is hidden. VR has not been tried.
- Characters driven by a ControllerManager (the Character Controller Library) have not been tried; the module warns once when it sees one, since sprinting writes `Humanoid.WalkSpeed`.
- Server Authority (`Workspace.AuthorityMode` set to Server) is not supported yet: sprinting sets the walking speed on the client.
- Cost: the camera and sprint steps cost little and stay the same; the body copy moves each of its parts every frame, so its cost grows with the avatar's parts and accessories. Turn on `debug.measure` to write the average milliseconds per frame to the module's attribute `InuFirstPersonFrameMs` once a second. In the MicroProfiler the steps show as `InuFirstPerson.Camera`, `InuFirstPerson.Body` and `InuFirstPerson.Sprint`.

## The gauge and the sprint button

The bundled layout, `InuFirstPerson.Assets.InuFirstPersonUi`, is a thin gauge at the bottom center, above the default backpack hotbar, and a round RUN button for touch screens. The button sits just above the touch jump button at 0.8 of its size, and falls back to the layout's own place when the jump button is not there. Its look is a plain starting point.

To give it the game's own look, copy that ScreenGui into the game, restyle it in Studio, and pass it as `ui.template`. It needs:

- `Gauge`, a Frame, holding `Fill`, a Frame. The module sets `Fill`'s width by scale, fades both by their BackgroundTransparency, and, if `Fill` has a Color3 attribute `ExhaustedColor`, colors it with that while exhausted.
- `SprintButton`, a GuiButton, if the game wants the touch button. The module shows it, makes it more opaque while held or toggled on, and sets its position, size and text size to follow the jump button.

Keep the template out of StarterGui, which would show a second copy; ReplicatedStorage works. To see the bundled layout in Edit, put a copy in StarterGui for a moment.

## Copies and versions

This folder is the source of InuFirstPerson. Games use a copy of `dist/InuFirstPerson.rbxm` and change it only through settings and the API, so each new version can replace the copy whole.

- The version is in `Version.luau` inside the module, and `CHANGELOG.md` lists what each version changed. Compare a game's copy with it to see whether the copy is behind.
- When a game needs something the settings and the API do not offer, it asks for it here. A fix that cannot wait may be made in the game's copy if it is written down in that game and reported here, and is dropped when a version with the fix replaces the copy.
- A game that wants to change the module freely detaches its copy and writes that down in the game; a detached copy no longer gets new versions.
- Known issues and ideas are in `ISSUES.md`.

## Developing

Tools: Rojo 7.7.1, Lune 0.11.0, luau-lsp 1.70.1, StyLua 2.5.2, selene 0.30.1.

- `src/InuFirstPerson/` is the module. `init.luau` is the API, `Config.luau` the settings; `CameraMotion`, `StaminaModel`, `TurnLag` and `Math` are pure (no Roblox services) so the tests can run them.
- Build the rbxm: `rojo build default.project.json -o dist/InuFirstPerson.rbxm`
- Run the tests: `lune run tests/run`. They play the same scripted runs (walking, sprinting, strafing, a step, a slope, a jump, a fall, a stop, third person, a kick) at 30, 60, 144 and 240 frames per second and at uneven frame times, and check that every value stays within a frame of a 960 frames-per-second run. They also check the stamina timings, the turn lag and the settings' errors.
- Build the demo place after the rbxm: `lune run tools/build-demo` writes `dist/InuFirstPersonDemo.rbxl`, a course with stairs, slopes, towers with a ladder, a long corridor, a seat and a lift, and a panel that shows the frame rate, the module's cost per frame and the rig, and switches between R15 and R6. Its scripts are in `tools/demo/`.
- Known diagnostics: the type checker cannot resolve the `@lune/*` requires in `tests/` and `tools/`, nor the module the demo scripts take from the built place.

## License

Copyright (c) 2026 inu (@inutataaaaa). All rights reserved. See `LICENSE`.
