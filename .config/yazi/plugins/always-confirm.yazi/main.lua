-- ~/.config/yazi/plugins/always-confirm.yazi/init.lua

local function entry()
	-- Prompt a native confirmation dialog box in the center of the screen
	local confirm = ya.confirm({
		pos = { "center", w = 40, h = 10 },
		title = "Quit Yazi?",
		body = "Are you absolutely sure you want to exit?",
	})

	-- If the user hits 'y' / Confirms, tell Yazi to exit cleanly
	if confirm then
		ya.manager_emit("quit", {})
	end
end

return { entry = entry }
