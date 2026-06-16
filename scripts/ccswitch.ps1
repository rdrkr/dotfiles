#Requires -Version 5.1
<#
.SYNOPSIS
    Multi-Account Switcher for Claude Code
.DESCRIPTION
    Simple tool to manage and switch between multiple Claude Code accounts.
    Supports Windows (Credential Manager), macOS (Keychain), Linux, and WSL.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Configuration
$script:BACKUP_DIR    = Join-Path $HOME '.claude-switch-backup'
$script:SEQUENCE_FILE = Join-Path $script:BACKUP_DIR 'sequence.json'

# ─────────────────────────────────────────────
# Platform detection
# ─────────────────────────────────────────────
function Get-Platform {
    if ($IsWindows -or $env:OS -eq 'Windows_NT') {
        if ($env:WSL_DISTRO_NAME) { return 'wsl' }
        return 'windows'
    }
    if ($IsMacOS) { return 'macos' }
    if ($IsLinux) {
        if ($env:WSL_DISTRO_NAME) { return 'wsl' }
        return 'linux'
    }
    return 'unknown'
}

function Test-RunningInContainer {
    if (Test-Path '/.dockerenv') { return $true }
    if (Test-Path '/proc/1/cgroup') {
        $cg = Get-Content '/proc/1/cgroup' -ErrorAction SilentlyContinue
        if ($cg -match 'docker|lxc|containerd|kubepods') { return $true }
    }
    if (Test-Path '/proc/self/mountinfo') {
        $mi = Get-Content '/proc/self/mountinfo' -ErrorAction SilentlyContinue
        if ($mi -match 'docker|overlay') { return $true }
    }
    if ($env:CONTAINER -or $env:container) { return $true }
    return $false
}

# ─────────────────────────────────────────────
# Dependencies
# ─────────────────────────────────────────────
function Test-Dependencies {
    # jq only needed on Unix platforms; Windows uses built-in ConvertFrom/To-Json
    $platform = Get-Platform
    if ($platform -in 'linux', 'wsl', 'macos') {
        if (-not (Get-Command jq -ErrorAction SilentlyContinue)) {
            Write-Error "Required command 'jq' not found. Install with: apt install jq (Linux) or brew install jq (macOS)"
            exit 1
        }
    }
}

# ─────────────────────────────────────────────
# JSON helpers
# ─────────────────────────────────────────────
function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    $raw = Get-Content -Raw -Path $Path -ErrorAction Stop
    return $raw | ConvertFrom-Json
}

function Write-JsonFile {
    param([string]$Path, [object]$Content)
    $json = $Content | ConvertTo-Json -Depth 20
    # Validate round-trip
    try { $json | ConvertFrom-Json | Out-Null }
    catch { Write-Error "Generated invalid JSON for ${Path}"; return }

    $tmp = "${Path}.tmp_$(Get-Random)"
    Set-Content -Path $tmp -Value $json -Encoding UTF8 -NoNewline
    Move-Item -Path $tmp -Destination $Path -Force

    $platform = Get-Platform
    if ($platform -eq 'windows') {
        try {
            $acl = Get-Acl $Path
            $acl.SetAccessRuleProtection($true, $false)
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,
                'FullControl', 'Allow')
            $acl.SetAccessRule($rule)
            Set-Acl -Path $Path -AclObject $acl -ErrorAction SilentlyContinue
        } catch { <# non-fatal #> }
    } else {
        chmod 600 $Path
    }
}

# ─────────────────────────────────────────────
# Validation
# ─────────────────────────────────────────────
function Test-EmailValid {
    param([string]$Email)
    return $Email -match '^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$'
}

# ─────────────────────────────────────────────
# Claude config path
# ─────────────────────────────────────────────
function Get-ClaudeConfigPath {
    $primary  = Join-Path $HOME '.claude' '.claude.json'
    $fallback = Join-Path $HOME '.claude.json'
    if (Test-Path $primary) {
        $obj = Read-JsonFile $primary
        if ($obj -and $obj.PSObject.Properties['oauthAccount']) {
            return $primary
        }
    }
    return $fallback
}

# ─────────────────────────────────────────────
# Directory setup
# ─────────────────────────────────────────────
function Initialize-Directories {
    $platform = Get-Platform
    foreach ($sub in @('', 'configs', 'credentials', 'scripts')) {
        $dir = if ($sub) { Join-Path $script:BACKUP_DIR $sub } else { $script:BACKUP_DIR }
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        if ($platform -ne 'windows') { chmod 700 $dir }
    }
}

# ─────────────────────────────────────────────
# Sequence file bootstrap
# ─────────────────────────────────────────────
function Initialize-SequenceFile {
    if (Test-Path $script:SEQUENCE_FILE) { return }
    # Write raw JSON so empty 'accounts' is {} not []
    $now = Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ' -AsUTC
    $raw = "{`n  `"activeAccountNumber`": null,`n  `"lastUpdated`": `"$now`",`n  `"sequence`": [],`n  `"accounts`": {}`n}"
    $tmp = "$($script:SEQUENCE_FILE).tmp_$(Get-Random)"
    Set-Content -Path $tmp -Value $raw -Encoding UTF8 -NoNewline
    Move-Item -Path $tmp -Destination $script:SEQUENCE_FILE -Force
    if ((Get-Platform) -ne 'windows') { chmod 600 $script:SEQUENCE_FILE }
}

# ─────────────────────────────────────────────
# Credential storage
# ─────────────────────────────────────────────
function Read-Credentials {
    $platform = Get-Platform
    switch ($platform) {
        'macos' {
            $r = & security find-generic-password -s 'Claude Code-credentials' -w 2>$null
            return $r
        }
        { $_ -in 'linux', 'wsl' } {
            $f = Join-Path $HOME '.claude' '.credentials.json'
            if (Test-Path $f) { return Get-Content -Raw $f }
            return ''
        }
        'windows' {
            try {
                $vault = New-Object Windows.Security.Credentials.PasswordVault
                $c = $vault.Retrieve('Claude Code-credentials', $env:USERNAME)
                $c.RetrievePassword()
                return $c.Password
            } catch {
                $f = Join-Path $HOME '.claude' '.credentials.json'
                if (Test-Path $f) { return Get-Content -Raw $f }
                return ''
            }
        }
    }
    return ''
}

function Write-Credentials {
    param([string]$Credentials)
    $platform = Get-Platform
    switch ($platform) {
        'macos' {
            & security add-generic-password -U -s 'Claude Code-credentials' -a $env:USER -w $Credentials 2>$null
        }
        { $_ -in 'linux', 'wsl' } {
            $dir = Join-Path $HOME '.claude'
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir -Force | Out-Null }
            $f = Join-Path $dir '.credentials.json'
            Set-Content -Path $f -Value $Credentials -NoNewline
            chmod 600 $f
        }
        'windows' {
            try {
                $vault = New-Object Windows.Security.Credentials.PasswordVault
                $c = New-Object Windows.Security.Credentials.PasswordCredential(
                    'Claude Code-credentials', $env:USERNAME, $Credentials)
                $vault.Add($c)
            } catch {
                $dir = Join-Path $HOME '.claude'
                if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir -Force | Out-Null }
                $f = Join-Path $dir '.credentials.json'
                Set-Content -Path $f -Value $Credentials -NoNewline
            }
        }
    }
}

function Read-AccountCredentials {
    param([string]$AccountNum, [string]$Email)
    $platform = Get-Platform
    if ($platform -eq 'macos') {
        return & security find-generic-password -s "Claude Code-Account-${AccountNum}-${Email}" -w 2>$null
    }
    $f = Join-Path $script:BACKUP_DIR 'credentials' ".claude-credentials-${AccountNum}-${Email}.json"
    if (Test-Path $f) { return Get-Content -Raw $f }
    return ''
}

function Write-AccountCredentials {
    param([string]$AccountNum, [string]$Email, [string]$Credentials)
    $platform = Get-Platform
    if ($platform -eq 'macos') {
        & security add-generic-password -U -s "Claude Code-Account-${AccountNum}-${Email}" -a $env:USER -w $Credentials 2>$null
        return
    }
    $f = Join-Path $script:BACKUP_DIR 'credentials' ".claude-credentials-${AccountNum}-${Email}.json"
    Set-Content -Path $f -Value $Credentials -NoNewline
    if ($platform -ne 'windows') { chmod 600 $f }
}

# ─────────────────────────────────────────────
# Config backup/restore
# ─────────────────────────────────────────────
function Read-AccountConfig {
    param([string]$AccountNum, [string]$Email)
    $f = Join-Path $script:BACKUP_DIR 'configs' ".claude-config-${AccountNum}-${Email}.json"
    if (Test-Path $f) { return Get-Content -Raw $f }
    return ''
}

function Write-AccountConfig {
    param([string]$AccountNum, [string]$Email, [string]$Config)
    $f = Join-Path $script:BACKUP_DIR 'configs' ".claude-config-${AccountNum}-${Email}.json"
    Set-Content -Path $f -Value $Config -NoNewline
    if ((Get-Platform) -ne 'windows') { chmod 600 $f }
}

function Backup-AccountScript {
    param([string]$AccountNum, [string]$Email)
    $src = Join-Path $HOME '.claude' 'fetch-claude-usage.js'
    $dst = Join-Path $script:BACKUP_DIR 'scripts' ".fetch-claude-usage-${AccountNum}-${Email}.js"
    if (Test-Path $src) { Copy-Item $src $dst -Force }
}

function Restore-AccountScript {
    param([string]$AccountNum, [string]$Email)
    $src = Join-Path $script:BACKUP_DIR 'scripts' ".fetch-claude-usage-${AccountNum}-${Email}.js"
    $dst = Join-Path $HOME '.claude' 'fetch-claude-usage.js'
    Remove-Item $dst -Force -ErrorAction SilentlyContinue
    if (Test-Path $src) {
        Copy-Item $src $dst -Force
        if ((Get-Platform) -ne 'windows') { chmod 755 $dst }
    }
}

# ─────────────────────────────────────────────
# Current account
# ─────────────────────────────────────────────
function Get-CurrentAccount {
    $cfgPath = Get-ClaudeConfigPath
    if (-not (Test-Path $cfgPath)) { return 'none' }
    $obj = Read-JsonFile $cfgPath
    if (-not $obj) { return 'none' }
    $email = $obj.oauthAccount.emailAddress
    if ($email) { return $email }
    return 'none'
}

# ─────────────────────────────────────────────
# Sequence helpers
# ─────────────────────────────────────────────
function Get-NextAccountNumber {
    if (-not (Test-Path $script:SEQUENCE_FILE)) { return '1' }
    $seq  = Read-JsonFile $script:SEQUENCE_FILE
    $props = $seq.accounts.PSObject.Properties
    if (-not $props -or @($props).Count -eq 0) { return '1' }
    $keys  = @(@($props.Name) | ForEach-Object { [int]$_ })
    if ($keys.Count -eq 0) { return '1' }
    return [string](($keys | Measure-Object -Maximum).Maximum + 1)
}

function Test-AccountExists {
    param([string]$Email)
    if (-not (Test-Path $script:SEQUENCE_FILE)) { return $false }
    $seq = Read-JsonFile $script:SEQUENCE_FILE
    foreach ($prop in $seq.accounts.PSObject.Properties) {
        if ($prop.Value.email -eq $Email) { return $true }
    }
    return $false
}

function Resolve-AccountIdentifier {
    param([string]$Identifier)
    if ($Identifier -match '^\d+$') { return $Identifier }
    if (-not (Test-Path $script:SEQUENCE_FILE)) { return '' }
    $seq = Read-JsonFile $script:SEQUENCE_FILE
    foreach ($prop in $seq.accounts.PSObject.Properties) {
        if ($prop.Value.email -eq $Identifier) { return $prop.Name }
    }
    return ''
}

# ─────────────────────────────────────────────
# Claude process detection
# ─────────────────────────────────────────────
function Test-ClaudeRunning {
    $procs = Get-Process -Name 'claude' -ErrorAction SilentlyContinue
    return ($null -ne $procs -and $procs.Count -gt 0)
}

function Wait-ForClaudeClose {
    if (-not (Test-ClaudeRunning)) { return }
    Write-Host 'Claude Code is running. Please close it first.'
    Write-Host 'Waiting for Claude Code to close...'
    while (Test-ClaudeRunning) { Start-Sleep -Seconds 1 }
    Write-Host 'Claude Code closed. Continuing...'
}

# ─────────────────────────────────────────────
# Commands
# ─────────────────────────────────────────────
function Invoke-AddAccount {
    Initialize-Directories
    Initialize-SequenceFile

    $currentEmail = Get-CurrentAccount
    if ($currentEmail -eq 'none') {
        Write-Error 'No active Claude account found. Please log in first.'
        exit 1
    }
    if (Test-AccountExists $currentEmail) {
        Write-Host "Account $currentEmail is already managed."
        return
    }

    $accountNum    = Get-NextAccountNumber
    $cfgPath       = Get-ClaudeConfigPath
    $currentCreds  = Read-Credentials
    $currentConfig = Get-Content -Raw $cfgPath

    if (-not $currentCreds) {
        Write-Error 'No credentials found for current account'
        exit 1
    }

    $cfgObj      = Read-JsonFile $cfgPath
    $accountUuid = $cfgObj.oauthAccount.accountUuid

    Write-AccountCredentials -AccountNum $accountNum -Email $currentEmail -Credentials $currentCreds
    Write-AccountConfig      -AccountNum $accountNum -Email $currentEmail -Config $currentConfig
    Backup-AccountScript     -AccountNum $accountNum -Email $currentEmail

    # Update sequence.json
    $seq = Read-JsonFile $script:SEQUENCE_FILE
    $now = Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ' -AsUTC

    # Add-Member chokes on numeric-looking strings; assign via PSObject directly
    $newEntry = [pscustomobject]@{ email = $currentEmail; uuid = $accountUuid; added = $now }
    $seq.accounts.PSObject.Properties.Add(
        [System.Management.Automation.PSNoteProperty]::new($accountNum, $newEntry))

    $seq.sequence            = @($seq.sequence) + @([int]$accountNum)
    $seq.activeAccountNumber = [int]$accountNum
    $seq.lastUpdated         = $now

    Write-JsonFile -Path $script:SEQUENCE_FILE -Content $seq
    Write-Host "Added Account ${accountNum}: $currentEmail"
}

function Invoke-RemoveAccount {
    param([string]$Identifier)
    if (-not $Identifier) {
        Write-Host 'Usage: ccswitch --remove-account <account_number|email>'
        exit 1
    }
    if (-not (Test-Path $script:SEQUENCE_FILE)) {
        Write-Error 'No accounts are managed yet'; exit 1
    }

    if ($Identifier -match '^\d+$') {
        $accountNum = $Identifier
    } else {
        if (-not (Test-EmailValid $Identifier)) {
            Write-Error "Invalid email format: $Identifier"; exit 1
        }
        $accountNum = Resolve-AccountIdentifier $Identifier
        if (-not $accountNum) {
            Write-Error "No account found with email: $Identifier"; exit 1
        }
    }

    $seq         = Read-JsonFile $script:SEQUENCE_FILE
    $accountProp = $seq.accounts.PSObject.Properties[$accountNum]
    if (-not $accountProp) {
        Write-Error "Account-$accountNum does not exist"; exit 1
    }

    $email         = $accountProp.Value.email
    $activeAccount = [string]$seq.activeAccountNumber

    if ($activeAccount -eq $accountNum) {
        Write-Warning "Account-$accountNum ($email) is currently active"
    }

    $confirm = Read-Host "Are you sure you want to permanently remove Account-$accountNum ($email)? [y/N]"
    if ($confirm -notin @('y', 'Y')) {
        Write-Host 'Cancelled'; return
    }

    # Remove stored data
    $platform = Get-Platform
    if ($platform -eq 'macos') {
        & security delete-generic-password -s "Claude Code-Account-${accountNum}-${email}" 2>$null
    } else {
        Remove-Item (Join-Path $script:BACKUP_DIR 'credentials' ".claude-credentials-${accountNum}-${email}.json") `
            -Force -ErrorAction SilentlyContinue
    }
    Remove-Item (Join-Path $script:BACKUP_DIR 'configs'  ".claude-config-${accountNum}-${email}.json")            -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $script:BACKUP_DIR 'scripts' ".fetch-claude-usage-${accountNum}-${email}.js")        -Force -ErrorAction SilentlyContinue

    # Update sequence.json
    $seq.accounts.PSObject.Properties.Remove($accountNum)
    $seq.sequence    = @($seq.sequence | Where-Object { $_ -ne [int]$accountNum })
    $seq.lastUpdated = Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ' -AsUTC

    Write-JsonFile -Path $script:SEQUENCE_FILE -Content $seq
    Write-Host "Account-$accountNum ($email) has been removed"
}

function Invoke-List {
    if (-not (Test-Path $script:SEQUENCE_FILE)) {
        Write-Host 'No accounts are managed yet.'
        Invoke-FirstRunSetup
        return
    }

    $currentEmail = Get-CurrentAccount
    $seq          = Read-JsonFile $script:SEQUENCE_FILE

    $activeAccountNum = ''
    if ($currentEmail -ne 'none') {
        foreach ($prop in $seq.accounts.PSObject.Properties) {
            if ($prop.Value.email -eq $currentEmail) {
                $activeAccountNum = $prop.Name
                break
            }
        }
    }

    Write-Host 'Accounts:'
    foreach ($num in $seq.sequence) {
        $numStr = [string]$num
        $info   = $seq.accounts.PSObject.Properties[$numStr].Value
        if ($numStr -eq $activeAccountNum) {
            Write-Host "  ${numStr}: $($info.email) (active)"
        } else {
            Write-Host "  ${numStr}: $($info.email)"
        }
    }
}

function Invoke-Switch {
    if (-not (Test-Path $script:SEQUENCE_FILE)) {
        Write-Error 'No accounts are managed yet'; exit 1
    }

    $currentEmail = Get-CurrentAccount
    if ($currentEmail -eq 'none') {
        Write-Error 'No active Claude account found'; exit 1
    }

    if (-not (Test-AccountExists $currentEmail)) {
        Write-Host "Notice: Active account '$currentEmail' was not managed."
        Invoke-AddAccount
        $seq        = Read-JsonFile $script:SEQUENCE_FILE
        $accountNum = $seq.activeAccountNumber
        Write-Host "It has been automatically added as Account-$accountNum."
        Write-Host "Please run 'ccswitch --switch' again to switch to the next account."
        return
    }

    $seq       = Read-JsonFile $script:SEQUENCE_FILE
    $activeNum = [string]$seq.activeAccountNumber
    $sequence  = @($seq.sequence | ForEach-Object { [string]$_ })

    $currentIndex = [Array]::IndexOf($sequence, $activeNum)
    $nextIndex    = ($currentIndex + 1) % $sequence.Count
    $nextAccount  = $sequence[$nextIndex]

    Invoke-PerformSwitch $nextAccount
}

function Invoke-SwitchTo {
    param([string]$Identifier)
    if (-not $Identifier) {
        Write-Host 'Usage: ccswitch --switch-to <account_number|email>'
        exit 1
    }
    if (-not (Test-Path $script:SEQUENCE_FILE)) {
        Write-Error 'No accounts are managed yet'; exit 1
    }

    if ($Identifier -match '^\d+$') {
        $targetAccount = $Identifier
    } else {
        if (-not (Test-EmailValid $Identifier)) {
            Write-Error "Invalid email format: $Identifier"; exit 1
        }
        $targetAccount = Resolve-AccountIdentifier $Identifier
        if (-not $targetAccount) {
            Write-Error "No account found with email: $Identifier"; exit 1
        }
    }

    $seq = Read-JsonFile $script:SEQUENCE_FILE
    if (-not $seq.accounts.PSObject.Properties[$targetAccount]) {
        Write-Error "Account-$targetAccount does not exist"; exit 1
    }

    Invoke-PerformSwitch $targetAccount
}

function Invoke-PerformSwitch {
    param([string]$TargetAccount)

    $seq            = Read-JsonFile $script:SEQUENCE_FILE
    $currentAccount = [string]$seq.activeAccountNumber
    $targetEmail    = $seq.accounts.PSObject.Properties[$TargetAccount].Value.email
    $currentEmail   = Get-CurrentAccount
    $cfgPath        = Get-ClaudeConfigPath

    # Step 1 – backup current account state
    $currentCreds  = Read-Credentials
    $currentConfig = Get-Content -Raw $cfgPath

    Write-AccountCredentials -AccountNum $currentAccount -Email $currentEmail -Credentials $currentCreds
    Write-AccountConfig      -AccountNum $currentAccount -Email $currentEmail -Config $currentConfig
    Backup-AccountScript     -AccountNum $currentAccount -Email $currentEmail

    # Step 2 – retrieve target account backup
    $targetCreds  = Read-AccountCredentials -AccountNum $TargetAccount -Email $targetEmail
    $targetConfig = Read-AccountConfig      -AccountNum $TargetAccount -Email $targetEmail

    if (-not $targetCreds -or -not $targetConfig) {
        Write-Error "Missing backup data for Account-$TargetAccount"; exit 1
    }

    # Step 3 – activate target account
    Write-Credentials $targetCreds
    Restore-AccountScript -AccountNum $TargetAccount -Email $targetEmail

    $targetCfgObj = $targetConfig | ConvertFrom-Json
    $oauthSection = $targetCfgObj.oauthAccount
    if (-not $oauthSection) {
        Write-Error 'Invalid oauthAccount in backup'; exit 1
    }

    $currentCfgObj = Read-JsonFile $cfgPath
    $currentCfgObj.oauthAccount = $oauthSection
    Write-JsonFile -Path $cfgPath -Content $currentCfgObj

    # Step 4 – update sequence state
    $seq.activeAccountNumber = [int]$TargetAccount
    $seq.lastUpdated         = Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ' -AsUTC
    Write-JsonFile -Path $script:SEQUENCE_FILE -Content $seq

    Write-Host "Switched to Account-$TargetAccount ($targetEmail)"
    Invoke-List
    Write-Host ''
    Write-Host 'Please restart Claude Code to use the new authentication.'
    Write-Host ''
}

function Invoke-FirstRunSetup {
    $currentEmail = Get-CurrentAccount
    if ($currentEmail -eq 'none') {
        Write-Host 'No active Claude account found. Please log in first.'
        return
    }
    $response = Read-Host "No managed accounts found. Add current account ($currentEmail) to managed list? [Y/n]"
    if ($response -in @('n', 'N')) {
        Write-Host "Setup cancelled. You can run 'ccswitch --add-account' later."
        return
    }
    Invoke-AddAccount
}

# ─────────────────────────────────────────────
# Usage
# ─────────────────────────────────────────────
function Show-Usage {
    @"
Multi-Account Switcher for Claude Code
Usage: ccswitch [COMMAND]

Commands:
  --add-account                    Add current account to managed accounts
  --remove-account <num|email>     Remove account by number or email
  --list                           List all managed accounts
  --switch                         Rotate to next account in sequence
  --switch-to <num|email>          Switch to specific account number or email
  --help                           Show this help message

Examples:
  ccswitch --add-account
  ccswitch --list
  ccswitch --switch
  ccswitch --switch-to 2
  ccswitch --switch-to user@example.com
  ccswitch --remove-account user@example.com
"@
}

# ─────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────
function Main {
    param([string[]]$Arguments)

    # Root check (Unix only – no direct equivalent on Windows)
    $platform = Get-Platform
    if ($platform -notin @('windows')) {
        $uid = & id -u 2>$null
        if ($uid -eq '0' -and -not (Test-RunningInContainer)) {
            Write-Error 'Do not run this script as root (unless running in a container)'
            exit 1
        }
    }

    Test-Dependencies

    $cmd = if ($Arguments.Count -gt 0) { $Arguments[0] } else { '' }

    switch ($cmd) {
        '--add-account'    { Invoke-AddAccount }
        '--remove-account' { Invoke-RemoveAccount -Identifier ($Arguments | Select-Object -Skip 1 -First 1) }
        '--list'           { Invoke-List }
        '--switch'         { Invoke-Switch }
        '--switch-to'      { Invoke-SwitchTo -Identifier ($Arguments | Select-Object -Skip 1 -First 1) }
        '--help'           { Show-Usage }
        ''                 { Show-Usage }
        default {
            Write-Host "Error: Unknown command '$cmd'"
            Show-Usage
            exit 1
        }
    }
}

Main -Arguments $args

