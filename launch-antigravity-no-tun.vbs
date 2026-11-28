Option Explicit

Dim shell, fso, procEnv, userEnv
Dim exePath, proxyUrl, hostPort, httpProxyUrl, socksProxyUrl, chromiumProxyUrl
Dim noProxy, chromiumBypass, cdpFlag, webrtcFlag, proxyFlags, cmd
Dim tunActive, forceProxy, dryRun, i, arg, extraArgs

Function StripScheme(ByVal u)
  Dim p
  u = Trim(u)
  p = InStr(u, "://")
  If p > 0 Then
    u = Mid(u, p + 3)
  End If
  Do While Len(u) > 0 And Right(u, 1) = "/"
    u = Left(u, Len(u) - 1)
  Loop
  StripScheme = u
End Function

Function FormatChromiumBypass(ByVal rawNoProxy)
  Dim parts, idx, token, outList
  rawNoProxy = Replace(rawNoProxy, ";", ",")
  parts = Split(rawNoProxy, ",")
  outList = "<local>"
  For idx = 0 To UBound(parts)
    token = Trim(parts(idx))
    If token <> "" Then
      If token = "::1" Then token = "[::1]"
      outList = outList & ";" & token
    End If
  Next
  FormatChromiumBypass = outList
End Function

Function IsTunAdapterActive()
  On Error Resume Next
  Dim wmi, adapters, nic, info
  IsTunAdapterActive = False
  Set wmi = GetObject("winmgmts:\\.\root\cimv2")
  If Err.Number <> 0 Then
    Err.Clear
    On Error GoTo 0
    Exit Function
  End If
  Set adapters = wmi.ExecQuery("SELECT Name, Description, NetConnectionID FROM Win32_NetworkAdapter WHERE NetConnectionStatus = 2")
  If Err.Number <> 0 Then
    Err.Clear
    On Error GoTo 0
    Exit Function
  End If
  For Each nic In adapters
    info = LCase(CStr("" & nic.Name & " " & nic.Description & " " & nic.NetConnectionID))
    If InStr(info, "mihomo") > 0 Or InStr(info, "clash") > 0 Or InStr(info, "meta") > 0 _
       Or InStr(info, "wintun") > 0 Or InStr(info, "sing-box") > 0 Or InStr(info, "utun") > 0 Then
      IsTunAdapterActive = True
      Exit For
    End If
  Next
  On Error GoTo 0
End Function

Sub ClearProxyEnv(ByRef envObj)
  Dim keys, k
  keys = Array("HTTP_PROXY", "http_proxy", "HTTPS_PROXY", "https_proxy", "ALL_PROXY", "all_proxy", "NODE_USE_ENV_PROXY")
  On Error Resume Next
  For Each k In keys
    envObj.Remove k
    Err.Clear
  Next
  On Error GoTo 0
End Sub

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

hostPort = StripScheme(proxyUrl)
If hostPort = "" Then hostPort = "127.0.0.1:7897"
httpProxyUrl = "http://" & hostPort
socksProxyUrl = "socks5h://" & hostPort

' Chromium full-duplex streaming works best over SOCKS5 (override via ANTIGRAVITY_CHROMIUM_PROXY_URL)
chromiumProxyUrl = Trim(procEnv("ANTIGRAVITY_CHROMIUM_PROXY_URL"))
If chromiumProxyUrl = "" Then chromiumProxyUrl = Trim(userEnv("ANTIGRAVITY_CHROMIUM_PROXY_URL"))
If chromiumProxyUrl = "" Then chromiumProxyUrl = "socks5://" & hostPort

' Inherit existing user NO_PROXY so LAN / private / Tailscale direct rules remain intact
noProxy = Trim(procEnv("NO_PROXY"))
If noProxy = "" Then noProxy = Trim(userEnv("NO_PROXY"))
If noProxy = "" Then
  noProxy = "localhost,127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,100.64.0.0/10,.ts.net,*.ts.net"
End If
chromiumBypass = FormatChromiumBypass(noProxy)

' Optional: disable CDP port flag by setting ANTIGRAVITY_DISABLE_CDP=1
cdpFlag = " --remote-debugging-port=0"
If Trim(procEnv("ANTIGRAVITY_DISABLE_CDP")) = "1" Or Trim(userEnv("ANTIGRAVITY_DISABLE_CDP")) = "1" Then
  cdpFlag = ""
End If

' Auto-detect active TUN adapter unless ANTIGRAVITY_FORCE_PROXY=1 is set
forceProxy = (Trim(procEnv("ANTIGRAVITY_FORCE_PROXY")) = "1" Or Trim(userEnv("ANTIGRAVITY_FORCE_PROXY")) = "1")
If Trim(procEnv("ANTIGRAVITY_SIMULATE_TUN")) = "1" Then
  tunActive = True
ElseIf forceProxy Then
  tunActive = False
Else
  tunActive = IsTunAdapterActive()
End If

On Error Resume Next
procEnv.Remove "ELECTRON_RUN_AS_NODE"
On Error GoTo 0

If tunActive Then
  ' TUN mode active: bypass explicit proxy flags so TCP/UDP/QUIC/WebRTC route natively via TUN
  ClearProxyEnv procEnv
  procEnv("NO_PROXY") = noProxy
  procEnv("no_proxy") = noProxy
  proxyFlags = ""
Else
  ' No-TUN mode: HTTP_PROXY for Node/Go language_server, SOCKS5 for Chromium full-duplex streaming
  procEnv("HTTP_PROXY") = httpProxyUrl
  procEnv("http_proxy") = httpProxyUrl
  procEnv("HTTPS_PROXY") = httpProxyUrl
  procEnv("https_proxy") = httpProxyUrl
  procEnv("ALL_PROXY") = socksProxyUrl
  procEnv("all_proxy") = socksProxyUrl
  procEnv("NO_PROXY") = noProxy
  procEnv("no_proxy") = noProxy
  procEnv("NODE_USE_ENV_PROXY") = "1"

  webrtcFlag = " --force-webrtc-ip-handling-policy=disable_non_proxied_udp"
  If Trim(procEnv("ANTIGRAVITY_ALLOW_DIRECT_WEBRTC_UDP")) = "1" Or Trim(userEnv("ANTIGRAVITY_ALLOW_DIRECT_WEBRTC_UDP")) = "1" Then
    webrtcFlag = ""
  End If

  proxyFlags = " --proxy-server=""" & chromiumProxyUrl & """ --proxy-bypass-list=""" & chromiumBypass & """ --disable-quic" & webrtcFlag
End If

' Forward any extra CLI arguments (e.g., workspace folder dropped onto the shortcut)
dryRun = False
extraArgs = ""
For i = 0 To WScript.Arguments.Count - 1
  arg = WScript.Arguments(i)
  If LCase(Trim(arg)) = "--dry-run-print-cmd" Then
    dryRun = True
  Else
    extraArgs = extraArgs & " """ & Replace(arg, """", """""") & """"
  End If
Next

cmd = """" & exePath & """" & proxyFlags & cdpFlag & extraArgs

If dryRun Then
  WScript.Echo "TUN_ACTIVE=" & CStr(tunActive)
  WScript.Echo "HTTP_PROXY=" & procEnv("HTTP_PROXY")
  WScript.Echo "HTTPS_PROXY=" & procEnv("HTTPS_PROXY")
  WScript.Echo "ALL_PROXY=" & procEnv("ALL_PROXY")
  WScript.Echo "NO_PROXY=" & procEnv("NO_PROXY")
  WScript.Echo "CMD=" & cmd
  WScript.Quit 0
End If

shell.Run cmd, 1, False
