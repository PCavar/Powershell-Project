function New-PCDC {
    $pathForDCTemplate = "C:\VM-Sysprep\Win2019\Virtual Hard Disks\Win2019Template.vhdx"
    $pathForDCVirtualMachines = "C:\VM-Sysprep\Win2019\Virtual Machines"
    $pathForVHDX = "C:\VM-Sysprep\Win2019\Virtual Hard Disks\$choosenDCToProvision.vhdx"

    New-VHD -ParentPath "$pathForDCTemplate" -Path ($pathForVHDX) -Differencing -Verbose
    
	New-VM `
	-Name $choosenDCToProvision `
	-MemoryStartupBytes 2GB `
	-BootDevice VHD `
    -VHDPath $pathForVHDX `
	-Path $pathForDCVirtualMachines `
	-Generation 2 `
	-Switch LAN 

    Set-VMProcessor -VMName $choosenDCToProvision -Count 4 -Verbose

    Enable-VMIntegrationService -VMName $choosenDCToProvision -Name "Guest Service Interface" -Verbose
    Set-VM -VMName $choosenDCToProvision -AutomaticCheckpointsEnabled $false -Verbose
  
    Write-Host "VM created" -ForegroundColor Cyan
    Start-VM $choosenDCToProvision

    Invoke-Command -VMName $choosenDCToProvision -Credential $choosenDCToProvision\Administrator -ScriptBlock {
        Start-Sleep -Seconds 15
        Rename-Computer -NewName $Using:choosenDCToProvision
        Start-Sleep -Seconds 3
        Restart-Computer -Force
    }
}

function New-PCVM {
    $pathForVMTemplate = "C:\VM-Sysprep\VM10\Virtual Hard Disks\VM10Template.vhdx"
    $pathForVMVirtualMachines = "C:\VM-Sysprep\VM10\Virtual Machines"
    $pathForVHDX = "C:\VM-Sysprep\VM10\Virtual Hard Disks\$choosenVMToProvision.vhdx"


    New-VHD -ParentPath "$pathForVMTemplate" -Path ($pathForVHDX) -Differencing -Verbose
    
	New-VM `
	-Name $choosenVMToProvision `
	-MemoryStartupBytes 2GB `
	-BootDevice VHD `
    -VHDPath $pathForVHDX `
	-Path $pathForVMVirtualMachines `
	-Generation 2 `
	-Switch LAN 

    Set-VMProcessor -VMName $choosenVMToProvision -Count 4 -Verbose

    Enable-VMIntegrationService -VMName $choosenVMToProvision -Name "Guest Service Interface" -Verbose
    Set-VM -VMName $choosenVMToProvision -AutomaticCheckpointsEnabled $false -Verbose
  
    Write-Host "VM created" -ForegroundColor Cyan
    Start-VM $choosenVMToProvision

    Invoke-Command -VMName $choosenVMToProvision -Credential $choosenVMToProvision\Administrator -ScriptBlock {
        Start-Sleep -Seconds 15
        Rename-Computer -NewName $Using:choosenVMToProvision
        Start-Sleep -Seconds 3
        Restart-Computer -Force
    }
}
function Remove-PCDC {
    $pathForDCVirtualMachines = "C:\VM-Sysprep\Win2019\Virtual Machines\$removeChoosenDC"
    $pathForVHDX = "C:\VM-Sysprep\Win2019\Virtual Hard Disks\$removeChoosenDC.vhdx"

    if(((Get-VM $removeChoosenDC).State) -eq "Running") {
        Write-Host "Shutting down $removeChoosenDC before deleting" -ForegroundColor Cyan
        Get-VM -Name $removeChoosenDC | Stop-VM
        Remove-VM $removeChoosenDC
        Remove-Item $pathForVHDX , $pathForDCVirtualMachines
    } else {
        Remove-VM $removeChoosenDC
        Remove-Item $pathForVHDX , $pathForDCVirtualMachines
        Write-Host "Virtual Machine $removeChoosenDC removed!" -ForegroundColor Cyan
    }
}
function Remove-PCVM {
    $pathForVMVirtualMachines = "C:\VM-Sysprep\VM10\Virtual Machines\$removeChoosenVM"
    $pathForVHDX = "C:\VM-Sysprep\VM10\Virtual Hard Disks\$removeChoosenVM.vhdx"

    if(((Get-VM $removeChoosenVM).State) -eq "Running") {
        Write-Host "Shutting down $removeChoosenVM before deleting" -ForegroundColor Cyan
        Stop-VM -Name $removeChoosenVM -Force
        Remove-VM $removeChoosenVM -Force
        Remove-Item $pathForVHDX , $pathForVMVirtualMachines -Force
    } else {
        Remove-VM $removeChoosenVM -Force
        Remove-Item $pathForVHDX , $pathForVMVirtualMachines -Force
    }
}
function New-PCCheckDCStatusOn {
    if(((Get-VM $choosenDCToStart).State) -eq "Running") {
        Write-Host "$choosenDCToStart is already Turned on and Running" -ForegroundColor Cyan
    } else {
        Write-Host "Starting $choosenDCToStart" -ForegroundColor Cyan
        Get-VM $choosenDCToStart | Start-VM
        Write-Host "$choosenDCToStart is now up and Running!" -ForegroundColor Cyan
    }
}
function New-PCCheckVMStatusOn {
    if(((Get-VM $choosenVMtoStart).State) -eq "Running") {
        Write-Host "$choosenVMtoStart is already Turned on and Running" -ForegroundColor Cyan
    } else {
        Write-Host "Starting $choosenVMtoStart" -ForegroundColor Cyan
        Get-VM -Name $choosenVMtoStart | Start-VM
        Write-Host "$choosenVMtoStart is now up and Running!" -ForegroundColor Cyan
    }
}
function New-PCCheckDCStatusOff {
    if(((Get-VM $turnOffChoosenDC).State) -eq "Off") {
        Write-Host "$turnOffChoosenDC is already turned Off" -ForegroundColor Cyan
    } else {
        Write-Host "Shutting down $turnOffChoosenDC" -ForegroundColor Cyan
        Start-Sleep -Seconds 1
        Get-VM -Name $turnOffChoosenDC | Stop-VM
        Write-Host "$turnOffChoosenDC is now turned Off" -ForegroundColor Cyan
    }
}
function New-PCCheckVMStatusOff {
    if(((Get-VM $turnOffChoosenVM).State) -eq "Off") {
        Write-Host "$turnOffChoosenVM is already turned Off" -ForegroundColor Cyan
    } else {
        Write-Host "Shutting down $turnOffChoosenVM" -ForegroundColor Cyan
        Start-Sleep -Seconds 1
        Get-VM -Name $turnOffChoosenVM | Stop-VM
        Write-Host "$turnOffChoosenVM is now turned Off" -ForegroundColor Cyan
    }
}

function Install-PCADDS {
    Invoke-Command -VMName $choosenDCForADDSInstallation -Credential $choosenDCForADDSInstallation\Administrator -ScriptBlock {
        $passwordForAdminDNS = "RandomPassword123"
        
        if($env:COMPUTERNAME -eq $env:USERDOMAIN) {
        
            ##config Active-Directory
            Install-WindowsFeature AD-Domain-Services
            Install-WindowsFeature RSAT-AD-PowerShell
            Install-WindowsFeature RSAT-ADDS
        
            Import-Module ADDSDeployment
        
            ##Install and configure AD/DS
            Install-ADDSForest `
            -CreateDnsDelegation:$false `
            -DatabasePath "C:\Windows\NTDS" `
            -DomainMode "WinThreshold" `
            -DomainName "powershell.local" `
            -DomainNetbiosName "POWERSHELL" `
            -ForestMode "WinThreshold" `
            -InstallDns:$true `
            -LogPath "C:\Windows\NTDS" `
            -SysvolPath "C:\Windows\sysvol" `
            -SafeModeAdministratorPassword (ConvertTo-SecureString $passwordForAdminDNS -AsPlainText -Force) `
            -NoRebootOnCompletion:$false `
            -Force:$true
            
            Write-Verbose "Configuration Succeded!" -ForegroundColor Cyan
            Write-Verbose "Applying settings..." -ForegroundColor Cyan
            Write-Verbose "Successfully Configured AD Services" -ForegroundColor Cyan

            Start-Sleep -Seconds 5
            Restart-Computer -Force

        } else {  
            Write-Verbose "Powershell.local already exists!"
            }
        }
}
function New-PCDCNetworkConfiguration {
    Invoke-Command -VMName $configureDCNetworkSettings -Credential (Get-Credential) -ScriptBlock {
        ##This disables IPV6 
        Get-NetAdapterBinding -Name (Get-NetAdapter).Name -ComponentID 'ms_tcpip6' | Disable-NetAdapterBinding -Verbose
        Start-Sleep -Seconds 5

        New-NetIPAddress `
         -IPAddress $Using:IPAddressDCConf `
         -InterfaceAlias (Get-NetAdapter).InterfaceAlias `
         -DefaultGateway $Using:defaultGatewayDCConf `
         -PrefixLength $Using:preFixLengthDCConf `

        Start-Sleep -Seconds 2

        Set-DnsClientServerAddress -InterfaceIndex (Get-DnsClientServerAddress).InterfaceIndex -ServerAddresses $Using:DNSServerClientDCConf
        
        Write-Host "Configuration Completed!" -ForegroundColor Cyan
        Start-Sleep -Seconds 2
    }
}
#Domain Controllers Main Menu
function New-DCMENU
{
    param (
        [string]$TitleDC = 'Manage and Provision Domain Controller/s'
    )
    Clear-Host
    Write-Host "================ $TitleDC ================"
    
    Write-Host "1: Show all Virtual Machines"
    Write-Host "2: Start a DC"
    Write-Host "3: Turnoff a DC"
    Write-Host "4: Remove a DC"
    Write-Host "5: Provision a new DC"
}

## Virtual Machines Main Menu
function New-VMMENU
 { 
     param (
         [string]$TitleVM = 'Manage and Provision VM/s'
     )
     Clear-Host
     Write-Host "================ $TitleVM ================"
     
     Write-Host "1: Show all Virtual Machines"
     Write-Host "2: Start a VM"
     Write-Host "3: Turnoff a VM"
     Write-Host "4: Remove a VM"
     Write-Host "5: Provision a new VM"
     Write-Host "6. Add VM to Domain"
 }

 function NEW-DCConfigurationsMenu {
    param (
        [string]$TitleVM = 'Configure Windows Server/DC'
    )
    Clear-Host
    Write-Host "================ $TitleVM ================"
    
    Write-Host "1: Configure IP/DNS/Gateway"
    Write-Host "2: Install AD/DS Roles on DC"
 }

function New-AddVMToDomain {
    Invoke-Command -VMName $addComputerVMToDomain -Credential (Get-Credential) -ScriptBlock {
        ##This disables IPV6 
        Get-NetAdapterBinding -Name (Get-NetAdapter).Name -ComponentID 'ms_tcpip6' | Disable-NetAdapterBinding -Verbose
        Start-Sleep -Seconds 3
        
        Set-DnsClientServerAddress -InterfaceIndex (Get-DnsClientServerAddress).InterfaceIndex -ServerAddresses $Using:setDNSVMBeforeJoiningDomain
        Start-Sleep -Seconds 3

        Add-Computer -DomainName $Using:domainNameToJoin
        Restart-Computer -Force
    }
}

do {
    Write-Host "================ Provision Domain Controllers or VMs ==============="
    Write-Host "1: Domain Controllers Menu"
    Write-Host "2: Virtual Machines Menu"
    Write-Host "3: Configure Domain Services"
    Write-Host "Q: Press Q to exit."

    $MainMenu = Read-Host "Choose an entrance Or press Q to quit"
    switch ($MainMenu) {
        '1' {
            do { New-DCMENU
                $DCMainMenu = Read-Host "Choose an entrance or Press B for Back"
                switch ($DCMainMenu) {
                    '1' {
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                     } '2' {
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                        $choosenDCToStart = Read-Host "Which DC would you like to start?"
                        New-PCCheckDCStatusOn
                     } '3' {
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                        $turnOffChoosenDC = Read-Host "Which DC would you like to turn off?"
                        New-PCCheckDCStatusOff
                     } '4' {
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                        $removeChoosenDC = Read-Host "Which DC would you like to remove?"
                        Remove-PCDC -Verbose
                     } '5' {
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                        $choosenDCToProvision = Read-Host "Enter name of the DC you want to provision"
                        New-PCDC -Verbose
                     }
                }
                pause
            } until($DCMainMenu -eq 'B')
        } '2' {
            do { New-VMMENU
                 $VMMainMenu = Read-Host "Choose an entrance or Press B for Back"
                 switch($VMMainMenu) {
                    '1' {
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                     } '2' {
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                        $choosenVMtoStart = Read-Host "What VM would you like to start?"
                        New-PCCheckVMStatusOn
                     } '3' {
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                        $turnOffChoosenVM = Read-Host "What VM would you like to turn off?"
                        New-PCCheckVMStatusOff
                     } '4' {
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                        $removeChoosenVM = Read-Host "What VM would you like to remove?"
                        Remove-PCVM -Verbose
                     } '5' {
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                        $choosenVMToProvision = Read-Host "Enter name of the VM you want to provision"
                        New-PCVM -Verbose
                     } '6' {
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                        $addComputerVMToDomain = Read-Host "Enter VM you want to add to domain"
                        $domainNameToJoin = Read-Host "Enter Domainname ex. 'Powershell.local'"
                        Write-Host "NOTE, before joining a domain you are required to enter the DNS residing for that domain."
                        $setDNSVMBeforeJoiningDomain = Read-Host "Please enter the DNS, ex: 192.168.10.2"
                        New-AddVMToDomain
                     }
                 }      
                 pause
            } until ($VMMainMenu -eq 'B')
        } '3' {
            do { NEW-DCConfigurationsMenu
                $WindowsServerADConfigMenu = Read-Host "Choose an entrance or Press B for Back"
                switch($WindowsServerADConfigMenu) {
                   '1' {
                    Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                    $configureDCNetworkSettings = Read-Host "Enter DC to configure IP/DNS/Gateway"
                    Write-Host "Example of a configuration"
                    Write-Host "IPAddress Value: 192.168.10.2"
                    Write-Host "DefaultGateway Value: 192.168.10.1"
                    Write-Host "InterfaceAlias Value:" (Get-NetAdapter).InterfaceAlias
                    Write-Host "PrefixLength Value: 24"
                    Write-Host "DNS ServerClient Value: 192.168.10.2"
                    $IPAddressDCConf = Read-Host "Enter Value for IP-Address"
                    $defaultGatewayDCConf = Read-Host "Enter Value for Gateway/Router"
                    $preFixLengthDCConf = Read-Host "Enter Value For Prefix length"
                    $DNSServerClientDCConf = Read-Host "Enter a value for DNS-Address"
                    New-PCDCNetworkConfiguration
                    } '2' {
                    Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                    $choosenDCForADDSInstallation = Read-Host "Enter DC to install AD/DS Services"
                    Install-PCADDS -Verbose
                    }
                }      
            } until ($WindowsServerADConfigMenu -eq 'B')
        }
    }
} until($MainMenu -eq 'Q')
