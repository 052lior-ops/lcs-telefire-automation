$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class MouseNative {
    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")]
    public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extraInfo);
    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")]
    public static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extraInfo);
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();

    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT {
        public uint type;
        public InputUnion U;
    }
    [StructLayout(LayoutKind.Explicit)]
    public struct InputUnion {
        [FieldOffset(0)] public KEYBDINPUT ki;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct KEYBDINPUT {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }
    [DllImport("user32.dll", SetLastError=true)]
    public static extern uint SendInput(uint count, INPUT[] inputs, int size);

    public static void SendUnicodeText(string text) {
        foreach (char ch in text) {
            INPUT down = new INPUT();
            down.type = 1;
            down.U.ki.wScan = ch;
            down.U.ki.dwFlags = 0x0004;
            INPUT up = down;
            up.U.ki.dwFlags = 0x0004 | 0x0002;
            INPUT[] pair = new INPUT[] { down, up };
            SendInput(2, pair, Marshal.SizeOf(typeof(INPUT)));
        }
    }
}
"@

[MouseNative]::SetProcessDPIAware() | Out-Null

$DescriptionX = 775
$DescriptionY = 288
$DeviceTypeX = 1240
$DeviceTypeY = 288
$SaveX = 1095
$SaveY = 844
$Address1X = 1340
$Address1Y = 293
$ProgrammedCheckX = 1050
$ProgrammedCheckY = 288
$NextAddressX = 965
$NextAddressY = 844

$PhotoAddresses  = @(1,5,6,7,10,14,15,18,19,20,21,22,28,29,30,31,37,38,39,40,46,47,51,56,57,58,59,65,66,67,68)
$SwitchAddresses = @(2,11,23,32,41,48,60,69)
$SirenAddresses  = @(3,4,12,13,26,27,35,36,44,45,49,50,63,64,72,73)
$LampAddresses   = @(8,9,16,17,24,25,33,34,42,43,52,61,62,70,71)

function Click-At([int]$x, [int]$y) {
    [MouseNative]::SetCursorPos($x, $y) | Out-Null
    Start-Sleep -Milliseconds 120
    [MouseNative]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
    [MouseNative]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
}

function DoubleClick-At([int]$x, [int]$y) {
    Click-At $x $y
    Start-Sleep -Milliseconds 110
    Click-At $x $y
}

function Stop-Requested {
    return (([MouseNative]::GetAsyncKeyState(0x1B) -band 0x8000) -ne 0)
}

function Press-Key([byte]$key) {
    [MouseNative]::keybd_event($key, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 35
    [MouseNative]::keybd_event($key, 0, 2, [UIntPtr]::Zero)
}

function Press-CtrlKey([byte]$key) {
    [MouseNative]::keybd_event(0x11, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 35
    Press-Key $key
    Start-Sleep -Milliseconds 35
    [MouseNative]::keybd_event(0x11, 0, 2, [UIntPtr]::Zero)
}

function Press-ShiftKey([byte]$key) {
    [MouseNative]::keybd_event(0x10, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    Press-Key $key
    Start-Sleep -Milliseconds 60
    [MouseNative]::keybd_event(0x10, 0, 2, [UIntPtr]::Zero)
}

function Get-TypeIndex([int]$address) {
    if ($PhotoAddresses -contains $address)  { return 0 }
    if ($SwitchAddresses -contains $address) { return 4 }
    if ($SirenAddresses -contains $address)  { return 6 }
    if ($LampAddresses -contains $address)   { return 7 }
    return $null
}

function Select-DeviceType([int]$index) {
    Click-At $DeviceTypeX $DeviceTypeY
    Start-Sleep -Milliseconds 250
    Press-Key 0x24
    Start-Sleep -Milliseconds 100
    for ($i = 0; $i -lt $index; $i++) {
        Press-Key 0x28
        Start-Sleep -Milliseconds 65
    }
    Press-Key 0x0D
}

function Clear-And-TypeDescription([string]$text) {
    Click-At $DescriptionX $DescriptionY
    Press-Key 0x23
    for ($i = 0; $i -lt 60; $i++) { Press-Key 0x08 }
    Press-Key 0x24
    for ($i = 0; $i -lt 60; $i++) { Press-Key 0x2E }
    [System.Windows.Forms.Clipboard]::SetText($text)
    Start-Sleep -Milliseconds 150
    Press-ShiftKey 0x2D
}

$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
if (($screen.Width -ne 1920) -or ($screen.Height -ne 1080)) {
    [System.Windows.Forms.MessageBox]::Show(
        "Required screen resolution: 1920x1080. Current: $($screen.Width)x$($screen.Height).",
        "Telefire automation"
    ) | Out-Null
    exit 1
}

$xlsx = Get-ChildItem -LiteralPath $PSScriptRoot -Filter "*.xlsx" | Select-Object -First 1
if (-not $xlsx) {
    [System.Windows.Forms.MessageBox]::Show(
        "The Excel file is missing from this folder.",
        "Telefire automation"
    ) | Out-Null
    exit 1
}

$choice = [System.Windows.Forms.MessageBox]::Show(
    "YES = test address 001 only.`r`nNO = enter all addresses.`r`nCANCEL = exit.`r`n`r`nKeep the Telefire device list open with address 001 visible. The automation will double-click address 001. Press ESC at any time to stop.",
    "Telefire automation",
    [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
    [System.Windows.Forms.MessageBoxIcon]::Question
)

if ($choice -eq [System.Windows.Forms.DialogResult]::Cancel) { exit 0 }
$testOnly = ($choice -eq [System.Windows.Forms.DialogResult]::Yes)

$excel = $null
$workbook = $null
$sheet = $null

try {
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false
    $workbook = $excel.Workbooks.Open($xlsx.FullName, 0, $true)
    $sheet = $workbook.Worksheets.Item(1)
    $usedRows = $sheet.UsedRange.Rows.Count

    [System.Windows.Forms.MessageBox]::Show(
        "Click OK, then do not touch the mouse or keyboard. Automation starts in 5 seconds. Press ESC to stop.",
        "Telefire automation"
    ) | Out-Null
    Start-Sleep -Seconds 5

    DoubleClick-At $Address1X $Address1Y
    Start-Sleep -Milliseconds 1100

    for ($row = 3; $row -le $usedRows; $row++) {
        if (Stop-Requested) { throw "Stopped by user." }

        $addressValue = $sheet.Cells.Item($row, 2).Value2
        if ($null -eq $addressValue) { continue }
        $address = [int]$addressValue
        $description = [string]$sheet.Cells.Item($row, 3).Value2

        if ([string]::IsNullOrWhiteSpace($description)) {
            if (-not $testOnly -and $address -lt 73) {
                Click-At $NextAddressX $NextAddressY
                Start-Sleep -Milliseconds 550
            }
            continue
        }

        $typeIndex = Get-TypeIndex $address
        if ($null -eq $typeIndex) { throw "No device type mapping for address $address." }

        Select-DeviceType $typeIndex
        Start-Sleep -Milliseconds 250

        # Test mode programs address 001. Full mode assumes address 001 passed the test,
        # and programs each remaining address exactly once.
        if ($testOnly -or $address -gt 1) {
            Click-At $ProgrammedCheckX $ProgrammedCheckY
            Start-Sleep -Milliseconds 300
        }

        Clear-And-TypeDescription $description
        Start-Sleep -Milliseconds 300

        Click-At $SaveX $SaveY
        Start-Sleep -Milliseconds 650

        if ($testOnly) { break }
        if ($address -lt 73) {
            Click-At $NextAddressX $NextAddressY
            Start-Sleep -Milliseconds 550
        }
    }

    if ($testOnly) {
        [System.Windows.Forms.MessageBox]::Show(
            "Test completed for address 001. Check the description and device type before running FULL mode.",
            "Telefire automation"
        ) | Out-Null
    } else {
        [System.Windows.Forms.MessageBox]::Show(
            "Full entry completed. Addresses with blank descriptions were skipped.",
            "Telefire automation"
        ) | Out-Null
    }
}
catch {
    [System.Windows.Forms.MessageBox]::Show(
        $_.Exception.Message,
        "Telefire automation stopped",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
}
finally {
    if ($workbook) { $workbook.Close($false) }
    if ($excel) { $excel.Quit() }
    if ($sheet) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($sheet) }
    if ($workbook) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($workbook) }
    if ($excel) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($excel) }
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
}
