# Issues

Known problems with InuFirstPerson, what has not been tried, and ideas. Each item says what happens and when. Remove an item in the change that fixes it, and note the fix in `CHANGELOG.md`.

## Known problems

- The look turns the joints before physics, so heads, waists and the Tool arm follow the view one frame late. The Tool's aim trails by that frame on top of `look.toolAimLag`.
- Seated or climbing, the body does not turn, and turning the view past what the head reaches keeps turning the eye about the neck, so looking right behind puts the eye behind the neck. The head is hidden, so it shows only as a view from a little further back.
- `stamina.jumpCost` takes stamina for each jump but does not stop a jump when there is not enough.
- A platform moved by setting its CFrame lifts the character without a velocity, so the view trails it by up to `stepSmoothing.maxOffset` until it stops. Platforms moved by physics are followed as they are.
- With a toggle mode, turning from one move key to another (W released a frame before D is pressed) stops sprinting for that frame, so `sprintChanged` fires twice.

## Not tried

- VR. The body is left as the default camera shows it, and the motion is scaled by `camera.vrScale`, which is 0 by default.
- Characters driven by a ControllerManager (the Character Controller Library). Sprinting writes `Humanoid.WalkSpeed`, which may not move them; the module warns once.
- Server Authority (`Workspace.AuthorityMode` set to Server). Sprinting sets the walking speed on the client.

## Ideas

- Arms that reach for things (IK), built on `look.setPoseCallback`.
- Crouching.
- Signals for landing (with the fall speed) and for footsteps (on the bob's beat), for sounds and effects that should match the view.
