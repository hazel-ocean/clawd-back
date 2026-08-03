on run argv
  set windowId to item 1 of argv
  set tabId to ""
  if (count of argv) > 1 then set tabId to item 2 of argv
  tell application "Ghostty"
    -- `focus` lands the exact window (Ghostty-native, unlike AppKit `activate
    -- window`); the explicit `select tab` guarantees the tab even in cases
    -- where focus's implicit tab switch doesn't hold.
    if tabId is not "" then
      focus (first terminal of tab id tabId of window id windowId)
      select tab (tab id tabId of window id windowId)
    else
      focus (first terminal of window id windowId)
    end if
  end tell
end run
