on run argv
  set windowId to item 1 of argv
  tell application "Ghostty"
    if exists window id windowId then
      return "true"
    else
      return "false"
    end if
  end tell
end run
