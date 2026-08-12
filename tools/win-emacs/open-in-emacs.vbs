' open-in-emacs.vbs — Windows side of the "open this file in the WSL Emacs"
' handler. Explorer runs this (via a file association or the "Open in Emacs"
' context-menu verb); it hands the path to the WSL daemon, then raises the
' WSLg window.
'
' VBScript rather than .cmd purely to avoid a console window flashing on every
' open — same reason, and same shape, as focus-emacs.vbs next door.
'
' Deployed copy lives at %LOCALAPPDATA%\EmacsWSL\open-in-emacs.vbs; the source
' of truth is dotfiles/tools/win-emacs/. Re-run install.sh after editing.
'
' It must NOT run off \\wsl.localhost — Explorer could not read the script
' while the distro is stopped, which is exactly when you need it to boot it.

If WScript.Arguments.Count = 0 Then WScript.Quit 1

Dim path, ws
path = WScript.Arguments(0)
Set ws = CreateObject("WScript.Shell")

' Hand the file to the running daemon. Wait (3rd arg True) so the file is open
' before we try to focus the window — otherwise we race the frame's creation.
ws.Run "C:\Windows\System32\wsl.exe -d whistle -e /home/scott/dotfiles/tools/win-emacs/open-in-emacs.sh """ & path & """", 0, True

' Raise the WSLg Emacs window. Reuses the already-deployed force-focus script:
' plain SetForegroundWindow is denied by the foreground lock when called from a
' freshly spawned process — see focus-emacs.ps1 for the full explanation.
ws.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""C:\Users\swhitson.CENTRALDATA\.glzr\glazewm\focus-emacs.ps1""", 0, False
