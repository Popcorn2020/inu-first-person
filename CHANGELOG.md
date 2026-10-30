# Changelog

What each version of InuFirstPerson changed. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/): a major version for changes a game has to adapt to (a setting or function renamed or removed, a behavior that changes by itself), a minor one for additions, a patch for fixes. Changed defaults are listed under Changed, since games that keep the defaults will feel them.

## [1.0.0] - 2026-10-30

### Added

- Camera motion on top of Roblox's default camera: a walking and sprinting bob, a lean into sideways movement, a hand-held sway, breathing, a landing dip, step smoothing, a wider field of view while sprinting, kicks, and camera and field of view offsets that a game holds under keys.
- The player's own body under the camera, for R15 and R6, with the right arm drawn at the real arm while a Tool is held.
- Sprinting with stamina for keyboard (hold Left Shift), gamepad (press L3) and touch (hold the RUN button), with a gauge that fades once stamina is full.
- Third person: zooming out, cutscenes and cameras on other subjects stop and hide the body copy and turn the walking motion off; `camera.firstPerson` chooses between starting in first person, locking it, and leaving the camera to the game.
- Settings checked when `start` runs, and the API for the camera, the body, sprinting and stamina.
- Lune tests that play the same runs at 30, 60, 144 and 240 frames per second and at uneven frame times and compare them with 960.
- A demo place built by `tools/build-demo.luau`.
