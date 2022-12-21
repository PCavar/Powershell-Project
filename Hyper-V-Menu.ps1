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
    
	New-VM `
	-Name $VMName `
    -Path $VMPath `
	-MemoryStartupBytes 2GB `
    -VHDPath $VHDPath `
    -BootDevice VHD `
	-Generation 2 `
	-Switch LAN

    Set-VMProcessor -VMName $VMName -Count 4 -Verbose

    Enable-VMIntegrationService -VMName $VMName -Name "Guest Service Interface" -Verbose
    Set-VM -VMName $VMName -AutomaticCheckpointsEnabled $false -Verbose
  
    Write-Host "[$($VMName)] created"
    Start-VM $VMName
    } else {
        Write-Host "$VMName already exists!"
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
        Write-Error "[Virtual Machine $($VMName)] does not exist!"
    } elseif (((Get-VM $VMName).State) -eq "Running") {
        Write-Host "Shutting down $VMName before deleting"
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
        Write-Host "[Virtual Machine $($VMName)] is already Turned on and Running"
    } elseif (((Get-VM $VMName).State) -eq "Off"){
        Write-Host "Starting $VMName"
        Get-VM $VMName | Start-VM -Verbose
        Write-Host "$VMName is now up and Running!"
    } else {
        Write-Host "Virtual Machine $VMName does not exist"
    }
}
function New-PCCheckVMStatusOff {
    if(((Get-VM $VMName).State) -eq "Off") {
        Write-Host "$VMName is already turned Off"
    } elseif (((Get-VM $VMName).State) -eq "Running") {
        Write-Host "Shutting down $VMName"
        Start-Sleep -Seconds 1
        Get-VM -Name $VMName | Stop-VM -Force:$true
        Write-Host "$VMName is now turned Off"
    } else {
        Write-Host "Virtual Machine $VMName does not exist"
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
            -DomainName "mstile.se" `
            -DomainNetbiosName "MSTILE" `
            -ForestMode "WinThreshold" `
            -InstallDns:$true `
            -LogPath "C:\Windows\NTDS" `
            -SysvolPath "C:\Windows\sysvol" `
            -SafeModeAdministratorPassword (ConvertTo-SecureString $passwordForAdminDNS -AsPlainText -Force) `
            -NoRebootOnCompletion:$false `
            -Force:$true
            
            Write-Verbose "Configuration Succeded!"
            Write-Verbose "Applying settings..."
            Write-Verbose "Successfully Configured AD Services"

            Start-Sleep -Seconds 5
            Restart-Computer -Wait
            Write-Host "Computer restarted and configuration successfully applied!"

        } else {  
            Write-Verbose "Mstile.se already exists!"
            }
        }
}
function New-PCDCNetworkConfiguration {
    Invoke-Command -VMName $VMName -Credential (Get-Credential) -ScriptBlock {

        Set-NetIPInterface `
        -InterfaceAlias (Get-NetAdapter).InterfaceAlias `
        -AddressFamily IPv4 `
        -IPAddress $Using:IPAddressDCConf `
        -PrefixLength $Using:preFixLengthDCConf `
        -DefaultGateway $Using:defaultGatewayDCConf

       <# New-NetIPAddress `
         -IPAddress $Using:IPAddressDCConf `
         -InterfaceAlias (Get-NetAdapter).InterfaceAlias `
         -DefaultGateway $Using:defaultGatewayDCConf `
         -PrefixLength $Using:preFixLengthDCConf `
        #>

        Start-Sleep -Seconds 2

        Set-DnsClient -InterfaceAlias (Get-NetAdapter).InterfaceAlias -ServerAddresses ("$Using:DNSServerClientDCConf")
        ##This disables IPV6 
        Get-NetAdapterBinding -Name (Get-NetAdapter).Name -ComponentID 'ms_tcpip6' | Disable-NetAdapterBinding -Verbose

        Start-Sleep -Seconds 2
        Write-Host "Configuration Completed!"
        Start-Sleep -Seconds 2

        Rename-Computer -NewName $Using:VMName -Force
        Start-Sleep -Seconds 2
        Write-Host "Computer restarted and setting successfully applied!"
        Restart-Computer -Force
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
    -DomainName "mstile.se" `
    -ReplicationSourceDC "DC01.MSTILE.SE"`
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
    Write-Host "InterfaceAlias Value:" (Get-NetAdapter).InterfaceAlias
    Write-Host "PrefixLength/Subnet Value: 24"
    Write-Host "DNS ServerClient Value: 192.168.10.2"
}

function New-ExampleOfDHCPConf {
    Write-Host "Example of a DHCP-Configuration"
    Write-Host "-Name 'DHCP' -IncludeManagementTools"
    Write-Host "Add-DhcpServerv4Scope -Name DHCP Scope -StartRange 192.168.10.5"
    Write-Host "-EndRange 192.168.10.100 -SubnetMask 255.255.255.0"
    Write-Host "Set-DhcpServerV4OptionValue -DnsServer 192.168.10.2 -Router 192.168.10.1"
    Write-Host "Set-DhcpServerv4Scope -ScopeId 192.168.10.2 -LeaseDuration 1.00:00:00"
}
function New-AddVMToDomain {
    Invoke-Command -VMName $addComputerVMToDomain -Credential $addComputerVMToDomain\Administrator -ScriptBlock {
        ##This disables IPV6 
        Get-NetAdapterBinding -Name (Get-NetAdapter).Name -ComponentID 'ms_tcpip6' | Disable-NetAdapterBinding -Verbose
        Start-Sleep -Seconds 3
        
        Set-DnsClientServerAddress -InterfaceIndex (Get-DnsClientServerAddress).InterfaceIndex -ServerAddresses $Using:setDNSVMBeforeJoiningDomain
        Start-Sleep -Seconds 3

        Rename-Computer -NewName $Using:addComputerVMToDomain -Force
        Start-Sleep -Seconds 2

        Write-Host "Please enter credentials for Domainname\Administrator"
        Add-Computer -DomainName $Using:domainNameToJoin -Credential (Get-Credential)
        Write-Host "$Using:addComputerVMToDomain successfully joined "
        Restart-Computer -Force
    }
}

function New-MoveFSMORolesAndDecomissionServer {
    Write-Host "Enter credentials for Domainname\Administrator"
    Invoke-Command -VMName $VMName -Credential (Get-Credential) -ScriptBlock {

    ##move the FSMO-Roles
    Move-ADDirectoryServerOperationMasterRole `
    -OperationMasterRole SchemaMaster,DomainNamingMaster,PDCEmulator,RIDMaster,InfrastructureMaster -Identity $Using:MoveFSMORolesTODC

    Write-Host "Enter Credentials for Windows Server example DC01\Administrator"
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
    Write-Host "Moved FSMO roles and successfully demoted Server"
    }
}

function New-VMPSSessionRemote {
    $savePSSessionVM = New-PSSession -VMName $chooseVMtoEnterPS -Credential(Get-Credential)
    Enter-PSSession $savePSSessionVM 
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
    Write-Host "6: Add VM to Domain"
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
    Write-Host "2: Install AD/DS Roles on Windows Server"
    Write-Host "3: Configure DHCP on Windows Server"
    Write-Host "4: Join a Server to existing Domain"
    Write-Host "5: Move FSMO-Roles and Decomission Windows Server"
 }

 function New-DCVMSessionEnterer {
    param (
        [string]$MenuTitleForEnteringSession = 'Enter a Remote PowerShell Session to a VM'
    )
    Clear-Host
    Write-Host "================ $MenuTitleForEnteringSession ================"
    Write-Host "1. Choose a VM to enter a Remote PSSession"
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
                        $VMName = Read-Host "Which VM would you like to start?"
                        New-PCCheckVMStatusOn
                     } '3' {
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                        $VMName = Read-Host "Which VM would you like to turn off?"
                        New-PCCheckVMStatusOff
                     } '4' {             
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                        $VMName = Read-Host "Which Virtual Machine do you want to remove?"
                        Remove-PCVM -VMName $VMName  -Verbose
                     } '5' {
                        do { New-ProvisioningDCVM
                            $DCVMProvision = Read-Host "Choose an entrance or Press B for Back"
                            switch($DCVMProvision) {
                               '1' {
                                Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                                $VMName = Read-Host "Enter name of the DC you want to provision"
                                New-PCVM -VMName $VMName -MachineType Server
                                } '2' {
                                Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                                $VMName = Read-Host "Enter name of the VM you want to provision"
                                New-PCVM -VMName $VMName -MachineType Client
                                }
                            }
                            pause
                        } until($DCVMProvision -eq 'B')
                     } '6' {
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                        $addComputerVMToDomain = Read-Host "Enter VM you want to add to domain"
                        if(Get-VM -Name $addComputerVMToDomain) {
                        $domainNameToJoin = Read-Host "Enter Domainname ex. 'Powershell.local'"
                        Write-Host "NOTE, before joining a domain you are required to enter the DNS residing for that domain."
                        $setDNSVMBeforeJoiningDomain = Read-Host "Please enter the DNS, ex: 192.168.10.2"
                        New-AddVMToDomain
                        Write-Host "Press Enter to cancel Option"
                        } 
                        else {
                            Write-Host "Virtual Machine [$addComputerVMToDomain] does not exist"
                        }
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
                    $VMName = Read-Host "Enter DC to configure IP/DNS/Gateway"
                    $IPAddressDCConf = Read-Host "Enter Value for IP-Address"
                    $defaultGatewayDCConf = Read-Host "Enter Value for Gateway/Router"
                    $preFixLengthDCConf = Read-Host "Enter Value For Prefix length"
                    $DNSServerClientDCConf = Read-Host "Enter a value for DNS-Address"
                    New-PCDCNetworkConfiguration
                    } '2' {
                    Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                    Write-Host "This Option Installes AD/DS on a Windows Server"
                    $VMName = Read-Host "Enter DC to install AD/DS Services"
                    Install-PCADDS -Verbose
                    } '3' {
                    Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                    New-ExampleOfDHCPConf
                    Write-Host "Comming soon"
                    $VMName = Read-Host "Enter DC to Configure DHCP-Scope"
                    if(Get-VM -Name $VMName) {
                    $NameOfDCHPScope = Read-Host "Name of DCHP-Scope"
                    $startOfDCHPScope = Read-Host "Start of DHCP-Scope"
                    $endOfDHCPScope = Read-Host "End of DCHP-Scope"
                    $subnetmaskDCHPScope = Read-Host "Enter SubnetMask"
                    $setDNSDHCP = Read-Host "Enter DNS"
                    $routerDHCP = Read-Host "Enter router IP"
                    $enterDHCPScopeId = Read-Host "Enter DHCP Scope ID"
                    $leaseDurationDHCP = Read-Host "Enter DHCP Lease-Duration"
                    New-PCConfigureDHCP
                    } else {
                    Write-Host "Virtual Machine [$VMName] does not exist"
                    }
                    } '4' {
                    Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                    $VMName = Read-Host "Enter DC to join Domain"
                    if(Get-VM -Name $VMName) {
                    New-AddDCToExistingDomain
                    } else { 
                    Write-Host "Virtual Machine [$VMName] does not exist"
                    }
                    } '5' {
                    Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                    $VMName = Read-Host "Enter Windows Server DC you want to move FSMO-Roles from and decomission"
                    $MoveFSMORolesTODC = "Enter target Server To move Roles to"
                    if(Get-VM -Name $VMName) {
                    New-MoveFSMORolesAndDecomissionServer
                    } else {
                    Write-Host "Virtual Machine [$VMName] does not exist"
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
                    $chooseVMtoEnterPS = Read-Host "Choose VM to remotely enter PSSession"
                    New-VMPSSessionRemote
                    Write-Host "Session successfully entered!"
                    Write-Host "Please exit script to continue your remote session"
                    }
                }
                pause
        } until ($enterPSSessionVM -eq 'B')
        }
    }
} until($MainMenu -eq 'Q')
