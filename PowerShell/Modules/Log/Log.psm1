function Log {
    param (
        [bool]$DryRun,
        [string]$Message,
        [string]$TypeOfMessage
    )

    if ($DryRun) {
        $Message = "[DRY_RUN]: $Message"
    }

    switch ($TypeOfMessage) {
        "info" {
            Write-Host "[INFO]: $Message"
        }
        "warning" {
            Write-Warning $Message
        }
        "error" {
            Write-Error "[ERROR]: $Message"
        }
    }    
}

Export-ModuleMember -Function Log
