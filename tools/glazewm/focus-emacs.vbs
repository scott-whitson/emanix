' focus-emacs.vbs — windowless wrapper (no console flash) that runs
' focus-emacs.ps1 to force-focus the WSLg Emacs window. Bound to a GlazeWM
' keybinding in config.yaml. The real work (and the foreground-lock
' explanation) lives in the .ps1.
Set ws = CreateObject("WScript.Shell")
ws.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""C:\Users\swhitson.CENTRALDATA\.glzr\glazewm\focus-emacs.ps1""", 0, False
