---Custom linemode showing the file size followed by its modification time.
---Times from the current year show "Mon DD HH:MM"; older ones show "Mon DD  YYYY".
---@return string line The formatted "<size> <mtime>" text for the file row.
function Linemode:size_and_mtime()
	local time = math.floor(self._file.cha.mtime or 0)
	if time == 0 then
		time = ""
	elseif os.date("%Y", time) == os.date("%Y") then
		time = os.date("%b %d %H:%M", time)
	else
		time = os.date("%b %d  %Y", time)
	end

	local size = self._file:size()
	return string.format("%s %s", size and ya.readable_size(size) or "-", time)
end

-- Share yanked (copied/cut) files across all running Yazi instances,
-- so files yanked in one instance can be pasted in another.
require("session"):setup {
	sync_yanked = true,
}
