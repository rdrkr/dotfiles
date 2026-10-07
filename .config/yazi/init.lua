---Format a Unix timestamp day-first (European order).
---Times from the current year show "DD/MM HH:MM"; older ones show "DD/MM/YYYY".
---@param time number|nil Unix timestamp in seconds (may be fractional or nil).
---@return string text The formatted date, or "" when the timestamp is missing.
local function format_time(time)
	time = math.floor(time or 0)
	if time == 0 then
		return ""
	elseif os.date("%Y", time) == os.date("%Y") then
		return os.date("%d/%m %H:%M", time)
	else
		return os.date("%d/%m/%Y", time)
	end
end

---Format the file's size, or "-" when it is unknown (e.g. unsized directories).
---@param file table The yazi File object for the row.
---@return string text Human-readable size such as "1.2M".
local function format_size(file)
	local size = file:size()
	return size and ya.readable_size(size) or "-"
end

---Custom linemode showing the file size followed by its modification time.
---@return string line The formatted "<size> <mtime>" text for the file row.
function Linemode:size_and_mtime()
	return string.format("%s %s", format_size(self._file), format_time(self._file.cha.mtime))
end

---Custom linemode showing the file size followed by its birth (creation) time.
---@return string line The formatted "<size> <btime>" text for the file row.
function Linemode:size_and_btime()
	return string.format("%s %s", format_size(self._file), format_time(self._file.cha.btime))
end

---Override of the built-in mtime linemode so dates are day-first (DD/MM) instead of MM/DD.
---@return string line The formatted modification time.
function Linemode:mtime()
	return format_time(self._file.cha.mtime)
end

---Override of the built-in btime linemode so dates are day-first (DD/MM) instead of MM/DD.
---@return string line The formatted birth time.
function Linemode:btime()
	return format_time(self._file.cha.btime)
end

-- Share yanked (copied/cut) files across all running Yazi instances,
-- so files yanked in one instance can be pasted in another.
require("session"):setup({
	sync_yanked = true,
})

require("full-border"):setup({
	type = ui.Border.ROUNDED,
})

-- ya.emit("plugin", { "split-tabs", "spl_activate" })

require("starship"):setup({
	hide_flags = false,
	flags_after_prompt = false,
	-- config_file = "~/.config/starship/starship.toml",
	show_right_prompt = true,
	hide_count = false,
	count_separator = " ",
})

require("confirm-quit"):setup()
