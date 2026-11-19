<#
Show a persistent Windows toast that survives in the notification center.

Clicking the toast body copies $Copy (base64url encoded in the launch URI) and,
when the copied text is a URL, also opens it in the default browser.

The click handler must be a GUI-subsystem binary: launching powershell.exe from
a protocol URI flashes a console window, so it is compiled once into
%LOCALAPPDATA%\log-notify\LogNotifyOpen.exe on first use.
#>
param(
  [Parameter(Mandatory = $true)][string]$TitleB64,
  [Parameter(Mandatory = $true)][string]$BodyB64,
  [string]$CopyB64 = ''
)

$ErrorActionPreference = 'Stop'
$Aumid = 'Specter.LogNotify'
$Root = Join-Path $env:LOCALAPPDATA 'log-notify'
$Exe = Join-Path $Root 'LogNotifyOpen.exe'

function ConvertFrom-B64Url([string]$s) {
  if (-not $s) { return '' }
  $t = $s.Replace('-', '+').Replace('_', '/')
  $t += '=' * ((4 - $t.Length % 4) % 4)
  return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($t))
}

function ConvertTo-B64Url([string]$s) {
  return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($s)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function EscapeXml([string]$s) {
  return [System.Security.SecurityElement]::Escape($s)
}

if (-not (Test-Path $Root)) { New-Item -ItemType Directory -Force -Path $Root | Out-Null }

if (-not (Test-Path $Exe)) {
  $source = @'
using System;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

static class LogNotifyOpen
{
    [STAThread]
    static int Main(string[] args)
    {
        if (args.Length < 1) return 2;
        Match m = Regex.Match(args[0], @"^lognotify:(?<payload>[A-Za-z0-9_-]+)$");
        if (!m.Success) return 2;

        string b64 = m.Groups["payload"].Value.Replace('-', '+').Replace('_', '/');
        b64 = b64.PadRight(b64.Length + (4 - b64.Length % 4) % 4, '=');
        string text = Encoding.UTF8.GetString(Convert.FromBase64String(b64));

        for (int i = 0; i < 20; i++)
        {
            try { Clipboard.SetText(text); break; }
            catch (Exception) { Thread.Sleep(50); }
        }

        if (text.StartsWith("http://") || text.StartsWith("https://"))
        {
            try { System.Diagnostics.Process.Start(text); } catch (Exception) { }
        }
        return 0;
    }
}
'@
  Add-Type -TypeDefinition $source -OutputAssembly $Exe -OutputType WindowsApplication -ReferencedAssemblies System.Windows.Forms
}

$SchemeKey = 'HKCU:\Software\Classes\lognotify'
$CmdKey = "$SchemeKey\shell\open\command"
$CmdValue = '"' + $Exe + '" "%1"'
if ((Get-ItemProperty -Path $CmdKey -ErrorAction SilentlyContinue).'(default)' -ne $CmdValue) {
  New-Item -Path $SchemeKey -Force | Out-Null
  Set-ItemProperty -Path $SchemeKey -Name '(default)' -Value 'URL:Log Notify'
  New-ItemProperty -Path $SchemeKey -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null
  New-Item -Path $CmdKey -Force | Out-Null
  Set-ItemProperty -Path $CmdKey -Name '(default)' -Value $CmdValue
}

$AumidKey = "HKCU:\Software\Classes\AppUserModelId\$Aumid"
if (-not (Test-Path $AumidKey)) { New-Item -Path $AumidKey -Force | Out-Null }
Set-ItemProperty -Path $AumidKey -Name 'DisplayName' -Value 'Log Notify'

[void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
[void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]

$title = ConvertFrom-B64Url $TitleB64
$body = ConvertFrom-B64Url $BodyB64
$copy = if ($CopyB64) { ConvertFrom-B64Url $CopyB64 } else { $body }
$payload = ConvertTo-B64Url $copy

$xml = '<toast activationType="protocol" launch="lognotify:' + $payload + '">' +
  '<visual><binding template="ToastGeneric"><text>' + (EscapeXml $title) +
  '</text><text>' + (EscapeXml $body) + '</text></binding></visual></toast>'

$doc = New-Object Windows.Data.Xml.Dom.XmlDocument
$doc.LoadXml($xml)
$toast = New-Object Windows.UI.Notifications.ToastNotification $doc
$toast.ExpirationTime = [DateTimeOffset]::Now.AddDays(7)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($Aumid).Show($toast)
