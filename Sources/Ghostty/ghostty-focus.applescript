on run argv
  set windowId to item 1 of argv
  set tabId to ""
  if (count of argv) > 1 then set tabId to item 2 of argv
  tell application "Ghostty"
    -- `focus` targets the exact surface, bringing its window to front and
    -- selecting its tab in one verb; unlike AppKit `activate window` it is
    -- Ghostty-native, so it can land the right window among many.
    if tabId is not "" then
      focus (first terminal of tab id tabId of window id windowId)
    else
      focus (first terminal of window id windowId)
    end if
  end tell
end run
