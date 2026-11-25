Option Explicit

Dim shell, fso, procEnv, userEnv
Dim exePath, proxyUrl, noProxy, cdpFlag, cmd, i, arg, extraArgs

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

exePath = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%\Programs\antigravity\Antigravity.exe")
If Not fso.FileExists(exePath) Then
  exePath = shell.ExpandEnvironmentStrings("%ProgramFiles%\antigravity\Antigravity.exe")
End If
If Not fso.FileExists(exePath) Then
  MsgBox "Antigravity.exe not found. Please install Google Antigravity first." & vbCrLf & exePath, vbExclamation, "Antigravity No-TUN Launcher"
  WScript.Quit 1
End If

Set procEnv = shell.Environment("PROCESS")
Set userEnv = shell.Environment("USER")

' Local proxy URL (override via ANTIGRAVITY_PROXY_URL environment variable; default Clash/Mihomo 7897)
proxyUrl = Trim(procEnv("ANTIGRAVITY_PROXY_URL"))
If proxyUrl = "" Then proxyUrl = Trim(userEnv("ANTIGRAVITY_PROXY_URL"))
If proxyUrl = "" Then proxyUrl = "http://127.0.0.1:7897"

' Inherit existing user NO_PROXY so LAN / private / Tailscale direct rules remain intact
noProxy = Trim(procEnv("NO_PROXY"))
If noProxy = "" Then noProxy = Trim(userEnv("NO_PROXY"))
If noProxy = "" Then
  noProxy = "localhost,127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,100.64.0.0/10"
End If

' Optional: disable CDP port flag by setting ANTIGRAVITY_DISABLE_CDP=1
cdpFlag = " --remote-debugging-port=0"
If Trim(procEnv("ANTIGRAVITY_DISABLE_CDP")) = "1" Or Trim(userEnv("ANTIGRAVITY_DISABLE_CDP")) = "1" Then
  cdpFlag = ""
End If

' Process-scoped proxy variables (inherited by Electron main, Node.js, Go language_server, and CLI)
procEnv("HTTP_PROXY") = proxyUrl
procEnv("http_proxy") = proxyUrl
procEnv("HTTPS_PROXY") = proxyUrl
procEnv("https_proxy") = proxyUrl
procEnv("ALL_PROXY") = proxyUrl
procEnv("all_proxy") = proxyUrl
procEnv("NO_PROXY") = noProxy
procEnv("no_proxy") = noProxy
procEnv("NODE_USE_ENV_PROXY") = "1"
On Error Resume Next
procEnv.Remove "ELECTRON_RUN_AS_NODE"
On Error GoTo 0

' Forward any extra CLI arguments (e.g., workspace folder dropped onto the shortcut)
extraArgs = ""
For i = 0 To WScript.Arguments.Count - 1
  arg = WScript.Arguments(i)
  extraArgs = extraArgs & " """ & Replace(arg, """", """""") & """"
Next

cmd = """" & exePath & """ --proxy-server=""" & proxyUrl & """ --proxy-bypass-list=""" & noProxy & """ --disable-quic" & cdpFlag & extraArgs
shell.Run cmd, 1, False
