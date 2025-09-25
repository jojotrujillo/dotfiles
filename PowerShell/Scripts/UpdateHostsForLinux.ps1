param (
    [Parameter(Mandatory=$true)]
    [string]$DistroName,

    [Parameter(Mandatory=$true)]
    [string]$HostName,

    [Parameter(Mandatory=$true)]
    [string]$HostsFile,
    [bool]$DryRun
)

Import-Module Log

if ($DryRun -eq $null -or (-not $DryRun)) {
    $currentUser = New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        Log -Message "The current PowerShell session is not running as Administrator. Start PowerShell by using the Run as Administrator option, and then try running the script again." -TypeOfMessage "error"
        exit 1
    }
}

try {
    # Forward a CLI command out of PowerShell via wsl.exe to get the instance's IP address
    $distrosIpAddress = wsl -d $DistroName -- bash -lc "ip -4 addr show eth0 | awk '/inet / {print $2}' | cut -d/ -f1"
    $distrosIpAddress = ($distrosIpAddress.Trim() -replace '^inet\s+','')

    if (-not [string]::IsNullOrWhiteSpace($distrosIpAddress) -and $distrosIpAddress -match '^\d{1,3}(.\d{1,3}){3}$') {
        Log -DryRun $DryRun -Message "Fetched ${DistroName}'s IP address: $distrosIpAddress." -TypeOfMessage "info"
    } else {
        Log -DryRun $DryRun -Message "Encountered a problem fetching ${DistroName}'s IP address." -TypeOfMessage "error"
        exit 1
    }

    if (-not (Test-Path $HostsFile)) {
        Log -DryRun $DryRun -Message "Hosts file not found at ${HostsFile}." -TypeOfMessage "error"
        exit 1
    } else {
        Log -DryRun $DryRun -Message "Found hosts file at ${HostsFile}." -TypeOfMessage "info"
    }

    # Making a backup and using -Force because this is a privileged directory
    $fileBackup = "$HostsFile.bak"
    if ($DryRun) {
        Log -DryRun $DryRun -Message "Would create file backup at ${fileBackup}." -TypeOfMessage "info"
    } else {
        Copy-Item -Path $HostsFile -Destination $fileBackup -Force
        Log -Message "Created file backup at ${fileBackup}." -TypeOfMessage "info"
    }
    
    $originalLines = Get-Content -Path $HostsFile -ErrorAction Stop

    # Find an existing entry for HostName
    $existingLineIndex = $null
    for ($i = 0; $i -lt $originalLines.Count; $i++) {
        if ($originalLines[$i] -match "^\s*\S+\s+$([regex]::Escape($HostName))\s*$" -or $originalLines[$i] -match "\s+$HostName(\s|$)" ) {
            $existingLineIndex = $i
            break
        }
    }

    if ($existingLineIndex -eq $null) {
        $newLine = "$distrosIpAddress $HostName"
        Log -DryRun $DryRun -Message "No existing entry for $HostName found in ${HostsFile}. Adding ${newLine}." -TypeOfMessage "warning"

        $updatedLines = $originalLines + $newLine
        if ($DryRun) {
            Log -DryRun $DryRun -Message "Would add new entry in ${HostsFile}." -TypeOfMessage "info"
        } else {
            Set-Content -Path $HostsFile -Value $updatedLines -Encoding ASCII
            Log -Message "Successfully added new entry in ${HostsFile}." -TypeOfMessage "info"
        }
        exit 0
    } else {
        $previousEntry = $originalLines[$existingLineIndex]
        Log -DryRun $DryRun -Message "Found previous entry: ${previousEntry}, in ${HostsFile}." -TypeOfMessage "warning"

        # Attempt to extract IP address (handles both "IP  hostname" and if line has extra spaces)
        if ($previousEntry -match "^\s*([0-9]{1,3}(?:\.[0-9]{1,3}){3})\s+.*$") {
            $previousIpAddress = $Matches[1]
        } else {
            $previousIpAddress = $null
        }

        if ($null -eq $previousIpAddress) {
            # Couldn't parse the IP address; replace the line entirely with the desired one
            $originalLines[$existingLineIndex] = "$distrosIpAddress $HostName"
            if ($DryRun) {
                Log -DryRun $DryRun -Message "Would update entry for $HostName to $distrosIpAddress (parsed IP address unavailable)." -TypeOfMessage "info"
            } else {
                Set-Content -Path $HostsFile -Value $originalLines -Encoding ASCII
                Log -Message "Updated entry for $HostName to $distrosIpAddress (parsed IP address unavailable)." -TypeOfMessage "info"
            }
            exit 0
        }

        if ($previousIpAddress -eq $distrosIpAddress) {
            if ($DryRun) {
                Log -DryRun $DryRun -Message "Entry for $HostName would already be up-to-date ($distrosIpAddress). No changes would be made." -TypeOfMessage "info"
                Log -DryRun $DryRun -Message "Would remove ${fileBackup}. No changes would be made." -TypeOfMessage "warning"
            } else {
                Remove-Item -Path $fileBackup -Force
                Log -Message "Entry for $HostName already up-to-date ($distrosIpAddress). No changes made." -TypeOfMessage "info"
                Log -Message "Removing ${fileBackup}. No changes made." -TypeOfMessage "warning"
            }
            exit 0
        } else {
            $updatedLine = "$distrosIpAddress $HostName"
            $originalLines[$existingLineIndex] = $updatedLine
            if ($DryRun) {
                Log -DryRun $DryRun -Message "Would update entry for $HostName to ${distrosIpAddress}." -TypeOfMessage "info"
            } else {
                Set-Content -Path $HostsFile -Value $originalLines -Encoding ASCII
                Log -Message "Updated entry for $HostName to ${distrosIpAddress}." -TypeOfMessage "info"
            }
            exit 0
        }
    }
} catch {
    Log -DryRun $DryRun -Message "Failed to update hosts file for ${DistroName}." -TypeOfMessage "error"
    # Rethrow error
    throw
}
