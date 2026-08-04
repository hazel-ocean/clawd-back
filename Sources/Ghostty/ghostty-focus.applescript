on run argv
  set windowId to item 1 of argv
  set tabId to ""
  if (count of argv) > 1 then set tabId to item 2 of argv
  tell application "Ghostty"
    -- `focus` runs LAST so the terminal surface ends as first responder
    -- (else keystrokes hit no key surface and the bell rings); the earlier
    -- `select tab` is the belt-and-suspenders tab guarantee.
    if tabId is not "" then
      select tab (tab id tabId of window id windowId)
      focus (first terminal of tab id tabId of window id windowId)
    else
      focus (first terminal of window id windowId)
    end if
  end tell
end run
