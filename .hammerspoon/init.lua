-- Dock autohide

-- Check if external displays are connected
local function hasExternalDisplay()
    local primary = hs.screen.primaryScreen()
    for _, screen in ipairs(hs.screen.allScreens()) do
        if screen ~= primary then
            return true
        end
    end
    return false
end

-- Estimate Dock frame (assuming it's always at bottom)
local dockProximity = 20

local function getDockFrame()
    local screen = hs.screen.primaryScreen()
    local fullFrame = screen:fullFrame()
    local usableFrame = screen:frame()

    local dockHeight = fullFrame.h - usableFrame.h
    return {
        x = usableFrame.x,
        y = usableFrame.y + usableFrame.h,
        w = usableFrame.w,
        h = dockHeight
    }
end

-- Check if two rectangles intersect
local function rectsIntersect(r1, r2)
    local r1Bottom = r1.y + r1.h + dockProximity
    local r2Top = r2.y

    return r1Bottom > r2Top
end

-- Maximize height if window is at top of screen
local function maximizeHeightIfAtTop(win)
    if not win then return end
  
    local frame = win:frame()
    local screenFrame = win:screen():frame()
  
    if frame.y == screenFrame.y then
      frame.h = screenFrame.h
      win:setFrame(frame)
    end
  end

-- Set Dock auto-hide if not already set
local lastDockState = nil
local function setDockAutohide(enable)
    if lastDockState == enable then return end
    lastDockState = enable

    local script = string.format([[
        tell application "System Events" to set the autohide of the dock preferences to %s
    ]], enable and "true" or "false")

    hs.osascript.applescript(script)
end

-- Monitor windows for overlap with Dock
local function monitorWindows()
    local dockFrame = getDockFrame()

    local function checkWindows()
        local windows = hs.window.visibleWindows()
        for _, win in ipairs(windows) do
            if win:isStandard() and win:screen() == hs.screen.primaryScreen() then
                if rectsIntersect(win:frame(), dockFrame) then
                    setDockAutohide(true)
                    maximizeHeightIfAtTop(win)
                    return
                end
            end
        end
        setDockAutohide(false)
    end

    local wf = hs.window.filter.new()
    wf:subscribe({
        "windowCreated",
        "windowDestroyed",
        "windowMoved",
        "windowFocused",
        "windowMinimized",
        "windowUnminimized",
    }, function()
        hs.timer.doAfter(0.0, checkWindows)
    end)

    checkWindows()
end

-- Main
if not hasExternalDisplay() then
    monitorWindows()
else
    hs.alert.show("External display detected; skipping Dock monitoring.")
end