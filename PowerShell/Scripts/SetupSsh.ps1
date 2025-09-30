[CmdletBinding(DefaultParameterSetName="Default")]
param (
    [Parameter(Mandatory=$true)]
    [string]$DistroName,

    [Parameter(Mandatory=$true)]
    [bool]$DryRun,

    [Parameter(Mandatory=$true)]
    [string]$Platform,

    [Parameter(Mandatory=$true)]
    [string]$Username,

    [Parameter(Mandatory=$true)]
    [string]$TargetDir1,

    [Parameter(Mandatory=$true)]
    [string]$TargetDir2,

    [Parameter(Mandatory=$true)]
    [string]$TargetDir3,

    [Parameter(Mandatory=$true)]
    [string]$SshKeyFileName,

    [Parameter(Mandatory=$true)]
    [string]$PortToForward,
    [string]$Signal,

    [Parameter(ParameterSetName='NeedToUpdateHostsFile')]
    [switch]$NeedToUpdateHostsFile,

    [Parameter(Mandatory=$true, ParameterSetName='NeedToUpdateHostsFile')]
    [string]$HostName,

    [Parameter(Mandatory=$true, ParameterSetName='NeedToUpdateHostsFile')]
    [string]$HostsFile,

    [Parameter(Mandatory=$true, ParameterSetName='NeedToUpdateHostsFile')]
    [bool]$UpdateHostsDryRun
)

Import-Module Log

function Convert-WinToWslPath([string]$winPath) {
    $full = [System.IO.Path]::GetFullPath($winPath)
    # Expect something like C:\Users\user\Documents\...
    if ($full -match '^[A-Za-z]:\\') {
        $drive = $matches[0].Substring(0,1).ToLower()
        $rest  = $full.Substring(3) -replace '\\','/'
        return "/mnt/$drive/$rest"
    } else {
        throw "Cannot convert path: $winPath"
    }
}

function Invoke-RemoteCommand {
    param(
        [string]$platform,
        [string]$distro,
        [string]$command,
        [string]$action,
        [string]$signal,
        [string]$username,
        [string]$fromDir = $null,
        [string]$toDir = $null
    )

    $commandOutput = $null
    if ($platform -eq "WSL") {
        $commandOutput = wsl -d $distro -- bash -lc $command
        if ($action -eq "run") { Write-Host "`n" }
        return $commandOutput
    } else {
        if ($action -eq "copyto") {
            $commandOutput = VBoxManage guestcontrol $distro copyto $fromDir $toDir --username $username --password $signal
            if ($LASTEXITCODE -ne 0) {
                throw "Remote command failed. Inspect error output."
            } else {
                return $commandOutput
            }
        } else {
            $commandOutput = VBoxManage guestcontrol $distro run --username $username --password $signal --exe /bin/sh -- -c $command
            if ($LASTEXITCODE -ne 0) {
                throw "Remote command failed. Inspect error output."
            } else {
                Write-Host "`n"
                return $commandOutput
            }
        }
    }
}

try {
    if (-not $DryRun) {
        if (-not $PSBoundParameters.ContainsKey('Signal') -or [string]::IsNullOrEmpty($Signal)) {
            $secureSignal = Read-Host -AsSecureString "Enter `"signal`" for $DistroName on $Platform"
        }
    }

    if ($NeedToUpdateHostsFile) {
        Log -DryRun $DryRun -Message "Calling UpdateHostsForLinux.ps1 to update hosts file for ${DistroName}." -TypeOfMessage "warning"
        & ".\UpdateHostsForLinux.ps1" $DistroName $HostName $HostsFile $UpdateHostsDryRun
        Log -DryRun $DryRun -Message "Updated hosts file for ${DistroName}." -TypeOfMessage "info"
    }

    $sshStatusRaw = $DryRun ? "Active: active (running)" : $null
    if ($DryRun) {
        Log -DryRun $DryRun -Message "Would update ${DistroName}'s packages, install OpenSSH server, then start and verify the service status." -TypeOfMessage "info"
    } else {
        $plainSignal  = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureSignal))

        # VirtualBox VM needs to be powered off for modifyvm command to work
        if ($Platform -eq "VBox") {
            $portForwardings = VBoxManage showvminfo $DistroName --machinereadable | Select-String '^Forwarding\([0-9]+\)="SSH Port Forwarding,tcp,.*,22"$'
            
            if ($portForwardings.Count -eq 0) {
                Log -Message "No existing SSH port forwarding found for $DistroName. Adding new rule to forward host port $PortToForward to guest port 22." -TypeOfMessage "warning"

                VBoxManage modifyvm $DistroName --natpf1 "SSH Port Forwarding,tcp,,$PortToForward,,22"
                VBoxManage startvm $DistroName --type gui

                Log -Message "Waiting 60 seconds for VM to boot up..." -TypeOfMessage "warning"
                Start-Sleep -Seconds 60

                $vmRunning = $false
                while (-not $vmRunning) {
                    $vmStatus = (VBoxManage showvminfo $DistroName --machinereadable | Select-String "VMState=").ToString().Split('=')[1].Trim().Replace('"', '')

                    if ($vmStatus -eq "running") {
                        $vmRunning = $true
                        Log -Message "VM '$DistroName' is now running. Continuing script execution." -TypeOfMessage "warning"
                    } else {
                        Log -Message "VM '$DistroName' is not yet running (Current status: $vmStatus). Waiting another 60 seconds..." -TypeOfMessage "warning"
                        Start-Sleep -Seconds 60
                    }
                }
            } else {
                Log -Message "Existing SSH port forwarding found for $DistroName. No changes made." -TypeOfMessage "info"
            }
        }
        # TODO: Cleanup forwarded commands
        Invoke-RemoteCommand -platform $Platform -distro $DistroName -command "echo $plainSignal | sudo -S DEBIAN_FRONTEND=noninteractive apt -y update && sudo -S DEBIAN_FRONTEND=noninteractive apt -y install openssh-server" -action "run" -signal $plainSignal -username $Username
        Invoke-RemoteCommand -platform $Platform -distro $DistroName -command "echo $plainSignal | sudo -S systemctl enable --now ssh" -action "run" -signal $plainSignal -username $Username
        $sshStatusRaw = Invoke-RemoteCommand -platform $Platform -distro $DistroName -command "echo $plainSignal | sudo -S systemctl status ssh" -action "run" -signal $plainSignal -username $Username
    }

    $sshStatus = $null
    if ($sshStatusRaw -like "*Active: active (running)*") {
       $sshStatus = "Running"
    } elseif ($sshStatusRaw -like "*Active: inactive (dead)*") {
        $sshStatus = "Stopped"
    } else {
        $sshStatus = "Unknown or Error"
    }

    Log -DryRun $DryRun -Message "Status of $DistroName's SSH server on ${Platform}: $sshStatus." -TypeOfMessage "info"
    if ($sshStatus -eq "Running") {
        $resourcesWinPath = Join-Path $PSScriptRoot "..\..\resources"
        $resourcesPath = Convert-WinToWslPath -winPath $resourcesWinPath

        $sshPublicKeyWinPath = Join-Path $env:USERPROFILE ".ssh\$SshKeyFileName"
        $sshPublicKeyPath = Convert-WinToWslPath -winPath $sshPublicKeyWinPath

        $gitConfigPattern = Join-Path $env:USERPROFILE ".gitconfig*"
        $gitConfigFiles = Get-ChildItem -Path $gitConfigPattern -File
        
        Log -DryRun $DryRun -Message "Copying resources directory to $DistroName on ${Platform}." -TypeOfMessage "info"
        Log -DryRun $DryRun -Message "Copying SSH public key to $DistroName on ${Platform}." -TypeOfMessage "info"
        Log -DryRun $DryRun -Message "Copying Git configs to $DistroName on ${Platform}." -TypeOfMessage "info"
        
        if (-not $DryRun) {
            Invoke-RemoteCommand -platform $Platform -distro $DistroName -command "cp -r $resourcesPath ~/source" -action "copyto" -signal $plainSignal -fromDir "$resourcesWinPath" -toDir $TargetDir1 -username $Username
            Invoke-RemoteCommand -platform $Platform -distro $DistroName -command "cp $sshPublicKeyPath ~/.ssh" -action "copyto" -signal $plainSignal -fromDir "$sshPublicKeyWinPath" -toDir $TargetDir2 -username $Username
            foreach ($file in $gitConfigFiles) {
                $gitConfigWinPath = $file.FullName
                $gitConfigPath = Convert-WinToWslPath -winPath $gitConfigWinPath

                Invoke-RemoteCommand -platform $Platform -distro $DistroName -command "cp $gitConfigPath ~/" -action "copyto" -signal $plainSignal -fromDir "$gitConfigWinPath" -toDir $TargetDir3 -username $Username
            }
        }
        
        if ($Platform -eq "WSL") {
            Log -DryRun $DryRun -Message "A new tab opened for you to SSH into $DistroName on ${Platform}." -TypeOfMessage "info"
            if (-not $DryRun) {
                wt new-tab -p "$DistroName"
            }
        } else {
            Log -DryRun $DryRun -Message "You may now SSH into $DistroName on ${Platform}." -TypeOfMessage "info"
        }
    } else {
        Log -Message "Encountered error when starting SSH server." -TypeOfMessage "error"
        exit 1
    }
} catch {
    Log -DryRun $DryRun -Message "Failed to setup SSH for $DistroName on ${Platform}." -TypeOfMessage "error"
    # Rethrow error
    throw
}
