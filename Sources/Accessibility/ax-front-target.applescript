on run argv
  set pid to (item 1 of argv) as integer
  tell application "System Events"
    tell process id pid
      set wins to windows whose subrole is "AXStandardWindow"
      if (count of wins) = 0 then return ""
      return title of item 1 of wins
    end tell
  end tell
end run
