# refresh-assoc.ps1 — tell Explorer that file associations changed.
#
# Without this, newly written associations are ignored until the next logon or
# explorer.exe restart, which makes a correct install look broken.
Add-Type -Namespace Win32 -Name Shell -MemberDefinition @"
[DllImport("shell32.dll")]
public static extern void SHChangeNotify(int eventId, uint flags, IntPtr item1, IntPtr item2);
"@
# SHCNE_ASSOCCHANGED, SHCNF_IDLIST
[Win32.Shell]::SHChangeNotify(0x08000000, 0x0000, [IntPtr]::Zero, [IntPtr]::Zero)
