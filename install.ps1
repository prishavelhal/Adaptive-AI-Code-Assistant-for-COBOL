# =============================================================================
# CobolTutor installer for Windows.   (macOS / Linux: install.sh)
#
#   Double-click install.cmd, or from PowerShell:
#     powershell -ExecutionPolicy Bypass -File install.ps1            # interactive
#     powershell -ExecutionPolicy Bypass -File install.ps1 --yes      # no questions
#     powershell -ExecutionPolicy Bypass -File install.ps1 --help     # all options
#
# Takes the same options as install.sh (--yes, --gpu, --ollama, ...); the
# PowerShell spellings -Yes, -Gpu, ... work too.
#
# What it does, in order:
#   1. Checks this PC: Windows version, RAM, disk, and GPU (NVIDIA, AMD).
#   2. Installs Docker Desktop (and WSL 2) with winget if needed, and starts it.
#   3. Sets up the GPU path:
#        - NVIDIA: Ollama in Docker on the GPU (Docker Desktop passes it through)
#        - AMD:    Ollama installed natively, since Docker can't use AMD GPUs here
#        - none:   Ollama in Docker on the CPU
#   4. Finds VS Code (or Cursor / VSCodium / Windsurf); installs VS Code if none.
#   5. Downloads the Granite models with a live progress bar. While that runs,
#      the backend image and the VS Code extension build in the background.
#   6. Starts the stack and waits until the backend says the model is ready.
#   7. Installs the CobolTutor extension into every editor it found.
#
# Safe to run again: finished steps are skipped and models aren't re-downloaded.
#
# Notes for maintainers:
#   - Works in Windows PowerShell 5.1 (built into Windows) and PowerShell 7.
#     So: no ternaries, no `??`, no `&&` between commands.
#   - This file is pure ASCII on purpose. PowerShell 5.1 reads BOM-less files
#     as ANSI, which would garble any UTF-8 characters; symbols are built from
#     code points at runtime instead.
#   - Native commands (docker, ollama, ...) report failure through
#     $LASTEXITCODE, which is checked explicitly everywhere.
# =============================================================================

$ErrorActionPreference = 'Continue'
Set-StrictMode -Version 2.0

# =============================================================================
# Settings. Keep model names and versions in step with coboltutor\docker-compose.yml.
# =============================================================================
$ChatModel       = 'granite4.2:8b'                # the tutor model
$EmbedModel      = 'granite-embedding:278m'       # for the upcoming RAG milestone
$NativeModel     = 'coboltutor-granite4.2:8b'     # native mode: ChatModel with a 16k context
$OllamaImage     = 'ollama/ollama:0.40.11'        # used to copy models out of the Docker volume
$OllamaVolume    = 'ollama-models'                # the named volume in docker-compose.yml
$NodeImage       = 'node:22-slim'                 # builds the extension when Node 22+ isn't installed
$BackendUrl      = 'http://127.0.0.1:8000'
$NativeOllamaUrl = 'http://127.0.0.1:11434'
$MinRamGB  = 8
$GoodRamGB = 16
$MinDiskGB = 12
$MinCompose = '2.24.0'   # native mode's override uses `!reset`

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppDir  = Join-Path $RootDir 'coboltutor'
$ExtDir  = Join-Path $AppDir 'extension'
$LogDir  = Join-Path $RootDir ('.install-logs\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))

# =============================================================================
# Command-line options (parsed by hand so both --yes and -Yes work)
# =============================================================================
$AssumeYes   = $false
$GpuChoice   = 'auto'   # auto | nvidia | amd | cpu
$OllamaMode  = 'auto'   # auto | docker | native
$DoModels    = $true
$DoExtension = $true
$DoEditor    = $true
$DryRun      = $false

function Show-Usage {
    @'
CobolTutor installer (Windows)

Usage: install.cmd [options]
       powershell -ExecutionPolicy Bypass -File install.ps1 [options]

Options:
  -y, --yes             Don't ask questions; accept the defaults.
      --gpu MODE        auto (default), nvidia, amd, or cpu.
      --cpu             Same as --gpu cpu.
      --ollama MODE     Where Ollama runs: auto (default), docker, or native.
                        auto = Docker, except native for AMD GPUs.
      --no-models       Don't download the AI models now.
      --no-extension    Don't build or install the VS Code extension.
      --no-editor       Don't install VS Code if no editor is found.
      --dry-run         Show what would happen without changing anything.
  -h, --help            Show this help.

Environment: NO_COLOR=1 turns off colors.
'@
}

$argList = @($args)
for ($i = 0; $i -lt $argList.Count; $i++) {
    $raw = [string]$argList[$i]
    $a = $raw.ToLowerInvariant() -replace '^-+', '-'   # --yes, -yes, -Yes -> -yes
    $value = $null
    if ($a -match '^(-[a-z-]+)=(.*)$') { $a = $Matches[1]; $value = $Matches[2] }
    switch ($a) {
        { $_ -in '-y', '-yes' }        { $AssumeYes = $true; continue }
        '-cpu'                          { $GpuChoice = 'cpu'; continue }
        '-no-models'                    { $DoModels = $false; continue }
        { $_ -in '-no-extension', '-noextension' } { $DoExtension = $false; continue }
        { $_ -in '-no-editor', '-noeditor' }       { $DoEditor = $false; continue }
        { $_ -in '-dry-run', '-dryrun' }           { $DryRun = $true; continue }
        { $_ -in '-h', '-help', '-?' }  { Show-Usage; exit 0 }
        { $_ -in '-gpu', '-ollama' } {
            if ($null -eq $value) { $i++; if ($i -lt $argList.Count) { $value = [string]$argList[$i] } else { $value = '' } }
            if ($a -eq '-gpu') { $GpuChoice = $value.ToLowerInvariant() } else { $OllamaMode = $value.ToLowerInvariant() }
            continue
        }
        default { [Console]::Error.WriteLine("Unknown option: $raw (try --help)"); exit 2 }
    }
}
if ($GpuChoice -notin 'auto', 'nvidia', 'amd', 'cpu') {
    [Console]::Error.WriteLine("--gpu must be auto, nvidia, amd, or cpu (got '$GpuChoice')"); exit 2
}
if ($OllamaMode -notin 'auto', 'docker', 'native') {
    [Console]::Error.WriteLine("--ollama must be auto, docker, or native (got '$OllamaMode')"); exit 2
}

# =============================================================================
# Terminal UI
# =============================================================================
$UseColor = (-not $env:NO_COLOR) -and (-not [Console]::IsOutputRedirected)
# Windows Terminal, VS Code's terminal, and PowerShell 7 render Unicode well;
# the old console host may not, so it gets ASCII.
$UseUnicode = [bool]($env:WT_SESSION -or $env:TERM_PROGRAM -eq 'vscode' -or $PSVersionTable.PSVersion.Major -ge 7)
if ($UseUnicode) {
    try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { $UseUnicode = $false }
}
if ($UseUnicode) {
    $S_OK = [string][char]0x2714; $S_FAIL = [string][char]0x2716; $S_WARN = [string][char]0x25B2
    $S_ARROW = [string][char]0x203A; $S_DOT = [string][char]0x2022; $S_BAR = [string][char]0x2502
    $H_LINE = [string][char]0x2500
    $Frames = @(0x280B, 0x2819, 0x2839, 0x2838, 0x283C, 0x2834, 0x2826, 0x2827, 0x2807, 0x280F) | ForEach-Object { [string][char]$_ }
} else {
    $S_OK = 'OK'; $S_FAIL = 'X'; $S_WARN = '!'; $S_ARROW = '>'; $S_DOT = '*'; $S_BAR = '|'; $H_LINE = '-'
    $Frames = @('|', '/', '-', '\')
}

$TotalSteps = 7
$script:CurrentStep = 0

function W([string]$text, [string]$color = '', [switch]$NoNewline) {
    if ($UseColor -and $color) { Write-Host $text -ForegroundColor $color -NoNewline:$NoNewline }
    else { Write-Host $text -NoNewline:$NoNewline }
}

function Show-Banner {
    W ''
    W '    ____      _           _ _____      _' Cyan
    W '   / ___|___ | |__   ___ | |_   _|   _| |_ ___  _ __' Cyan
    W "  | |   / _ \| '_ \ / _ \| | | || | | | __/ _ \| '__|" Cyan
    W '  | |__| (_) | |_) | (_) | | | || |_| | || (_) | |' Cyan
    W '   \____\___/|_.__/ \___/|_| |_| \__,_|\__\___/|_|' Cyan
    W ''
    W "  Your local IBM COBOL tutor $S_DOT Granite 4.2 on Ollama $S_DOT VS Code" DarkGray
    if ($DryRun) { W '  DRY RUN: nothing will be changed' Yellow }
    W ''
}

function Step([string]$title) {
    $script:CurrentStep++
    $pad = [Math]::Max(3, 52 - $title.Length)
    W ''
    W ("[{0}/{1}] " -f $script:CurrentStep, $TotalSteps) Magenta -NoNewline
    W "$title " White -NoNewline
    W ($H_LINE * $pad) DarkGray
}

function Ok([string]$m)   { W "  $S_OK " Green -NoNewline; W $m }
function Warn([string]$m) { W "  $S_WARN " Yellow -NoNewline; W $m }
function Err([string]$m)  { W "  $S_FAIL " Red -NoNewline; W $m }
function Info([string]$m) { W "  $S_ARROW $m" DarkGray }
function Note([string]$m) { W "    $m" DarkGray }
function Kv([string]$k, [string]$v) { W ('  {0,-14} ' -f $k) DarkGray -NoNewline; W $v }

function Die([string]$m) {
    Err $m
    if (Test-Path $LogDir) { Note "Logs: $LogDir" }
    exit 1
}

function Format-Elapsed([datetime]$start) {
    $s = [int]((Get-Date) - $start).TotalSeconds
    '{0}:{1:00}' -f [int][Math]::Floor($s / 60), ($s % 60)
}

function Show-LogTail([string]$log, [int]$lines = 15) {
    if (-not (Test-Path $log)) { return }
    Get-Content $log -Tail $lines | ForEach-Object { W "    $S_BAR $_" DarkGray }
    Note "Full log: $log"
}

function Write-Spinner([int]$i, [string]$label, [datetime]$start) {
    if ([Console]::IsOutputRedirected) { return }
    $line = "`r  {0} {1} ({2})" -f $Frames[$i % $Frames.Count], $label, (Format-Elapsed $start)
    $width = 80
    try { $width = [Console]::WindowWidth - 1 } catch { $width = 79 }  # no real console: keep the default
    W ($line.PadRight($width).Substring(0, [Math]::Min($width, $line.PadRight($width).Length))) Cyan -NoNewline
}

function Clear-SpinnerLine {
    if ([Console]::IsOutputRedirected) { return }
    $width = 80
    try { $width = [Console]::WindowWidth - 1 } catch { $width = 79 }  # no real console: keep the default
    Write-Host ("`r" + (' ' * $width) + "`r") -NoNewline
}

# Background work runs as a PowerShell job: a scriptblock plus arguments.
# The scriptblock writes its output to $log and its exit code is returned.
$script:Jobs = @{}
function Start-Bg([string]$name, [string]$log, [scriptblock]$block, [object[]]$arguments = @()) {
    $wrapper = {
        param($dir, $log, $blockText, $arguments)
        $ErrorActionPreference = 'Continue'
        Set-Location $dir
        $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
        $sb = [scriptblock]::Create($blockText)
        $global:LASTEXITCODE = 0
        try {
            & $sb @arguments *>&1 | ForEach-Object { "$_" } | Out-File -FilePath $log -Encoding utf8
            $code = $LASTEXITCODE
        } catch {
            "$_" | Out-File -FilePath $log -Append -Encoding utf8
            $code = 1
        }
        [int]$code
    }
    $job = Start-Job -ScriptBlock $wrapper -ArgumentList $AppDir, $log, $block.ToString(), $arguments
    $script:Jobs[$name] = @{ Job = $job; Log = $log }
}

# Wait for a background job with a spinner; returns $true on success.
function Wait-Bg([string]$name, [string]$label) {
    $entry = $script:Jobs[$name]
    $start = Get-Date; $i = 0
    while ($entry.Job.State -eq 'Running') {
        Write-Spinner $i $label $start; $i++
        Start-Sleep -Milliseconds 100
    }
    Clear-SpinnerLine
    $out = @(Receive-Job $entry.Job 2>$null)
    Remove-Job $entry.Job -Force
    $code = 1
    if ($out.Count -gt 0 -and $out[-1] -is [int]) { $code = $out[-1] }
    if ($code -eq 0) { Ok "$label ($(Format-Elapsed $start))"; return $true }
    Err "$label failed (exit code $code)"
    Show-LogTail $entry.Log
    return $false
}

# Run a native command with a spinner; output goes to a log. For commands that never prompt.
function Run([string]$label, [string]$exe, [string[]]$arguments = @()) {
    if ($DryRun) { Info "[dry-run] ${label}: $exe $($arguments -join ' ')"; return $true }
    $slug = ($label.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    $log = Join-Path $LogDir "$slug.log"
    Start-Bg $slug $log { param($exe, $a) & $exe @a } @($exe, $arguments)
    return (Wait-Bg $slug $label)
}

# Quote arguments for Start-Process, which takes one command-line string.
function Join-Arguments([string[]]$a) {
    ($a | ForEach-Object {
        if ($_ -eq '' -or $_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    }) -join ' '
}

# Run a native command in the foreground, showing its own output (progress bars,
# installers with their own prompts). Returns $true when it exits with 0.
# Start-Process hands the command this console directly. Calling it with `&`
# inside a function would capture its output into the function's return value,
# and the tool would see a pipe instead of a terminal and drop its progress bar.
function Live([string]$exe, [string[]]$arguments = @(), [string]$workDir = $AppDir) {
    if ($DryRun) { Info "[dry-run] $exe $($arguments -join ' ')"; return $true }
    $params = @{ FilePath = $exe; NoNewWindow = $true; Wait = $true; PassThru = $true; WorkingDirectory = $workDir }
    if ($arguments.Count -gt 0) { $params.ArgumentList = Join-Arguments $arguments }
    try { $p = Start-Process @params } catch { Err "$_"; return $false }
    return ($p.ExitCode -eq 0)
}

# Poll a scriptblock until it returns $true, with a spinner.
function Wait-Until([string]$label, [int]$timeoutSec, [scriptblock]$test) {
    if ($DryRun) { Info "[dry-run] wait for: $label"; return $true }
    $start = Get-Date; $i = 0; $next = Get-Date
    while ($true) {
        if ((Get-Date) -ge $next) {
            if (& $test) { break }
            $next = (Get-Date).AddSeconds(2)
        }
        if (((Get-Date) - $start).TotalSeconds -ge $timeoutSec) {
            Clear-SpinnerLine; Err "${label}: gave up after ${timeoutSec}s"; return $false
        }
        Write-Spinner $i $label $start; $i++
        Start-Sleep -Milliseconds 100
    }
    Clear-SpinnerLine
    Ok "$label ($(Format-Elapsed $start))"
    return $true
}

function Confirm([string]$question, [bool]$default = $true) {
    if ($AssumeYes -or [Console]::IsInputRedirected) { return $default }
    $hint = '[y/N]'; if ($default) { $hint = '[Y/n]' }
    W '  ? ' Blue -NoNewline; W "$question " -NoNewline; W "$hint " DarkGray -NoNewline
    $ans = Read-Host
    if ([string]::IsNullOrWhiteSpace($ans)) { return $default }
    return ($ans -match '^[Yy]')
}

# =============================================================================
# Small helpers
# =============================================================================
function Have([string]$cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

function Update-PathFromRegistry {
    # Installers update PATH in the registry; pick that up without a new window.
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}

function Test-VersionAtLeast([string]$have, [string]$need) {
    $clean = { param($v) ($v -replace '^[vV]', '' -replace '[-+ ].*$', '') }
    try { return ([version](& $clean $have) -ge [version](& $clean $need)) } catch { return $true }
}

function Invoke-Docker { & docker @args }
function Invoke-Compose {
    Push-Location $AppDir
    try { & docker compose @args } finally { Pop-Location }
}

function Test-Http([string]$url) {
    try { $null = Invoke-RestMethod -Uri $url -TimeoutSec 3; return $true } catch { return $false }
}

function Install-WithWinget([string]$id, [string]$label) {
    if (-not (Have winget)) {
        Die "winget isn't available. Install 'App Installer' from the Microsoft Store, or install $label yourself, then run this again."
    }
    # winget shows its own progress and Windows may ask for admin rights (UAC),
    # so this runs in the foreground.
    $ok = Live 'winget' @('install', '--exact', '--id', $id, '--accept-package-agreements', '--accept-source-agreements')
    Update-PathFromRegistry
    return $ok
}

# =============================================================================
# Step 1: detect the system
# =============================================================================
$script:RamGB = 0; $script:DiskGB = 0
$script:GpuKind = 'none'; $script:GpuName = ''; $script:GpuNote = ''
$script:Accel = 'cpu'; $script:Override = ''

function Find-NvidiaSmi {
    $c = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    foreach ($p in @("$env:SystemRoot\System32\nvidia-smi.exe", "$env:ProgramFiles\NVIDIA Corporation\NVSMI\nvidia-smi.exe")) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Find-Gpu {
    $smi = Find-NvidiaSmi
    if ($smi) {
        $q = & $smi --query-gpu=name,memory.total --format=csv,noheader 2>$null
        if ($LASTEXITCODE -eq 0 -and $q) {
            $script:GpuKind = 'nvidia'; $script:GpuName = (@($q)[0] -replace ', ', ' - '); return
        }
    }
    $cards = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    $nv = $cards | Where-Object { $_ -match 'NVIDIA' } | Select-Object -First 1
    $amd = $cards | Where-Object { $_ -match 'AMD|Radeon' } | Select-Object -First 1
    if ($nv) { $script:GpuNote = "Found $nv, but its driver tools (nvidia-smi) aren't working. Update the NVIDIA driver for GPU speed; using the CPU for now." }
    if ($amd) { $script:GpuKind = 'amd'; $script:GpuName = $amd }
}

function Select-Plan {
    $want = $GpuChoice
    if ($want -eq 'auto') { $want = $script:GpuKind }
    if ($want -eq 'none') { $want = 'cpu' }
    $script:Accel = $want

    if ($script:OllamaMode -eq 'auto') {
        # Docker Desktop passes NVIDIA GPUs through, but not AMD ones, so an
        # AMD GPU is only usable by an Ollama installed directly on Windows.
        if ($script:Accel -eq 'amd') { $script:OllamaMode = 'native' } else { $script:OllamaMode = 'docker' }
    }
    if ($script:OllamaMode -eq 'docker' -and $script:Accel -eq 'amd') {
        Warn "Docker can't use AMD GPUs on Windows, so Ollama in Docker will run on the CPU."
        $script:Accel = 'cpu'
    }
    if ($script:OllamaMode -eq 'native') { $script:Override = 'docker-compose.native-ollama.yml' }
    elseif ($script:Accel -eq 'nvidia') { $script:Override = 'docker-compose.gpu-nvidia.yml' }
    else { $script:Override = '' }
}

function Get-AccelLabel {
    if ($script:OllamaMode -eq 'native') {
        if ($script:Accel -eq 'cpu') { return 'CPU via Ollama on Windows' }
        return "$($script:Accel.ToUpper()) GPU via Ollama on Windows"
    }
    if ($script:Accel -eq 'nvidia') { return 'NVIDIA GPU via Ollama in Docker' }
    return 'CPU via Ollama in Docker (answers will be slower)'
}

function Step-System {
    Step 'Checking your system'
    if (-not (Test-Path (Join-Path $AppDir 'docker-compose.yml'))) {
        Die "Can't find coboltutor\docker-compose.yml next to this script. Run it from a clone of the repository."
    }
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    if ($cs) { $script:RamGB = [int][Math]::Floor($cs.TotalPhysicalMemory / 1GB) }
    $sysDrive = $env:SystemDrive.TrimEnd(':')
    # Docker Desktop keeps images and volumes on the system drive by default.
    $d = Get-PSDrive -Name $sysDrive -ErrorAction SilentlyContinue
    if ($d) { $script:DiskGB = [int][Math]::Floor($d.Free / 1GB) }
    Find-Gpu
    Select-Plan

    $osName = 'Windows'; if ($os) { $osName = "$($os.Caption) (build $($os.BuildNumber))" }
    Kv 'System' "$osName ($env:PROCESSOR_ARCHITECTURE)"
    Kv 'Memory' "$($script:RamGB) GB"
    Kv 'Free disk' "$($script:DiskGB) GB on ${sysDrive}:"
    if ($script:GpuName) { Kv 'GPU' $script:GpuName } else { Kv 'GPU' 'none usable' }
    Kv 'Granite runs' (Get-AccelLabel)
    if ($script:GpuNote) { Warn $script:GpuNote }

    if ($script:RamGB -lt $MinRamGB) { Warn "Only $($script:RamGB) GB of RAM: Granite 8B needs about $MinRamGB GB and may not load." }
    elseif ($script:RamGB -lt $GoodRamGB) { Note "$($script:RamGB) GB of RAM works, but $GoodRamGB GB+ is more comfortable." }
    if ($script:DiskGB -lt $MinDiskGB) {
        Warn "Only $($script:DiskGB) GB free; about $MinDiskGB GB is needed for the models and images."
        if (-not (Confirm 'Continue anyway?' $false)) { Die 'Stopped. Free up some disk space and run again.' }
    }
    W ''
    if (-not (Confirm 'Install CobolTutor with these settings?' $true)) {
        Info 'Nothing changed. Options: install.cmd --help'; exit 0
    }
}

# =============================================================================
# Step 2: Docker Desktop
# =============================================================================
function Test-DockerReady { & docker info *> $null; return ($LASTEXITCODE -eq 0) }

function Find-DockerCli {
    if (Have docker) { return $true }
    $p = Join-Path $env:ProgramFiles 'Docker\Docker\resources\bin'
    if (Test-Path (Join-Path $p 'docker.exe')) { $env:Path = "$p;$env:Path"; return $true }
    return $false
}

function Step-Docker {
    Step 'Docker'
    if (-not (Find-DockerCli)) {
        # Docker Desktop runs on WSL 2. Turning WSL on needs admin and a reboot.
        & wsl.exe --status *> $null
        if ($LASTEXITCODE -ne 0) {
            Info 'Docker Desktop needs WSL 2, which is not turned on yet.'
            if (-not (Confirm 'Turn on WSL 2 now? (asks for admin rights; needs a restart after)' $true)) {
                Die 'Docker Desktop needs WSL 2. Run "wsl --install" as administrator, restart, then run this again.'
            }
            if (-not $DryRun) {
                $p = Start-Process wsl.exe -ArgumentList '--install', '--no-distribution' -Verb RunAs -Wait -PassThru
                if ($p.ExitCode -ne 0) { Die 'Turning on WSL failed. Run "wsl --install" as administrator yourself.' }
                Warn 'WSL 2 is on. Restart Windows, then run install.cmd again to continue.'
                exit 0
            }
        }
        Info "Docker isn't installed. Installing Docker Desktop with winget."
        if (-not (Install-WithWinget 'Docker.DockerDesktop' 'Docker Desktop')) { Die "Docker Desktop didn't install." }
        if (-not $DryRun -and -not (Find-DockerCli)) {
            Die 'Docker Desktop installed. Restart Windows (or sign out and in), then run install.cmd again.'
        }
        Ok 'Docker Desktop installed'
    } else {
        $v = (& docker --version 2>$null) -replace '^Docker version ', '' -replace ',.*$', ''
        Ok "Docker is installed ($v)"
    }

    if (-not $DryRun -and -not (Test-DockerReady)) {
        $exe = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
        if (Test-Path $exe) {
            Start-Process $exe
            Note "If Docker Desktop shows its welcome window, accept it so the engine can start."
        }
        if (-not (Wait-Until 'Waiting for Docker to start' 300 { Test-DockerReady })) {
            Die "Docker didn't start. Open Docker Desktop, wait until it says it's running, then run this again."
        }
    }
    if (-not $DryRun) { Ok 'Docker engine is running' }

    $cv = (& docker compose version --short 2>$null)
    if ($LASTEXITCODE -ne 0) { Die 'Docker Compose is missing. Update Docker Desktop, then run this again.' }
    $cv = ([string]$cv).Trim() -replace '^v', ''
    Ok "Docker Compose ($cv)"
    if ($script:OllamaMode -eq 'native' -and -not (Test-VersionAtLeast $cv $MinCompose)) {
        Die "Docker Compose $cv is too old (need $MinCompose+). Update Docker Desktop and run this again."
    }
}

# =============================================================================
# Step 3: GPU runtime / native Ollama
# =============================================================================
$script:OllamaExe = ''
function Find-Ollama {
    $c = Get-Command ollama -ErrorAction SilentlyContinue
    if ($c) { $script:OllamaExe = $c.Source; return $true }
    $p = Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'
    if (Test-Path $p) { $script:OllamaExe = $p; return $true }
    return $false
}

function Test-NativeOllama { Test-Http "$NativeOllamaUrl/api/version" }

function Step-Accel {
    Step 'AI runtime'
    if ($script:OllamaMode -eq 'native') {
        if (Find-Ollama) { Ok "Ollama is installed ($($script:OllamaExe))" }
        else {
            Info "Ollama isn't installed. Installing it with winget."
            if (-not (Install-WithWinget 'Ollama.Ollama' 'Ollama')) { Die "Ollama didn't install." }
            if (-not $DryRun -and -not (Find-Ollama)) { Die "Ollama installed, but ollama.exe wasn't found. Open a new terminal and run this again." }
            if ($DryRun) { $script:OllamaExe = 'ollama' }
        }
        if (-not $DryRun -and -not (Test-NativeOllama)) {
            # The Ollama app starts the server and keeps it running at sign-in.
            $app = Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama app.exe'
            if (Test-Path $app) { Start-Process $app }
            else { Start-Process $script:OllamaExe -ArgumentList 'serve' -WindowStyle Hidden }
            if (-not (Wait-Until 'Waiting for Ollama to start' 60 { Test-NativeOllama })) {
                Die "Ollama didn't start. Open the Ollama app from the Start menu, then run this again."
            }
        }
        if (-not $DryRun) {
            $v = (Invoke-RestMethod "$NativeOllamaUrl/api/version").version
            $tested = $OllamaImage.Split(':')[1]
            if (-not (Test-VersionAtLeast $v $tested)) {
                Warn "Ollama $v is older than the tested version ($tested); Granite 4.2 may not load."
                if (Confirm 'Upgrade Ollama with winget?' $true) {
                    $null = Live 'winget' @('upgrade', '--exact', '--id', 'Ollama.Ollama', '--accept-package-agreements', '--accept-source-agreements')
                    $null = Wait-Until 'Waiting for Ollama to restart' 60 { Test-NativeOllama }
                }
            } else { Ok "Ollama is running (version $v)" }
        }
    } elseif ($script:Accel -eq 'nvidia') {
        Ok "Using Docker Desktop's built-in NVIDIA GPU support (WSL 2)"
    } else {
        Ok 'Nothing extra needed for the CPU'
    }
    Write-ComposeEnv
}

# Record the chosen compose files in coboltutor\.env, so a plain
# `docker compose up -d` later uses the same setup. Other lines are kept.
function Write-ComposeEnv {
    $envFile = Join-Path $AppDir '.env'
    $files = 'docker-compose.yml'
    if ($script:Override) { $files = "$files;$($script:Override)" }
    if ($DryRun) { Info "[dry-run] write COMPOSE_FILE=$files to coboltutor\.env"; return }
    $keep = @()
    if (Test-Path $envFile) {
        $keep = @(Get-Content $envFile | Where-Object { $_ -notmatch '^(COMPOSE_FILE|COMPOSE_PATH_SEPARATOR)=' -and $_ -notmatch '^# Set by install\.(sh|ps1)' })
    }
    $lines = $keep + @('# Set by install.ps1: which compose files make up this machine''s stack.', 'COMPOSE_PATH_SEPARATOR=;', "COMPOSE_FILE=$files")
    # UTF-8 without a BOM: Compose would read a BOM as part of the first key.
    [IO.File]::WriteAllLines($envFile, [string[]]$lines, (New-Object Text.UTF8Encoding $false))
    Ok "Saved the setup to coboltutor\.env (COMPOSE_FILE=$files)"
}

# =============================================================================
# Step 4: code editor
# =============================================================================
$script:Editors = @()   # objects with Name and Cli

function Find-Editors {
    $script:Editors = @()
    $candidates = @(
        @('VS Code', 'code.cmd', "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd", "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd"),
        @('VS Code Insiders', 'code-insiders.cmd', "$env:LOCALAPPDATA\Programs\Microsoft VS Code Insiders\bin\code-insiders.cmd", "$env:ProgramFiles\Microsoft VS Code Insiders\bin\code-insiders.cmd"),
        @('Cursor', 'cursor.cmd', "$env:LOCALAPPDATA\Programs\cursor\resources\app\bin\cursor.cmd", ''),
        @('VSCodium', 'codium.cmd', "$env:LOCALAPPDATA\Programs\VSCodium\bin\codium.cmd", "$env:ProgramFiles\VSCodium\bin\codium.cmd"),
        @('Windsurf', 'windsurf.cmd', "$env:LOCALAPPDATA\Programs\Windsurf\bin\windsurf.cmd", '')
    )
    foreach ($c in $candidates) {
        $cli = $null
        $onPath = Get-Command $c[1] -ErrorAction SilentlyContinue
        if ($onPath) { $cli = $onPath.Source }
        else {
            foreach ($p in $c[2..3]) { if ($p -and (Test-Path $p)) { $cli = $p; break } }
        }
        if ($cli) { $script:Editors += [pscustomobject]@{ Name = $c[0]; Cli = $cli } }
    }
}

function Step-Editor {
    Step 'Code editor'
    if (-not $DoExtension) { Info 'Skipped (--no-extension)'; return }
    Find-Editors
    if ($script:Editors.Count -eq 0) {
        if (-not $DoEditor) { Warn 'No VS Code-compatible editor found; skipping (--no-editor).' }
        elseif (Confirm 'No VS Code-compatible editor found. Install VS Code?' $true) {
            if (-not (Install-WithWinget 'Microsoft.VisualStudioCode' 'VS Code')) {
                Warn "Couldn't install VS Code automatically. Get it from https://code.visualstudio.com"
            }
            Find-Editors
        }
    }
    foreach ($e in $script:Editors) { Ok "$($e.Name) ($($e.Cli))" }
    if ($script:Editors.Count -eq 0 -and -not $DryRun) { Note 'The extension will still be built so you can install it later.' }
}

# =============================================================================
# Step 5: models (foreground, with progress) + builds (background)
# =============================================================================
$pkg = Get-Content (Join-Path $ExtDir 'package.json') -Raw | ConvertFrom-Json
$ExtVersion = $pkg.version
$PnpmVersion = ($pkg.packageManager -replace '^pnpm@', '')

function Test-HostNode {
    # npx.cmd, not npx: the npx.ps1 shim can be blocked by the execution policy.
    if (-not (Have node) -or -not (Have npx.cmd)) { return $false }
    $major = & node -p "process.versions.node.split('.')[0]" 2>$null
    return ($LASTEXITCODE -eq 0 -and [int]$major -ge 22)
}

# Runs inside a background job. Builds coboltutor\extension\coboltutor-<version>.vsix
# with Node on this PC if it's new enough, otherwise inside a Node container.
$BuildExtensionBlock = {
    param($extDir, $pnpm, $nodeImage, $useHost)
    if ($useHost) {
        "Building with Node $(& node -v) on this PC"
        Push-Location $extDir
        & npx.cmd --yes "pnpm@$pnpm" install --frozen-lockfile
        if ($LASTEXITCODE -eq 0) { & npx.cmd --yes "pnpm@$pnpm" run package }
        Pop-Location
        if ($LASTEXITCODE -eq 0) { return }
        'Local build failed; trying again in a container'
    }
    "Building in $nodeImage"
    # Copy the sources (minus any Windows node_modules) into the container,
    # build there, and copy only the finished .vsix back out.
    $sh = 'mkdir /build && tar -C /src --exclude=./node_modules --exclude=./dist --exclude="./*.vsix" -cf - . | tar -C /build -xf - && cd /build && npx --yes "pnpm@$PNPM_VERSION" install --frozen-lockfile && npx --yes "pnpm@$PNPM_VERSION" run package && cp ./*.vsix /src/'
    & docker run --rm -v "${extDir}:/src" -e "PNPM_VERSION=$pnpm" $nodeImage sh -euc $sh
}

function Start-BackgroundBuilds {
    if ($DryRun) {
        Info '[dry-run] background: docker compose build backend'
        if ($DoExtension) { Info "[dry-run] background: build coboltutor-$ExtVersion.vsix" }
        return
    }
    Start-Bg 'backend' (Join-Path $LogDir 'backend-build.log') { & docker compose build backend }
    Info 'Building the backend image in the background'
    if ($DoExtension) {
        Start-Bg 'extension' (Join-Path $LogDir 'extension-build.log') $BuildExtensionBlock @($ExtDir, $PnpmVersion, $NodeImage, (Test-HostNode))
        Info 'Building the VS Code extension in the background'
    }
}

# `ollama pull` with its own progress bar; retried, since Ollama resumes.
function Get-Model([string]$model) {
    W ''
    W "  $S_ARROW " Cyan -NoNewline; W "Downloading $model" White
    for ($try = 1; $try -le 3; $try++) {
        if ($script:OllamaMode -eq 'native') { $ok = Live $script:OllamaExe @('pull', $model) }
        else {
            $a = @('compose', 'exec')
            if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) { $a += '-T' }
            $ok = Live 'docker' ($a + @('ollama', 'ollama', 'pull', $model))
        }
        if ($ok) { return $true }
        if ($try -lt 3) { Warn "Download interrupted; retrying ($try/3)..."; Start-Sleep 3 }
    }
    return $false
}

# Native mode on a PC that ran the Docker setup before: copy the models out of
# the ollama-models volume instead of downloading ~5 GB again.
function Copy-DockerModels {
    if ($DryRun) { return }
    $dest = $env:OLLAMA_MODELS
    if (-not $dest) { $dest = Join-Path $env:USERPROFILE '.ollama\models' }
    $parts = $ChatModel.Split(':')
    $manifest = "manifests/registry.ollama.ai/library/$($parts[0])/$($parts[1])"
    if (Test-Path (Join-Path $dest $manifest)) { return }
    & docker volume inspect $OllamaVolume *> $null; if ($LASTEXITCODE -ne 0) { return }
    & docker image inspect $OllamaImage *> $null; if ($LASTEXITCODE -ne 0) { return }
    & docker run --rm --entrypoint test -v "${OllamaVolume}:/src:ro" $OllamaImage -f "/src/models/$manifest" *> $null
    if ($LASTEXITCODE -ne 0) { return }
    $null = New-Item -ItemType Directory -Force -Path $dest
    if (-not (Run 'Copying models you already downloaded for Docker' 'docker' @('run', '--rm', '--entrypoint', 'cp', '-v', "${OllamaVolume}:/src:ro", '-v', "${dest}:/dst", $OllamaImage, '-a', '/src/models/.', '/dst/'))) {
        Warn "Couldn't copy them; downloading instead."
    }
}

function Use-CpuInstead([string]$why) {
    Warn $why
    Warn 'Falling back to the CPU. Fix the GPU setup and re-run to switch.'
    $script:Accel = 'cpu'; $script:Override = ''
}

function Start-DockerOllama {
    $pulled = Live 'docker' @('compose', 'pull', 'ollama')
    if (-not $pulled) { Die "Couldn't download the Ollama image. Check your internet connection." }
    if (-not (Run 'Starting Ollama' 'docker' @('compose', 'up', '-d', '--wait', 'ollama'))) {
        if ($script:Accel -ne 'cpu') {
            Use-CpuInstead "Ollama didn't start with the $($script:Accel.ToUpper()) GPU."
            Write-ComposeEnv
            if (-not (Run 'Starting Ollama on the CPU' 'docker' @('compose', 'up', '-d', '--wait', 'ollama'))) {
                Die "Ollama didn't start. See: cd coboltutor; docker compose logs ollama"
            }
        } else { Die "Ollama didn't start. See: cd coboltutor; docker compose logs ollama" }
    }
    if ($script:Accel -ne 'cpu' -and -not $DryRun) {
        Start-Sleep 2
        $logs = Invoke-Compose logs ollama 2>&1 | Out-String
        if ($logs -match '(?i)inference compute.*library=(cuda|rocm)') { Ok 'Ollama is using the GPU' }
        else { Warn "Ollama started, but its log doesn't show the GPU. Check: docker compose logs ollama" }
    }
}

function Step-Models {
    Step 'AI models + builds'
    if (-not $DryRun) { $null = New-Item -ItemType Directory -Force -Path $LogDir }
    if ($script:OllamaMode -eq 'docker' -and $DoModels) { Start-DockerOllama }

    # Start the slow builds now, so they run while the models download.
    Start-BackgroundBuilds

    if (-not $DoModels) { Info "Skipping model downloads (--no-models). They'll download on the first 'docker compose up'."; return }
    if ($script:OllamaMode -eq 'native') { Copy-DockerModels }

    Note 'Granite 4.2 8B is about 5 GB, so this can take a while. Safe to stop and re-run: downloads resume.'
    if (-not (Get-Model $ChatModel)) { Die "Couldn't download $ChatModel. Check your connection and run this again; it resumes." }
    if (-not (Get-Model $EmbedModel)) { Warn "Couldn't download $EmbedModel (not used yet; it'll be retried next time)." }
    W ''
    if ($script:OllamaMode -eq 'native') {
        # A copy of the model with a 16k context window; see coboltutor\ollama\Modelfile.
        $mf = Join-Path $AppDir 'ollama\Modelfile'
        if (-not (Run "Setting Granite's context window to 16k" $script:OllamaExe @('create', $NativeModel, '-f', $mf))) {
            Die "Couldn't create $NativeModel."
        }
    }
    Ok 'Models are ready'
}

# =============================================================================
# Step 6: start the stack
# =============================================================================
function Test-BackendReady {
    try { return [bool](Invoke-RestMethod -Uri "$BackendUrl/health" -TimeoutSec 3).model_ready } catch { return $false }
}

function Step-Start {
    Step 'Starting CobolTutor'
    if ($script:Jobs.ContainsKey('backend')) {
        if (-not (Wait-Bg 'backend' 'Building the backend image')) { Die "The backend image didn't build." }
    }
    if ($script:OllamaMode -eq 'native' -and -not $DryRun) {
        # Switching from the Docker setup: remove its Ollama container so it
        # doesn't hold memory (its models stay in the ollama-models volume).
        $ids = @()
        foreach ($svc in 'ollama', 'ollama-pull') {
            $ids += @(& docker ps -aq --filter 'label=com.docker.compose.project=coboltutor' --filter "label=com.docker.compose.service=$svc" 2>$null)
        }
        $ids = @($ids | Where-Object { $_ })
        if ($ids.Count -gt 0) { $null = Run 'Removing the Ollama container (this PC uses native Ollama)' 'docker' (@('rm', '-f') + $ids) }
    }
    if (-not (Run 'Starting the services' 'docker' @('compose', 'up', '-d', '--remove-orphans'))) {
        Die "The stack didn't start. See: cd coboltutor; docker compose logs"
    }
    if ($DoModels) {
        if (-not (Wait-Until 'Waiting for the tutor to be ready' 180 { Test-BackendReady })) {
            Die "The backend is up but the model isn't ready. Check: $BackendUrl/health"
        }
    } else {
        if (-not (Wait-Until 'Waiting for the backend' 60 { Test-Http "$BackendUrl/health" })) { Warn "The backend isn't answering yet." }
    }
}

# =============================================================================
# Step 7: the VS Code extension
# =============================================================================
function Step-Extension {
    Step 'VS Code extension'
    if (-not $DoExtension) { Info 'Skipped (--no-extension)'; return }
    if ($script:Jobs.ContainsKey('extension')) {
        if (-not (Wait-Bg 'extension' 'Building the extension')) { Die "The extension didn't build." }
    }
    $vsix = Join-Path $ExtDir "coboltutor-$ExtVersion.vsix"
    if ($DryRun) {
        $names = ($script:Editors | ForEach-Object { $_.Name }) -join ', '
        if (-not $names) { $names = 'no editors found' }
        Info "[dry-run] install $vsix into: $names"; return
    }
    if (-not (Test-Path $vsix)) { Die "The build finished but $vsix is missing." }
    Ok "Built coboltutor\extension\coboltutor-$ExtVersion.vsix"
    $failed = $false
    foreach ($e in $script:Editors) {
        if (-not (Run "Installing into $($e.Name)" $e.Cli @('--install-extension', $vsix, '--force'))) { $failed = $true }
    }
    if ($failed) { Note "To install by hand: Extensions view $S_ARROW ... menu $S_ARROW Install from VSIX $S_ARROW $vsix" }
}

# =============================================================================
# Done
# =============================================================================
function Show-Finish {
    W ''
    W ('  ' + ($H_LINE * 58)) Green
    if ($DryRun) { W "  $S_OK Dry run finished: nothing was changed." White }
    else { W "  $S_OK CobolTutor is installed!" Green }
    W ('  ' + ($H_LINE * 58)) Green
    W ''
    Kv 'Running on' (Get-AccelLabel)
    Kv 'Backend' $BackendUrl
    if ($script:Editors.Count -gt 0) { Kv 'Extension in' (($script:Editors | ForEach-Object { $_.Name }) -join ', ') }
    W ''
    W '  Try it' White
    W '    1. Open a COBOL file in VS Code (try coboltutor\examples\PAYROLL.cbl).'
    W "    2. Select some code and press Ctrl+Alt+E, or right-click $S_ARROW Explain Selected Code."
    W '    3. Or click the CobolTutor icon in the activity bar and ask a question.'
    W ''
    W '  Manage it ' White -NoNewline; W '(from the coboltutor folder)' DarkGray
    W '    docker compose up -d      start (it also restarts with Docker Desktop)'
    W '    docker compose down       stop (models are kept)'
    W '    docker compose logs -f    see what it''s doing'
    if ($script:OllamaMode -eq 'native') { Note 'Ollama runs on Windows outside Docker; keep the Ollama app running (it starts at sign-in).' }
    if (Test-Path $LogDir) { Note "Install logs: $LogDir" }
    W ''
}

# =============================================================================
# Main
# =============================================================================
try {
    Show-Banner
    if (-not $DryRun) { $null = New-Item -ItemType Directory -Force -Path $LogDir }
    Step-System
    Step-Docker
    Step-Accel
    Step-Editor
    Step-Models
    Step-Start
    Step-Extension
    Show-Finish
} finally {
    # Ctrl+C or an error: don't leave background builds running.
    foreach ($entry in $script:Jobs.Values) {
        if ($entry.Job.State -eq 'Running') { Stop-Job $entry.Job; Remove-Job $entry.Job -Force }
    }
}
