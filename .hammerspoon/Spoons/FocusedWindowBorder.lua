local obj = {}

-- Metadata
obj.name = "FocusedWindowBorder"
obj.version = "1.0"

-- Configuration
--rgba(235, 219, 178)
local borderColor = { red = 0.91796875, green = 0.85546875, blue = 0.6953125, alpha = 0.8 }
local borderWidth = 4
local cornerRadius = 25
local animationDuration = 0.15 -- Animation duration in seconds (0.2-0.5 recommended)

-- List of apps that should not have borders drawn
local excludedApps = {
	"iPhone Mirroring",
	"Raycast",
	"System Settings",
}

-- Global variable to store the border
local focusBorder = nil
local animationTimer = nil
local lastWindowFrame = nil

-- Function to check if an app should be excluded from border drawing
local function shouldExcludeApp(win)
	local app = win:application()
	if not app then
		return true
	end

	local appName = app:name()
	for _, excludedApp in ipairs(excludedApps) do
		if appName == excludedApp then
			return true
		end
	end

	return false
end

-- Function to delete the border
local function deleteBorder()
	if focusBorder then
		focusBorder:delete()
		focusBorder = nil
	end

	-- Stop any ongoing animation
	if animationTimer then
		animationTimer:stop()
		animationTimer = nil
	end
end

-- Function to animate border movement
local function animateBorder(fromFrame, toFrame)
	if animationTimer then
		animationTimer:stop()
	end

	local startTime = hs.timer.secondsSinceEpoch()
	local startFrame = fromFrame or toFrame

	animationTimer = hs.timer.new(0.004, function() -- ~120fps animation
		local elapsed = hs.timer.secondsSinceEpoch() - startTime
		local progress = math.min(elapsed / animationDuration, 1.0)

		-- Use ease-out cubic function for smooth animation
		local easeProgress = 1 - math.pow(1 - progress, 3)

		-- Interpolate between start and end frames
		local currentFrame = {
			x = startFrame.x + (toFrame.x - startFrame.x) * easeProgress,
			y = startFrame.y + (toFrame.y - startFrame.y) * easeProgress,
			w = startFrame.w + (toFrame.w - startFrame.w) * easeProgress,
			h = startFrame.h + (toFrame.h - startFrame.h) * easeProgress,
		}

		if focusBorder then
			focusBorder:setFrame(currentFrame)

			-- Animate transparency during animation
			-- focusBorder:setAlpha(borderColor.alpha * easeProgress)
		end

		if progress >= 1.0 then
			-- Restore original alpha when animation completes
			-- if focusBorder then
			-- 	focusBorder:setAlpha(borderColor.alpha)
			-- end

			animationTimer:stop()
			animationTimer = nil
			lastWindowFrame = toFrame
		end
	end)

	animationTimer:start()
end

-- Function to draw the border
local function drawBorder()
	local win = hs.window.focusedWindow()

	if not win then
		deleteBorder()
		return
	end

	-- Check if the app should be excluded
	if shouldExcludeApp(win) then
		deleteBorder()
		return
	end

	local frame = win:frame()

	-- Adjust frame for border width and padding
	local adjustedFrame = {
		x = frame.x,
		y = frame.y,
		w = frame.w,
		h = frame.h,
	}

	if focusBorder then
		-- Animate from current position to new position
		local currentFrame = focusBorder:frame()
		animateBorder(currentFrame, adjustedFrame)
	else
		-- Create new border and animate from last known position or current position
		focusBorder = hs.drawing.rectangle(adjustedFrame)
		focusBorder:setStrokeColor(borderColor)
		focusBorder:setStrokeWidth(borderWidth)
		focusBorder:setRoundedRectRadii(cornerRadius, cornerRadius)
		focusBorder:setFill(false)
		-- Set window level to appear above windows but below dock and menubar
		focusBorder:setLevel(hs.drawing.windowLevels.utility)
		focusBorder:show()

		-- If we have a last known frame, animate from it
		if lastWindowFrame then
			animateBorder(lastWindowFrame, adjustedFrame)
		else
			lastWindowFrame = adjustedFrame
		end
	end
end

-- Function to handle window unfocusing (store position for animation)
local function onWindowUnfocused(win)
	if focusBorder then
		-- Store the current border position for animation to next window
		lastWindowFrame = focusBorder:frame()
		-- Don't delete the border immediately - let the new focus handle it
	end
end

-- Event listener for window focus changes
local windowFilter = hs.window.filter.new()
windowFilter:subscribe(hs.window.filter.windowFocused, drawBorder)
windowFilter:subscribe(hs.window.filter.windowUnfocused, onWindowUnfocused)
windowFilter:subscribe(hs.window.filter.windowDestroyed, deleteBorder)
windowFilter:subscribe(hs.window.filter.windowMoved, drawBorder)
windowFilter:subscribe(hs.window.filter.windowMinimized, deleteBorder)
windowFilter:subscribe(hs.window.filter.windowHidden, deleteBorder)
windowFilter:subscribe(hs.window.filter.windowUnminimized, drawBorder)
windowFilter:subscribe(hs.window.filter.windowUnhidden, drawBorder)

return obj
