# InuFirstPerson

A first-person base for any Roblox experience. Put `InuFirstPerson.rbxm` in ReplicatedStorage, call `start()` from a client script, and the player gets a camera at the eye that moves like a head, their own body, a character that turns with the view, and sprinting with stamina, on R15 and R6 alike and the same at 60 and 240 frames per second. Add the server half, `InuFirstPersonServer.rbxm`, and players also see where the others look. A game tunes it with settings and drives it through the API; it does not edit the module.

## What it does

- Camera motion: a walking and sprinting bob, a lean into sideways movement, a hand-held sway, breathing that gets heavy when stamina runs low, a dip on landing that grows with the fall, smooth climbing of steps, a wider field of view while sprinting, and kicks that throw the view out and wobble back to rest on one spring, with a fine shake that fades with the wobble. It works on top of Roblox's default camera, so mouse, touch and gamepad look and their sensitivity stay as Roblox makes them.
- The eye: in first person the camera sits at the eye, in front of the neck, and swings out over the chest when looking down, as a head does on its neck. As with people, the head takes part of the tilt and the eyes the rest, so the eye stays above the chest, and the further it looks down the further it leans forward, as someone does to see their feet, so the chest does not fill the view. Sitting, climbing or riding, the eye stays where the head is. Against a wall it draws back toward the neck at its own height, so climbing a ladder does not jolt it up and down.
- The player's own body: the real character shows in first person, all but the head and what is worn on it, so sitting, climbing, a held Tool, emotes and vehicles show as they are.
- Where characters look: in first person the view turns first and the body follows it on a spring, so a quick look to the side turns the eyes, then the head and chest, then the body, which swings a little past and settles. Standing still it follows too, so a slow turn moves the body along with the view; a game can let the feet stay put while the view turns a little either side (`look.standTwist`). Every character's head and waist turn toward where that player looks, on top of the animation: the waist a moment after the head, the neck only as far as a neck turns, and a look round behind the body lets the head go back to the front. A held Tool aims with the view, a little behind fast turns.
- Sprinting: hold Left Shift on a keyboard, press L3 on a gamepad, or hold the RUN button on a touch screen. Stamina drains while sprinting and refills after a short wait; a gauge shows it and fades once it is full again.
- Third person: when the player zooms out (mouse wheel, pinch), the walking motion and the eye are off and the Humanoid turns the character again; field of view offsets, kicks, where heads look, sprinting and stamina carry on, and zooming back in eases the eye and the motion back in. During a cutscene (a Scriptable camera) or with the camera on another subject, the module also leaves the camera itself alone, with no kicks or field of view offsets, while sprinting and stamina carry on.

## Getting started

1. Insert `dist/InuFirstPerson.rbxm` into ReplicatedStorage. It brings one ModuleScript, `InuFirstPerson`.
2. Start it once per player from a LocalScript in StarterPlayerScripts (or a Script whose RunContext is Client). It follows respawns by itself.

	```lua
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local InuFirstPerson = require(ReplicatedStorage.InuFirstPerson)

	InuFirstPerson.start()
	```

3. To let players see where the others look, insert `dist/InuFirstPersonServer.rbxm` into ServerScriptService and start it from a Script, with the module the clients use. Give both halves the same version; `start` errors when they differ. Without the server half, each player sees only their own look.

	```lua
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ServerScriptService = game:GetService("ServerScriptService")
	local InuFirstPersonServer = require(ServerScriptService.InuFirstPersonServer)

	InuFirstPersonServer.start(ReplicatedStorage.InuFirstPerson)
	```

4. Check these StarterPlayer properties:
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
- The resolved settings are frozen; `getConfig()` returns them. `configure(overrides)` changes them while running, naming only what differs from the settings in use. Most take effect at once; `camera.firstPerson`, `camera.fieldOfView`, `input`, `ui.enabled`, `ui.template`, `ui.sprintButton` and `debug` are read on `start` and wait for the next one. Values that change during play, such as a walking speed, go through the API instead.

| Group | What it covers |
| --- | --- |
| `camera` | Whether the game starts in, locks to, or leaves alone first person; the field of view; where the eye sits and how far it leans looking down; overall motion scale, and the scale under Reduce Motion and in VR |
| `bob` | Step rate and size of the walking bob, its growth with speed and sprinting |
| `strafeTilt` | The lean into sideways movement |
| `sway` | The hand-held drift and jitter, and how much stronger they get when tired |
| `breathing` | Breathing at rest and when out of stamina |
| `landing` | The dip on landing: from which falling speed, how deep, how springy |
| `stepSmoothing` | How the view climbs steps |
| `sprintFov` | The field of view added while sprinting |
| `kick` | Behind `camera.kick`: how fast the view wobbles back and how quickly the wobble dies, the shake, and how repeated kicks vary |
| `body` | Showing the player's own body |
| `look` | How the body follows the view: its spring, and whether standing feet let the view turn a little first; how far the neck turns and when the head lets a look behind go; the head's and the waist's shares and the waist's delay; the Tool's aim |
| `sync` | Sharing where each player looks: how often, how smoothly others follow |
| `sprint` | Walking speed, sprinting speed, acceleration, the angle and speed needed to sprint |
| `stamina` | Size, drain, refill, the wait after running out, jump cost |
| `input` | Sprint keys, hold or toggle for each kind of input, the input context's priority |
| `ui` | The gauge and touch button: on or off, a game's own layout, when the button shows |
| `debug` | Writing the module's time per frame to an attribute |

## API

Everything is under the table `require` returns. Functions that change something error until `start()` has run; the ones that read work at any time. `stop()` clears what they set.

```lua
InuFirstPerson.version: string
InuFirstPerson.start(overrides: table?)    -- errors on the server, when already running, or on a bad setting;
                                           -- may wait up to 10 seconds for the PlayerGui
InuFirstPerson.stop()                      -- puts back zoom, field of view and a locked camera mode; walks without sprinting
InuFirstPerson.isRunning(): boolean
InuFirstPerson.getConfig(): Config         -- the settings in use (the defaults while stopped)
InuFirstPerson.configure(overrides: table)  -- changes settings while running; errors on a bad setting

-- camera
InuFirstPerson.camera.FirstPersonChanged   -- Event(isFirstPerson: boolean)
InuFirstPerson.camera.setEnabled(enabled: boolean)  -- motion on or off; the camera mode stays
InuFirstPerson.camera.isEnabled(): boolean
InuFirstPerson.camera.isFirstPerson(): boolean
InuFirstPerson.camera.kick(rotationDegrees: Vector3, position: Vector3?)
InuFirstPerson.camera.setOffset(key: string, offset: CFrame?)
InuFirstPerson.camera.setFovOffset(key: string, degrees: number?)
InuFirstPerson.camera.getLayer(): CFrame
InuFirstPerson.camera.getMotion(): Motion

-- body
InuFirstPerson.body.setEnabled(enabled: boolean)
InuFirstPerson.body.isEnabled(): boolean

-- look
InuFirstPerson.look.setEnabled(enabled: boolean)
InuFirstPerson.look.isEnabled(): boolean
InuFirstPerson.look.getAngles(player: Player?): (number?, number?)
InuFirstPerson.look.setPoseCallback(callback: ((character: Model, player: Player) -> ())?)

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

-- the server half, required from ServerScriptService.InuFirstPersonServer
InuFirstPersonServer.version: string
InuFirstPersonServer.start(client: ModuleScript)  -- the InuFirstPerson module the clients use; errors on a client,
                                                  -- when already running, or when the versions differ
InuFirstPersonServer.stop()                       -- removes the remote; the clients stop sending
```

- Events have `Connect`, `Once` and `Wait`, like Roblox's events. Handlers run in their own thread, so they may yield.
- `camera.kick` swings the view out to `rotationDegrees` (X pitch up, Y yaw left, Z roll left) and `position` (studs, in the camera's space) and wobbles back to rest, as for recoil or a hit. Kicks add up.
- `camera.setOffset` holds a CFrame on the camera, in its own space, under a key, until set again or cleared with nil (a lean, an aim). Offsets multiply in the sorted order of their keys, since CFrames do not commute: name the keys so the order is the one you want.
- `camera.setFovOffset` adds degrees under a key; offsets add up, on top of the sprint widening.
- `camera.getLayer` is the motion put on the camera this frame, in the camera's space, for something that should sway with the view. It leaves out the move to the eye, the step smoothing and the landing dip. The motion is applied at `Enum.RenderPriority.Camera.Value + 1`; read it after that.
- `camera.getMotion` returns a new table of how much each part of the motion turns the view this frame, in degrees: `bob`, `sway`, `breath`, `tilt`, `landing`, `kick` (the springs), `shake` (the kicks' shake) and `rotation` (all of it); `position`, how far the motion moves the view, in studs; `fatigue`, 0 with full stamina to 1 with none; `fovOffset`, in degrees. All are 0 while the motion is off. It suits a monitor or effects that follow the motion.
- `look.setEnabled(false)` hands the character's facing back to the Humanoid and leaves every character's joints to the animation. Others still see the local player's look fade to straight ahead.
- `look.setPoseCallback` runs every frame right after the look turns a character's joints (the local character, and each other one whose look shows), before physics and after the Animator, so it may write joints' `Transform` on top: an IK that brings the left hand to a held Tool, say. What it writes on the neck, waist and right shoulder is redone from the animation each frame, so it does not pile up. It must not yield.
- `look.getAngles` is where a player's head turns as this client shows it, in degrees relative to their character's facing: yaw (left positive), then pitch (up positive), or nil, nil while nothing is known. It is the look held to what a neck can do: 0, 0 while the look is round behind the body, and while the head is left to the animation, further than 150 studs from the camera.
- `sprint.setWalkSpeed(nil)` goes back to `sprint.walkSpeed`, and a setting of 0 means `StarterPlayer.CharacterWalkSpeed`. Multipliers apply to walking and sprinting and multiply together (carrying something heavy, a slowing hit).
- `stamina.set` and `stamina.add` clamp to 0..max.

## Things to know in a game

- While running, the module owns `Humanoid.WalkSpeed` and writes it every frame. Change walking speed with `sprint.setWalkSpeed` and `sprint.setSpeedMultiplier`, not by writing the Humanoid.
- In first person, while the character stands, walks, jumps, falls, climbs or swims, the module also owns its facing: it turns `Humanoid.AutoRotate` off and sets the root's facing right after the camera. Seated, in PlatformStand or in third person, it turns AutoRotate back on. Climbing and swimming stay with the module because the Humanoid, given AutoRotate in first person, faces the character along the line from the camera to it, which is backwards with the camera at the eye in front of the character. If the game had turned AutoRotate off before the module took it, the module leaves the facing to the game; while the module holds it, the game turns the character by calling `look.setEnabled(false)` first.
- The look writes the `Transform` of the Neck, Waist and right shoulder joints (Motor6D or AnimationConstraint) before physics, on top of what the Animator wrote, on every character within 150 studs of the camera. A game that writes those joints itself does it in `look.setPoseCallback`, or turns `look.enabled` off.
- The body shows because the module sets `LocalTransparencyModifier` on the character's parts every frame in first person. To hide a part in first person, set its `Transparency`; a `LocalTransparencyModifier` the game writes is overwritten.
- First person is judged from the default camera's own output: the camera type is Custom, the subject is the player's character, and the camera is within a stud of its focus. A cutscene that sets the camera type to Scriptable, or a camera on another subject, is third person to the module.
- With `camera.firstPerson = "start"` (the default), `start` zooms the camera in, and the player can zoom out and back as far as `CameraMaxZoomDistance` allows. `"lock"` sets `Player.CameraMode` to LockFirstPerson and `stop` puts back the mode it found. `"start"` and `"keep"` leave `Player.CameraMode` as the game set it, and `"keep"` leaves the zoom too.
- Steps: characters pop up a step in a frame or two. The view takes in any rise that the floor under the character does not explain and climbs it at the character's horizontal speed plus `stepSmoothing.catchUpSpeed`. The floor is found with a ray down from the root; its slope along the character's way and its own velocity explain a rise, so slopes and lifts driven by physics (constraints, velocities) are followed as they are. A platform moved by setting its CFrame lifts the character without a velocity, so the view trails it by up to `stepSmoothing.maxOffset` until it stops; move such platforms with physics, or turn `stepSmoothing` off in that game.
- The player's Reduce Motion setting scales the motion by `camera.reducedMotionScale`. In VR the motion is scaled by `camera.vrScale` (0 by default) and the body is left as the default camera shows it. VR has not been tried.
- Characters driven by a ControllerManager (the Character Controller Library) have not been tried; the module warns once when it sees one, since sprinting writes `Humanoid.WalkSpeed`.
- Server Authority (`Workspace.AuthorityMode` set to Server) is not supported yet: sprinting sets the walking speed on the client.
- Cost: the camera and sprint steps cost little and stay the same. Showing the body sets a property on each of the character's parts every frame, so it grows with the avatar's parts and accessories; the look turns three joints on each character near the camera. Turn on `debug.measure` to write the average milliseconds per frame to the module's attribute `InuFirstPersonFrameMs` once a second. In the MicroProfiler the steps show as `InuFirstPerson.Camera` (with the body), `InuFirstPerson.Look` and `InuFirstPerson.Sprint`.
- The server half keeps no game state. It passes on 4 bytes per look, at most 30 a second from each player and only while the look changes, and sends the changes to everyone 15 times a second in batches, with everyone's look again every 3 seconds.

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

- `src/InuFirstPerson/` is the module. `init.luau` is the API, `Config.luau` the settings; `CameraMotion`, `StaminaModel`, `Turn`, `LookPose`, `SyncProtocol` and `Math` are pure (no Roblox services) so the tests can run them.
- `src/InuFirstPersonServer/` is the server half. It shares `SyncProtocol.luau` and `Version.luau` with the module: `server.project.json` puts copies of them in it, so both halves read the same protocol and version.
- Build the rbxms: `rojo build module.project.json -o dist/InuFirstPerson.rbxm` and `rojo build server.project.json -o dist/InuFirstPersonServer.rbxm`. `default.project.json` puts both into a place, for the type checker and for serving to Studio.
- Run the tests: `lune run tests/run`. They play the same scripted runs (walking, sprinting, strafing, a step, a slope, a jump, a fall, a stop, third person, a kick) at 30, 60, 144 and 240 frames per second and at uneven frame times, and check that every value stays within a frame of a 960 frames-per-second run. They also check the stamina timings, how the body follows the view (at the same frame rates), how the head, neck and waist share a look, the look's encoding, the shape of a kick and the settings' errors.
- Build the demo place after the rbxms: `lune run tools/build-demo` writes `dist/InuFirstPersonDemo.rbxl`, a course with stairs, slopes, towers with a ladder, a long corridor, a seat, a lift and a tool, and on screen a panel with the frame rate, the module's cost per frame and the rig (R15 or R6), sliders for some settings with the default in the middle, a monitor of the camera motion, and the player seen from outside. Its scripts are in `tools/demo/`.
- Known diagnostics: the type checker cannot resolve the `@lune/*` requires in `tests/` and `tools/`, nor the module the demo scripts take from the built place.

## License

MIT. Copyright (c) 2026 inu (@inutataaaaa). See `LICENSE`.
