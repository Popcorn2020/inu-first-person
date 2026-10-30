# Changelog

What each version of InuFirstPerson changed. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/): a major version for changes a game has to adapt to (a setting or function renamed or removed, a behavior that changes by itself), a minor one for additions, a patch for fixes. Changed defaults are listed under Changed, since games that keep the defaults will feel them.

## [2.0.0] - 2026-10-30

### Changed

- The player's own body is the real character, shown in first person but for the head and what is worn on it, instead of a copy behind the camera. Sitting, climbing, a held Tool, emotes and vehicles show as they are.
- In first person the camera sits at the eye, in front of the neck, and swings with it (`camera.eyeHeight`, `camera.eyeForward`).
- In first person, while standing, walking, jumping or falling, the module turns `Humanoid.AutoRotate` off and turns the character with the view itself, in the same frame as the camera. Standing still, the feet stay until the view turns past `look.turnThreshold`. A game that turned AutoRotate off keeps the facing.
- Kicks snap, then settle slowly, and shake a little; repeated kicks vary in yaw and roll. `kick.frequency` is 6 (was 5) and `kick.damping` 0.45 (was 0.6).
- `camera.getLayer` also leaves out the move to the eye.

### Added

- The heads, waists and right arms of every character turn toward where that player looks, on top of the animation, and a held Tool tilts with the view (`look`).
- The server half, `InuFirstPersonServer`, which passes each player's look on to the others (`sync`).
- `configure`, to change settings while running.
- `camera.getMotion`, how much each part of the camera motion moves the view.
- `look.setEnabled`, `look.isEnabled`, `look.getAngles` and `look.setPoseCallback`.
- Settings: `camera.eyeHeight`, `camera.eyeForward`, `look.headPitchShare`, `kick.settleShare`, `kick.settleFrequency`, `kick.settleDamping`, `kick.shake`, `kick.shakeDegrees`, `kick.shakeFrequency`, `kick.shakeDecay`, `kick.variation`, `kick.seed`, and the groups `look` and `sync`.

### Removed

- `body.getModel`, `body.rebuild` and `body.setPoseCallback`, and the settings `body.offset`, `body.turnLag`, `body.maxTurnLag`, `body.toolArm` and `body.rebuildDelay`, since there is no body copy any more.

### Fixed

- Sitting or otherwise stopping no longer leaves the body behind the view.
- The body no longer trails the camera in jerks while a Tool is held.

## [1.0.0] - 2026-10-30

### Added

- Camera motion on top of Roblox's default camera: a walking and sprinting bob, a lean into sideways movement, a hand-held sway, breathing, a landing dip, step smoothing, a wider field of view while sprinting, kicks, and camera and field of view offsets that a game holds under keys.
- The player's own body under the camera, for R15 and R6, with the right arm drawn at the real arm while a Tool is held.
- Sprinting with stamina for keyboard (hold Left Shift), gamepad (press L3) and touch (hold the RUN button), with a gauge that fades once stamina is full.
- Third person: zooming out, cutscenes and cameras on other subjects stop and hide the body copy and turn the walking motion off; `camera.firstPerson` chooses between starting in first person, locking it, and leaving the camera to the game.
- Settings checked when `start` runs, and the API for the camera, the body, sprinting and stamina.
- Lune tests that play the same runs at 30, 60, 144 and 240 frames per second and at uneven frame times and compare them with 960.
- A demo place built by `tools/build-demo.luau`.
