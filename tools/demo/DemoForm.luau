--!strict
-- Which of the demo screen's two layouts to use. The touch one keeps the
-- bottom-left corner free for Roblox's thumbstick: the panel and the sliders
-- stack, with the sliders folded until asked for, and the motion monitor and
-- the third-person view sit at the top right.

local UserInputService = game:GetService("UserInputService")

return {
	touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled,
}
