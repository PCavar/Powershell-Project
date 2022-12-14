##NOTE, if somethings bugging and you dont know why, remove the this variable
##for trubleshooting! Thanks :)
$ErrorActionPreference = 'SilentlyContinue'

$VMPath = "C:\VM-Sysprep"
$ServerTemplatePath = "C:\VM-Sysprep\Win2019\Virtual Hard Disks\Win2019Template.vhdx"
$ClientTemplatePath = "C:\VM-Sysprep\VM10\Virtual Hard Disks\VM10Template.vhdx"

function New-PCVM {

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$VMName,

    [Parameter(Mandatory)]
    [ValidateSet("Server","Client")]$MachineType
)
    if((-not(Get-VM $VMName -ErrorAction SilentlyContinue).Name) -eq $VMName) {

        if ($MachineType -like "Server") {
            $TemplatePath = $ServerTemplatePath
        } else {
            $TemplatePath = $ClientTemplatePath
        }

    $VHDPath = "$VMPath\$VMName\$VMName.vhdx"
    New-VHD -ParentPath "$TemplatePath" -Path $VHDPath -Differencing -Verbose

    if($MachineType -like "Server") {
        New-VM `
        -Name $VMName `
        -Path $VMPath `
        -MemoryStartupBytes 2GB `
        -VHDPath $VHDPath `
        -BootDevice VHD `
        -Generation 2 `
        -Switch LAN     
    } else {
        New-VM `
        -Name $VMName `
        -Path $VMPath `
        -MemoryStartupBytes 1GB `
        -VHDPath $VHDPath `
        -BootDevice VHD `
        -Generation 2 `
        -Switch LAN
    }
    

    Set-VMProcessor -VMName $VMName -Count 4 -Verbose

    Enable-VMIntegrationService -VMName $VMName -Name "Guest Service Interface" -Verbose
    Set-VM -VMName $VMName -AutomaticCheckpointsEnabled $false -CheckpointType Disabled -Verbose
  
    Write-Host "$VMName created" -ForegroundColor Yellow
    Start-VM $VMName
    } else {
        Write-Host "$VMName already exists!" -ForegroundColor Yellow
    }
}

function Remove-PCVM {
    [CmdletBinding()]
    param (
    [Parameter(Mandatory)]
    [string]$VMName
    )

    $VMPath = (get-vm -name $VMName).Path
    $VHDPath = (get-vm -name $VMName).HardDrives.Path

    if (!(get-vm $VMName -ErrorAction SilentlyContinue)) {
        Write-Host "Virtual Machine $VMName does not exist!" -ForegroundColor Yellow
    } elseif (((Get-VM $VMName).State) -eq "Running") {
        Write-Host "Shutting down $VMName before deleting" -ForegroundColor Yellow
        Get-VM -Name $VMName | Stop-VM -Force:$true
        Remove-VM $VMName -Force:$true
        Remove-Item $VHDPath,$VMPath -Force
    } else {
        Remove-VM $VMName -Confirm:$false -Force -Verbose
        Remove-Item $VHDPath,$VMPath -Confirm:$false -Force -Verbose
    }
}

function New-PCCheckVMStatusOn {
    if(((Get-VM $VMName).State) -eq "Running") {
        Write-Host "[Virtual Machine $($VMName)] is already Turned on and Running" -ForegroundColor Yellow
    } elseif (((Get-VM $VMName).State) -eq "Off"){
        Write-Host "Starting $VMName"
        Get-VM $VMName | Start-VM -Verbose
        Write-Host "$VMName is now up and Running!" -ForegroundColor Yellow
    } else {
        Write-Host "Virtual Machine $VMName does not exist" -ForegroundColor Yellow
    }
}
function New-PCCheckVMStatusOff {
    if(((Get-VM $VMName).State) -eq "Off") {
        Write-Host "$VMName is already turned Off" -ForegroundColor Yellow
    } elseif (((Get-VM $VMName).State) -eq "Running") {
        Write-Host "Shutting down $VMName" -ForegroundColor Yellow
        Start-Sleep -Seconds 1
        Get-VM -Name $VMName | Stop-VM -Force:$true
        Write-Host "$VMName is now turned Off"
    } else {
        Write-Host "Virtual Machine $VMName does not exist" -ForegroundColor Yellow
    }
}
function Install-PCADDS {
    Invoke-Command -VMName $VMName -Credential $VMName\Administrator -ScriptBlock {
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
            -DomainName $Using:DomainNameForDomainController `
            -DomainNetbiosName $Using:netBIOSNameDC `
            -ForestMode "WinThreshold" `
            -InstallDns:$true `
            -LogPath "C:\Windows\NTDS" `
            -SysvolPath "C:\Windows\sysvol" `
            -SafeModeAdministratorPassword (ConvertTo-SecureString $passwordForAdminDNS -AsPlainText -Force) `
            -NoRebootOnCompletion:$false `
            -Force:$true
            
            Write-Host "Successfully Configured AD Services" -ForegroundColor Yellow

            Start-Sleep -Seconds 5
            Restart-Computer -Force
            Write-Host "Computer restarted and configuration successfully applied!" -ForegroundColor Yellow

        } else {  
            Write-Verbose "Mstile.se already exists!"
            }
        }
}
function New-PCDCNetworkConfiguration {

    Start-Sleep -Seconds 10

    Invoke-Command -VMName $VMName -Credential (Get-Credential) -ScriptBlock {

        do {
        Write-Host "Applying settings...." -ForegroundColor Yellow
        ##This disables IPV6 
        Get-NetAdapterBinding -Name (Get-NetAdapter).Name -ComponentID 'ms_tcpip6' | Disable-NetAdapterBinding -Verbose
        
        New-NetIPAddress `
         -IPAddress $Using:IPAddressDCConf `
         -PrefixLength $Using:preFixLengthDCConf `
         -InterfaceIndex (Get-NetAdapter).InterfaceIndex `
         -DefaultGateway $Using:defaultGatewayDCConf `
         -AddressFamily IPv4

        Set-DnsClientServerAddress -InterfaceIndex (Get-NetAdapter).InterfaceIndex -ServerAddresses ("$Using:DNSServerClientDCConf")

        Write-Host "Hold on..." -ForegroundColor Yellow
    } until(Test-Path "C:\Windows\System32")
    
    Rename-Computer -NewName $Using:VMName -Force
    Start-Sleep -Seconds 2
    Write-Host "Computer restarted and setting successfully applied!" -ForegroundColor Yellow
    Restart-Computer -Force
    }
}

function New-PCDCOnlyInstallADDS {
    Invoke-Command -VMName $VMName -Credential $VMName\Administrator -ScriptBlock {
        
        if($env:COMPUTERNAME -eq $env:USERDOMAIN) {
        
            ##config Active-Directory
            Install-WindowsFeature AD-Domain-Services
            Install-WindowsFeature RSAT-AD-PowerShell
            Install-WindowsFeature RSAT-ADDS
        
            Import-Module ADDSDeployment
            Write-Host "Successfully Configured AD Services" -ForegroundColor Yellow

            Start-Sleep -Seconds 5
            Restart-Computer -Force
            Write-Host "Computer restarted and configuration successfully applied!" -ForegroundColor Yellow

        } else {  
            Write-Verbose "Mstile.se already exists!"
            }
        }
}

function New-PCConfigureDHCP {
    Invoke-Command -VMName $vmName -Credential (Get-Credential) {
        Install-WindowsFeature -Name 'DHCP' -IncludeManagementTools
        Start-Sleep -Seconds 60
        Add-DhcpServerv4Scope -Name $Using:NameOfDCHPScope -StartRange $Using:startOfDCHPScope -EndRange $Using:endOfDHCPScope -SubnetMask $Using:subnetmaskDCHPScope -State Active
        Set-DhcpServerV4OptionValue -DnsServer $Using:setDNSDHCP -Router $Using:routerDHCP
        Set-DhcpServerv4Scope -ScopeId $Using:enterDHCPScopeId -LeaseDuration $Using:leaseDurationDHCP
        Restart-Service dhcpserver -Force
    }   
}
function New-AddDCToExistingDomain {
Invoke-Command -VMName $VMName -Credential $VMName\Administrator -ScriptBlock {

    ##config Active-Directory
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
    Install-WindowsFeature RSAT-AD-PowerShell
    Install-WindowsFeature RSAT-ADDS

    Start-Sleep -Seconds 5

    # Windows PowerShell script for AD DS Deployment
    # Password for domain join credentials will be prompted
    # no DSRM password prompt.
    $adminForVMPassword = "RandomPassword123"

    Import-Module ADDSDeployment
    Install-ADDSDomainController `
    -AllowDomainControllerReinstall:$true `
    -NoGlobalCatalog:$false `
    -CreateDnsDelegation:$false `
    -Credential (Get-Credential MSTILE\Administrator) `
    -CriticalReplicationOnly:$false `
    -SiteName "Default-First-Site-Name" `
    -DomainName $Using:DomainNameForDomainController `
    -ReplicationSourceDC $Using:enterReplicationSourceDC `
    -DatabasePath "C:\Windows\NTDS" `
    -InstallDns:$true `
    -LogPath "C:\Windows\NTDS" `
    -NoRebootOnCompletion:$false `
    -SysvolPath "C:\Windows\SYSVOL" `
    -SafeModeAdministratorPassword (ConvertTo-SecureString $adminForVMPassword -AsPlainText -Force) `
    -Force:$true
}
}

function New-ExampleOfIpDnsRouterConf {
    Write-Host "Example of a configuration"
    Write-Host "IPAddress Value: 192.168.10.2"
    Write-Host "DefaultGateway Value: 192.168.10.1"
    Write-Host "PrefixLength/Subnet Value: 24"
    Write-Host "DNS ServerClient Value: 192.168.10.2"
}
function New-AddVMToDomain {
    Invoke-Command -VMName $addComputerVMToDomain -Credential $addComputerVMToDomain\Administrator -ScriptBlock {
        Rename-Computer -NewName $Using:addComputerVMToDomain -Force
        Start-Sleep -Seconds 2

        Write-Host "Please enter credentials for DomainName\Administrator" -ForegroundColor Yellow
        Add-Computer -DomainName $Using:domainNameToJoin -Credential (Get-Credential)
        Write-Host "$Using:addComputerVMToDomain successfully joined " -ForegroundColor Yellow
        Restart-Computer -Force
    }
}

function New-MoveFSMORolesAndDecomissionServer {
    Write-Host "Enter credentials for Domainname\Administrator" -ForegroundColor Yellow
    Invoke-Command -VMName $VMName -Credential (Get-Credential) -ScriptBlock {

    ##move the FSMO-Roles
    Move-ADDirectoryServerOperationMasterRole `
    -OperationMasterRole SchemaMaster,DomainNamingMaster,PDCEmulator,RIDMaster,InfrastructureMaster -Identity $Using:MoveFSMORolesTODC

    Write-Host "Enter Credentials for Windows Server example DC01\Administrator" -ForegroundColor Yellow
    #uninstall ADDSDomaincontroller
    Uninstall-ADDSDomainController `
    -Credential (Get-Credential) `
    -DemoteOperationMasterRole:$true `
    -IgnoreLastDnsServerForZone:$true `
    -RemoveDnsDelegation:$false `
    -LastDomainControllerInDomain:$false `
    -Force:$true

    #uninstall WindowsFeature
    Uninstall-WindowsFeature AD-Domain-Services -IncludeManagementTools
    Restart-Computer -Force -Wait
    Write-Host "Moved FSMO roles and successfully demoted Server" -ForegroundColor Yellow
    }
}

function New-VMPSSessionRemote {
    $savePSSessionVM = New-PSSession -VMName $chooseVMtoEnterPS -Credential(Get-Credential)
    Enter-PSSession $savePSSessionVM 
}

function New-DHCPServerConfigurationWindows {
    Write-Host "Enter credentials for Domainname\Administrator" -ForegroundColor Yellow
    Invoke-Command -VMName $VMName -Credential (Get-Credential) -ScriptBlock {

    Install-WindowsFeature -Name 'DHCP' ???IncludeManagementTools

    Add-DhcpServerV4Scope `
    -Name "DHCP Scope" `
    -StartRange $Using:configureDHCPForWindowsServerStartRange `
    -EndRange $Using:configureDHCPForWindowsServerEndRange `
    -SubnetMask $Using:configureDHCPForWindowsServerSubnetMask 

    Set-DhcpServerV4OptionValue `
    -DnsServer $Using:configureDHCPForWindowsServerDnsServer `
    -Router $Using:configureDHCPForWindowsServer

    Set-DhcpServerv4Scope `
    -ScopeId 192.168.10.2 `
    -LeaseDuration 1.00:00:00

    Restart-service dhcpserver

    Start-Sleep -Seconds 10

    Restart-Computer -Force
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
    Write-Host "2: Start a VM"
    Write-Host "3: Turnoff a VM"
    Write-Host "4: Remove a VM"
    Write-Host "5: Provision a new VM"
}
function New-ProvisioningDCVM
 { 
     param (
         [string]$TitleVMDCProvisioning = 'Provision VM'
     )
     Clear-Host
     Write-Host "================ $TitleVMDCProvisioning ================"
     
     Write-Host "1: Provision a Windows Server"
     Write-Host "2: Provision a new Client VM"
 }
 function NEW-DCConfigurationsMenu {
    param (
        [string]$TitleDCConfig = 'Configure Windows Server/DC'
    )
    Clear-Host
    Write-Host "================ $TitleDCConfig ================"
    
    Write-Host "1: Configure IP/DNS/Gateway"
    Write-Host "2: Add Roles and Features for a server"
    Write-Host "3: Join a existing Domain"
 }
 function New-DCConfigurationsSubMenu
 { 
     param (
         [string]$TitleDCConfigurationsSubMenu = 'Add Roles and Features to Windows Server'
     )
     Clear-Host
     Write-Host "================ $TitleDCConfigurationsSubMenu ================"
     
     Write-Host "1: Install AD/DS Roles and make it a Domain Controller"
     Write-Host "2: Install AD/DS on Windows Server"
     Write-Host "3: Join existing Domain as a Domain Controller with Replication"
     Write-Host "4: Move FSMO-Roles and Decomission Windows Server"
     Write-Host "5: Install & Configure DCHP"
 }

 function New-DCVMSessionEnterer {
    param (
        [string]$MenuTitleForEnteringSession = 'Enter a Remote PowerShell Session to a VM'
    )
    Clear-Host
    Write-Host "================ $MenuTitleForEnteringSession ================"
    Write-Host "1: Choose a VM to enter a Remote PSSession"
 }

do {
    Write-Host "================ Main Menu ==============="
    Write-Host "1: Provision/Manage Virtual Machines"
    Write-Host "2: Configure Domain Services"
    Write-Host "3: Enter Remote Powershell Session"
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
                        Write-Host "Press enter to cancel" -ForegroundColor Yellow
                        $VMName = Read-Host "Which VM would you like to start?"
                        New-PCCheckVMStatusOn
                     } '3' {
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                        Write-Host "Press enter to cancel" -ForegroundColor Yellow
                        $VMName = Read-Host "Which VM would you like to turn off?"
                        New-PCCheckVMStatusOff
                     } '4' {             
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                        Write-Host "Press enter to cancel" -ForegroundColor Yellow
                        $VMName = Read-Host "Which Virtual Machine do you want to remove?"
                        Remove-PCVM -VMName $VMName  -Verbose
                     } '5' {
                        do { New-ProvisioningDCVM
                            Write-Host "Press enter to cancel" -ForegroundColor Yellow
                            $DCVMProvision = Read-Host "Choose an entrance or Press B for Back"
                            switch($DCVMProvision) {
                               '1' {
                                Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                                $VMName = Read-Host "Enter name of the Windows Server you want to provision"
                                if(Get-VM -Name $VMName) {
                                    Write-Host "Windows Server with name $VMName already exists!"
                                } else {
                                    New-PCVM -VMName $VMName -MachineType Server 
                                }
                                } '2' {
                                Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                                $VMName = Read-Host "Enter name of the VM you want to provision"
                                if(Get-VM -Name $VMName) {
                                    Write-Host "Virtual Machine with name $VMName already exists!"
                                } else {
                                    New-PCVM -VMName $VMName -MachineType Client                                }
                                }
                            }
                            pause
                        } until($DCVMProvision -eq 'B')
                     }
                }
                pause
            } until($DCMainMenu -eq 'B')
            } '2' {
            do { NEW-DCConfigurationsMenu
                $WindowsServerADConfigMenu = Read-Host "Choose an entrance or Press B for Back"
                switch($WindowsServerADConfigMenu) {
                   '1' {
                    Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                    New-ExampleOfIpDnsRouterConf
                    $VMName = Read-Host "Enter VM to configure IP/DNS/Gateway"
                    if(Get-VM -Name $VMName) {
                        $IPAddressDCConf = Read-Host "Enter Value for IP-Address"
                        $defaultGatewayDCConf = Read-Host "Enter Value for Gateway/Router"
                        $preFixLengthDCConf = Read-Host "Enter Value For Prefix length"
                        $DNSServerClientDCConf = Read-Host "Enter a value for DNS-Address"
                        New-PCDCNetworkConfiguration
                        } else { 
                        Write-Host "Virtual Machine $VMName does not exist" -ForegroundColor Yellow
                        }
                    } '2' {
                        do { New-DCConfigurationsSubMenu
                            $TitleDCConfigurationsSubMenu = Read-Host "Choose an entrance or Press B for Back"
                            switch($TitleDCConfigurationsSubMenu) {
                               '1' {
                                Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                                Write-Host "Press enter to cancel" -ForegroundColor Yellow
                                Write-Host "This Option Installes AD/DS on a Windows Server" -ForegroundColor Yellow
                                $VMName = Read-Host "Enter DC to install AD/DS Services"
                                if(Get-VM -Name $VMName) {
                                    $DomainNameForDomainController = Read-Host "Enter DomainName ex mstile.se"
                                    $netBIOSNameDC = Read-Host "Enter NetBios Name ex MSTILE"
                                    Install-PCADDS -Verbose
                                    } else { 
                                    Write-Host "Virtual Machine $VMName does not exist" -ForegroundColor Yellow
                                    }
                                } '2' {
                                Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                                Write-Host "Press enter to cancel" -ForegroundColor Yellow
                                $VMName = Read-Host "Enter name of the Windows Server to install AD/DS"
                                if(Get-VM -Name $VMName) {
                                    New-PCDCOnlyInstallADDS
                                } else {
                                    Write-Host "Virtual Machine $VMName does not exist" -ForegroundColor Yellow
                                }
                                } '3' {
                                Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                                Write-Host "Press enter to cancel" -ForegroundColor Yellow
                                $VMName = Read-Host "Enter Windows Server to join Domain"
                                if(Get-VM -Name $VMName) {
                                $DomainNameForDomainController = Read-Host "Enter DomainName ex mstile.se"
                                $enterReplicationSourceDC = Read-Host "Enter DomainController ex DC01.mstile.se"
                                New-AddDCToExistingDomain
                                } else { 
                                Write-Host "Virtual Machine $VMName does not exist" -ForegroundColor Yellow
                                }
                                } '4' {
                                Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                                Write-Host "Press enter to cancel" -ForegroundColor Yellow
                                $VMName = Read-Host "Enter Windows Server DC you want to move FSMO-Roles from and decomission"
                                if(Get-VM -Name $VMName) {
                                $MoveFSMORolesTODC = "Enter target Server To move Roles to"
                                New-MoveFSMORolesAndDecomissionServer
                                } else {
                                Write-Host "Virtual Machine $VMName does not exist" -ForegroundColor Yellow
                                }
                                } '5' {
                                Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                                Write-Host "Press enter to cancel" -ForegroundColor Yellow
                                $VMName = Read-Host "Enter target Server to configure DHCP"
                                if(Get-VM -Name $VMName) {
                                $configureDHCPForWindowsServerStartRange = Read-Host "Starting Range"
                                $configureDHCPForWindowsServerEndRange = Read-Host "End Range"
                                $configureDHCPForWindowsServerSubnetMask = Read-Host "Subnet Mask"
                                $configureDHCPForWindowsServerDnsServer = Read-Host "DNS"
                                $configureDHCPForWindowsServer = Read-Host "Router"
                                New-DHCPServerConfigurationWindows
                                } else {
                                Write-Host "Virtual Machine $VMName does not exist" -ForegroundColor Yellow
                                }

                                }
                            }
                            pause
                        } until($TitleDCConfigurationsSubMenu -eq 'B')
                     }
                     '3' {
                    Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                    Write-Host "Press enter to cancel" -ForegroundColor Yellow
                    $addComputerVMToDomain = Read-Host "Enter VM to ad to domain"
                    if(Get-VM -Name $addComputerVMToDomain) {
                    $domainNameToJoin = Read-Host "Enter Domainname ex. 'mstile.se'"
                    Write-Host "NOTE, before joining a domain you are required to Configure the DNS residing for that domain." -ForegroundColor Yellow
                    New-AddVMToDomain
                    } 
                    else {
                    Write-Host "Virtual Machine [$addComputerVMToDomain] does not exist" -ForegroundColor Yellow
                    }
                    }
                }
                pause  
            } until ($WindowsServerADConfigMenu -eq 'B')
        } '3' {
            do {
                New-DCVMSessionEnterer
                $enterPSSessionVM = Read-Host "Choose an entrance or Press B for Back"
                switch($enterPSSessionVM){
                '1' {
                    Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                    Write-Host "Press enter to cancel" -ForegroundColor Yellow
                    $chooseVMtoEnterPS = Read-Host "Choose VM to remotely enter PSSession"
                    New-VMPSSessionRemote
                    Write-Host "Session successfully entered!" -ForegroundColor Yellow
                    Write-Host "Please exit script to continue your remote session" -ForegroundColor Yellow
                    }
                }
                pause
        } until ($enterPSSessionVM -eq 'B')
        }
    }
} until($MainMenu -eq 'Q')