tell application "Ghostty"
  set w to front window
  return (id of w) & tab & (id of selected tab of w)
end tell
