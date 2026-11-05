-- ~/.config/yazi/plugins/always-confirm.yazi/main.lua

local function entry()
	-- 1. Trigger the visual prompt window
	local confirm = ya.confirm({
		pos = { "center", w = 45, h = 10 },
		title = "Quit Yazi?",
		body = "Are you absolutely sure you want to exit?",
	})

	-- 2. If 'Yes' is pressed, trigger quit globally using the correct syntax
	if confirm then
		ya.emit("quit", {})
	end
end

return { entry = entry }
