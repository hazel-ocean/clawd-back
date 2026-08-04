tell application "Ghostty"
  set w to front window
  set wid to id of w
  set tid to id of selected tab of w
end tell
-- Build the separator OUTSIDE the tell block: inside it, `tab` resolves to
-- Ghostty's tab class (dictionary term), not AppleScript's tab character.
return wid & tab & tid
