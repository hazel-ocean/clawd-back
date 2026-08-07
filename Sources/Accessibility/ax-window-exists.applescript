on run argv
  set pid to (item 1 of argv) as integer
  set windowTitle to item 2 of argv
  tell application "System Events"
    tell process id pid
      if exists window windowTitle then
        return "true"
      else
        return "false"
      end if
    end tell
  end tell
end run
