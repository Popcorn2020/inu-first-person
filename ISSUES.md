# Issues

Known problems with InuFirstPerson, what has not been tried, and ideas. Each item says what happens and when. Remove an item in the change that fixes it, and note the fix in `CHANGELOG.md`.

## Known problems

- Holding a Tool and looking far down opens a gap between the right arm, which is drawn where the real arm is, and the shoulder of the body copy.
- `stamina.jumpCost` takes stamina for each jump but does not stop a jump when there is not enough.
- A platform moved by setting its CFrame lifts the character without a velocity, so the view trails it by up to `stepSmoothing.maxOffset` until it stops. Platforms moved by physics are followed as they are.
- Changes to the character's colors and size show on the body copy only after `body.rebuild()`.
- With a toggle mode, turning from one move key to another (W released a frame before D is pressed) stops sprinting for that frame, so `sprintChanged` fires twice.
- While zooming between 0.5 and 1 stud, the real character and the body copy may show together for a moment. Not yet seen in play.

## Not tried

- VR. The body copy hides and the motion is scaled by `camera.vrScale`, which is 0 by default.
- Characters driven by a ControllerManager (the Character Controller Library). Sprinting writes `Humanoid.WalkSpeed`, which may not move them; the module warns once.
- Server Authority (`Workspace.AuthorityMode` set to Server). Sprinting sets the walking speed on the client.

## Ideas

- Arms that reach for things (IK), built on `body.setPoseCallback`.
- Crouching.
- Signals for landing (with the fall speed) and for footsteps (on the bob's beat), for sounds and effects that should match the view.
