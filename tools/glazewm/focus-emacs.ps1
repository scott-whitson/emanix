# focus-emacs.ps1 — force-focus the WSLg Emacs window (launched hidden by
# focus-emacs.vbs from a GlazeWM keybinding).
#
# Plain AppActivate/SetForegroundWindow is DENIED by Windows' foreground
# lock when called from a freshly spawned background process (verified
# 2026-08-05 — worked from an idle shell, silently failed from GlazeWM's
# shell-exec while the user was typing). Counter it the standard way:
# attach this thread to the foreground window's input queue, nudge an Alt
# keypress to satisfy the "recent input" heuristic, then SetForegroundWindow.
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class FF {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
}
"@

$w = Get-Process msrdc -ErrorAction SilentlyContinue |
     Where-Object { $_.MainWindowTitle -match 'emacs' } |
     Select-Object -First 1
if (-not $w) { exit 1 }
$h = $w.MainWindowHandle

if ([FF]::IsIconic($h)) { [void][FF]::ShowWindow($h, 9) }  # SW_RESTORE

# Alt down/up — marks this process as having recent input.
[FF]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
[FF]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)             # KEYEVENTF_KEYUP

$fgPid = 0
$fgThread = [FF]::GetWindowThreadProcessId([FF]::GetForegroundWindow(), [ref]$fgPid)
$me = [FF]::GetCurrentThreadId()
[void][FF]::AttachThreadInput($me, $fgThread, $true)
[void][FF]::SetForegroundWindow($h)
[void][FF]::AttachThreadInput($me, $fgThread, $false)
