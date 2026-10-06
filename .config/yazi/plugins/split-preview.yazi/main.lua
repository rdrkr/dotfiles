--- @since 26.5.6

---Seconds to wait after toggling split mode before opening the preview, giving
---split-tabs time to create/switch the second tab (an immediate call is lost).
local PREVIEW_DELAY = 0.3

---Toggles split-tabs dual-pane mode and, when entering it, enables the preview pane.
---Runs async so it can sleep between the two split-tabs calls. When leaving split
---mode the delayed spl_preview call is a no-op inside split-tabs (no active state).
---@param _ table Plugin state (unused).
---@param _job table Job info from the keymap (unused).
local function entry(_, _job)
	ya.emit("plugin", { "split-tabs", "spl_toggle" })
	ya.sleep(PREVIEW_DELAY)
	ya.emit("plugin", { "split-tabs", "spl_preview" })
end

return { entry = entry }
