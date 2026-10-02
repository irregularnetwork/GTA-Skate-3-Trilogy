<#
  Vice City Skate - first-run setup and launcher.
  Started by "2 - Play Vice City Skate.bat". On the first run it asks for
  your GTA Vice City folder and your Skate 3 default.xex, copies Vice City
  into Files\game (your install is only read, never changed), adds reVC and
  skate mode, converts the Skate 3 data once, then starts the game. Later
  runs start the game straight away.

  Layout:  <package>\1 - READ ME FIRST.txt
           <package>\2 - Play Vice City Skate.bat
           <package>\Files\bin      reVC + skate mode, laid over the game copy
           <package>\Files\setup    this script and the Skate 3 converter
           <package>\Files\game     the playable copy (made here)

  Options (for the .bat):  -Setup     run the setup again
                           -ViceCity <folder> -Xex <default.xex>   skip the questions
                           -NoLaunch  set up but do not start the game
#>
param(
    [string] $ViceCity,
    [string] $Xex,
    [switch] $Setup,
    [switch] $NoLaunch
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { $Host.UI.RawUI.WindowTitle = 'Vice City Skate' } catch {}

$files = Split-Path -Parent $PSScriptRoot
$package = Split-Path -Parent $files
$bin = Join-Path $files 'bin'
$game = Join-Path $files 'game'
$converter = Join-Path $PSScriptRoot 'iw4l-skate-convert.exe'
$remembered = Join-Path $PSScriptRoot 'paths.txt'

function Say([string] $text, [string] $color = 'Gray') { Write-Host $text -ForegroundColor $color }
function Fail([string] $text) { Say ''; Say $text 'Red'; exit 1 }
function Clean([string] $path) { if (-not $path) { return '' }; return $path.Trim().Trim('"').Trim("'").Trim() }

function Test-ViceCity([string] $dir) {
    if (-not $dir -or -not (Test-Path -LiteralPath $dir -PathType Container)) { return $false }
    foreach ($need in 'models\gta3.img', 'models\gta3.dir', 'data\gta_vc.dat', 'anim\ped.ifp', 'TEXT\american.gxt') {
        if (-not (Test-Path -LiteralPath (Join-Path $dir $need))) { return $false }
    }
    return $true
}

function Find-ViceCity {
    $candidates = New-Object System.Collections.Generic.List[string]
    # Steam libraries
    try {
        $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath
        $libraries = @($steam)
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            foreach ($m in [regex]::Matches((Get-Content -Raw $vdf), '"path"\s+"([^"]+)"')) { $libraries += $m.Groups[1].Value.Replace('\\', '\') }
        }
        foreach ($lib in $libraries) { $candidates.Add((Join-Path $lib 'steamapps\common\Grand Theft Auto Vice City')) }
    } catch {}
    # Rockstar Launcher and retail installs
    foreach ($key in 'HKLM:\SOFTWARE\WOW6432Node\Rockstar Games\Grand Theft Auto Vice City', 'HKLM:\SOFTWARE\Rockstar Games\Grand Theft Auto Vice City') {
        try { $p = Get-ItemProperty $key -ErrorAction Stop; foreach ($name in 'InstallFolder', 'Install Dir', 'InstallDir', 'Path') { if ($p.$name) { $candidates.Add($p.$name) } } } catch {}
    }
foreach ($base in $env:ProgramFiles, ${env:ProgramFiles(x86)}, 'C:\Games', 'D:\Games') {
        if ($base) {
            try {
                $candidates.Add((Join-Path $base 'Rockstar Games\Grand Theft Auto Vice City'))
                $candidates.Add((Join-Path $base 'Grand Theft Auto Vice City'))
            } catch {}
        }
    }
    foreach ($c in $candidates) { if (Test-ViceCity $c) { return (Resolve-Path -LiteralPath $c).Path } }
    return $null
}

$SkateRequired = 'data\big\miscload.big', 'data\big\miscboot.big', 'data\big\db.big', 'data\content\createacharacter.big'

function Resolve-Xex([string] $path) {
    if (-not $path) { return $null }
    if (Test-Path -LiteralPath $path -PathType Container) { $path = Join-Path $path 'default.xex' }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    if ((Split-Path -Leaf $path) -ne 'default.xex') { return $null }
    return (Resolve-Path -LiteralPath $path).Path
}

function Test-SkateData([string] $xex) {
    $dir = Split-Path -Parent $xex
    foreach ($need in $SkateRequired) { if (-not (Test-Path -LiteralPath (Join-Path $dir $need))) { return $need } }
    return $null
}

function Copy-Tree([string] $from, [string] $to, [switch] $NewerOnly) {
    $sourceRoot = (Resolve-Path -LiteralPath $from).Path.TrimEnd([char[]]@('\', '/'))
    New-Item -ItemType Directory -Path $to -Force | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $sourceRoot -Force -Recurse) {
        $relative = $item.FullName.Substring($sourceRoot.Length).TrimStart([char[]]@('\', '/'))
        $target = Join-Path $to $relative
        if ($item.PSIsContainer) {
            New-Item -ItemType Directory -Path $target -Force | Out-Null
            continue
        }
        if ($NewerOnly -and (Test-Path -LiteralPath $target -PathType Leaf)) {
            $existing = Get-Item -LiteralPath $target -Force
            if ($item.LastWriteTimeUtc -lt $existing.LastWriteTimeUtc -or ($item.LastWriteTimeUtc -eq $existing.LastWriteTimeUtc -and $item.Length -eq $existing.Length)) { continue }
        }
        $parent = Split-Path -Parent $target
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        Copy-Item -LiteralPath $item.FullName -Destination $target -Force
    }
}

function Invoke-Setup {
    Say ''
    Say '  VICE CITY SKATE - first-time setup' 'Cyan'
    Say '  ----------------------------------' 'Cyan'
    Say '  You need: GTA Vice City (original PC version, not the Definitive Edition)'
    Say '  and Skate 3 for Xbox 360, extracted (default.xex with its data folder).'
    Say '  Your game folders are only read, never changed.'
    Say ''

    # 1. Vice City
    $vc = Clean $ViceCity
    if ($vc -and -not (Test-ViceCity $vc)) { Fail "Not a GTA Vice City folder: $vc" }
    if (-not $vc) {
        $found = Find-ViceCity
        while ($true) {
            Say 'Step 1 of 2: your GTA Vice City folder' 'Yellow'
            Say '  (the folder with models, data and anim in it; you can drag it into this window)'
            if ($found) { Say "  Found: $found" 'Green'; Say '  Press Enter to use it, or type another folder.' }
            $answer = Clean (Read-Host '  Vice City folder')
            if (-not $answer -and $found) { $answer = $found }
            if (Test-ViceCity $answer) { $vc = (Resolve-Path -LiteralPath $answer).Path; break }
            if ($answer -and (Test-Path -LiteralPath (Join-Path $answer 'Gameface'))) {
                Say '  That is the Definitive Edition. Vice City Skate needs the original 2002 PC version.' 'Red'
            } else {
                Say '  That folder is not GTA Vice City (models\gta3.img, data\gta_vc.dat, ... are missing). Try again.' 'Red'
            }
            Say ''
        }
    }
    Say "  Vice City: $vc" 'Green'
    Say ''

    # 2. Skate 3
    $x = Resolve-Xex (Clean $Xex)
    if ($Xex -and -not $x) { Fail "Not a Skate 3 default.xex: $Xex" }
    while (-not $x) {
        Say 'Step 2 of 2: your Skate 3 default.xex' 'Yellow'
        Say '  (the file default.xex from the extracted Xbox 360 game, with its data folder beside it;'
        Say '   you can drag the file or its folder into this window. ISO files do not work.)'
        $answer = Clean (Read-Host '  default.xex')
        $x = Resolve-Xex $answer
        if (-not $x) { Say '  That is not a default.xex file (or a folder containing one). Try again.' 'Red'; Say ''; continue }
        $missing = Test-SkateData $x
        if ($missing) { Say "  The data folder next to default.xex is incomplete ($missing is missing). Try again." 'Red'; Say ''; $x = $null }
    }
    $missing = Test-SkateData $x
    if ($missing) { Fail "The Skate 3 data folder next to $x is incomplete ($missing is missing)." }
    Say "  Skate 3:   $x" 'Green'
    Say ''

    # 3. Room
    $size = (Get-ChildItem -LiteralPath $vc -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    $drive = (Get-Item -LiteralPath $package).PSDrive
    $need = $size + 400MB
    if ($drive.Free -lt $need) { Fail ("Not enough free space on {0}: need {1:N1} GB, have {2:N1} GB." -f $drive.Name, ($need / 1GB), ($drive.Free / 1GB)) }

    # 4. Copy Vice City, then reVC and skate mode over it
    Say 'Copying Vice City into this folder (this takes a minute)...' 'Cyan'
    Copy-Tree $vc $game
    Copy-Tree $bin $game
    Say '  done'

    # 5. Skate 3 data
    Say 'Converting the Skate 3 data (skater, animations, physics settings)...' 'Cyan'
    & $converter --xex $x --out (Join-Path $game 'skate-data')
    if ($LASTEXITCODE -ne 0) { Fail 'The Skate 3 conversion failed. See the messages above.' }
    if (-not (Test-Path (Join-Path $game 'skate-data\assets\private\skater.glb'))) { Fail 'The Skate 3 conversion did not produce the skater model.' }

    Set-Content -LiteralPath $remembered -Value @("ViceCity=$vc", "Xex=$x") -Encoding UTF8
    Say ''
    Say 'Setup finished.' 'Green'
}

# -------------------------------------------------------------------- main

try { [IO.File]::WriteAllText((Join-Path $files '.write-test'), 'x'); Remove-Item (Join-Path $files '.write-test') }
catch { Fail "This folder is read-only: $package`nMove the Vice City Skate folder somewhere you can write to (for example C:\Games) and run it again." }
if ($package -match '[^\x20-\x7E]') {
    Fail "Please move the Vice City Skate folder to a path with only plain English letters and numbers`n(for example C:\Games\Vice City Skate). Current path: $package"
}
if (-not (Test-Path (Join-Path $bin 'reVC.exe')) -or -not (Test-Path $converter)) { Fail 'Vice City Skate is incomplete (Files\bin\reVC.exe or Files\setup\iw4l-skate-convert.exe is missing). Unzip it again.' }

$ready = (Test-Path (Join-Path $game 'reVC.exe')) -and (Test-Path (Join-Path $game 'skate-data\assets\private\skater.glb')) -and (Test-ViceCity $game)
if ($Setup -or -not $ready) {
    Invoke-Setup
} else {
    # Updates: newer files dropped into bin\ replace the game's copies.
    Copy-Tree $bin $game -NewerOnly
}

if ($NoLaunch) { exit 0 }
Say 'Starting Vice City Skate...' 'Cyan'
Say '  J (or both sticks clicked in) gets on and off the board. Ctrl+M opens the skate tools.'
Start-Process -FilePath (Join-Path $game 'reVC.exe') -WorkingDirectory $game
exit 0
