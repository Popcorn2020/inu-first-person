# Issues

Known problems with InuFirstPerson, what has not been tried, and ideas. Each item says what happens and when. Remove an item in the change that fixes it, and note the fix in `CHANGELOG.md`.

## Known problems

- Holding a Tool and looking far down opens a gap between the right arm, which is drawn where the real arm is, and the shoulder of the body copy.
- `stamina.jumpCost` takes stamina for each jump but does not stop a jump when there is not enough.
- A platform moved by setting its CFrame lifts the character without a velocity, so the view trails it by up to `stepSmoothing.maxOffset` until it stops. Platforms moved by physics are followed as they are.
- Changes to the character's colors and size show on the body copy only after `body.rebuild()`.

## Not tried

- VR. The body copy hides and the motion is scaled by `camera.vrScale`, which is 0 by default.
- Characters driven by a ControllerManager (the Character Controller Library). Sprinting writes `Humanoid.WalkSpeed`, which may not move them; the module warns once.
- Server Authority (`Workspace.AuthorityMode` set to Server). Sprinting sets the walking speed on the client.

## Ideas

- Arms that reach for things (IK), built on `body.setPoseCallback`.
- Crouching.
