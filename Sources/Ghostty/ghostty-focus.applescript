on run argv
  set windowId to item 1 of argv
  set tabId to ""
  if (count of argv) > 1 then set tabId to item 2 of argv
  tell application "Ghostty"
    activate window (window id windowId)
    if tabId is not "" then
      select tab (tab id tabId of window id windowId)
    end if
  end tell
end run
