on run argv
  set pid to (item 1 of argv) as integer
  set windowTitle to item 2 of argv
  tell application "System Events"
    tell process id pid
      set frontmost to true
      perform action "AXRaise" of window windowTitle
    end tell
  end tell
end run
