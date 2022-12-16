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
  
    Write-Host "[$($VMName)] created" -ForegroundColor Cyan
    Start-VM $VMName
    } else {
        Write-Host "$VMName already exists!" -ForegroundColor Cyan
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
        Write-Host "Shutting down $VMName before deleting" -ForegroundColor Cyan
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
        Write-Error "[Virtual Machine $($VMName)] is already Turned on and Running" -ForegroundColor Cyan
    } elseif (((Get-VM $VMName).State) -eq "Off"){
        Write-Host "Starting $VMName" -ForegroundColor Cyan
        Get-VM $VMName | Start-VM
        Write-Host "$VMName is now up and Running!" -ForegroundColor Cyan
    } else {
        Write-Host "Virtual Machine $VMName does not exist" -ForegroundColor Cyan
    }
}
function New-PCCheckVMStatusOff {
    if(((Get-VM $VMName).State) -eq "Off") {
        Write-Host "$VMName is already turned Off" -ForegroundColor Cyan
    } elseif (((Get-VM $VMName).State) -eq "Running") {
        Write-Host "Shutting down $VMName" -ForegroundColor Cyan
        Start-Sleep -Seconds 1
        Get-VM -Name $VMName | Stop-VM
        Write-Host "$VMName is now turned Off" -ForegroundColor Cyan
    } else {
        Write-Host "Virtual Machine $VMName does not exist" -ForegroundColor Cyan
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
    Invoke-Command -VMName $VMName -Credential (Get-Credential) -ScriptBlock {
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

        Rename-Computer -NewName $Using:VMName
        Start-Sleep -Seconds 2
        Restart-Computer -Force
    }
}
<#
function New-PCConfigureDHCP {
    Invoke-Command -VMName $vmName -Credential (Get-Credential) {
        Install-WindowsFeature -Name 'DHCP' -IncludeManagementTools
        Start-Sleep -Seconds 60
        Add-DhcpServerv4Scope -Name $Using:NameOfDCHPScope -StartRange $Using:startOfDCHPScope -EndRange $Using:endOfDHCPScope -SubnetMask $Using:subnetmaskDCHPScope -State Active
        Set-DhcpServerV4OptionValue -DnsServer $Using:setDNSDHCP -Router $Using:routerDHCP
        Set-DhcpServerv4Scope -ScopeId $Using:enterDHCPScopeId -LeaseDuration $Using:leaseDurationDHCP
        Restart-Service dhcpserver -Force
    }   
} #>
function New-AddDCToExistingDomain {
Invoke-Command -VMName $VMName -Credential $VMName\Administrator -ScriptBlock {

    ##config Active-Directory
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
    Install-WindowsFeature RSAT-AD-PowerShell
    Install-WindowsFeature RSAT-ADDS

    Start-Sleep -Seconds 10

    # Windows PowerShell script for AD DS Deployment
    # Password for domain join credentials will be prompted
    # no DSRM password prompt.
    $adminForVMPassword = "RandomPassword123"

    Import-Module ADDSDeployment
    Install-ADDSDomainController `
    -NoGlobalCatalog:$false `
    -CreateDnsDelegation:$false `
    -Credential (Get-Credential POWERSHELL\Administrator) `
    -CriticalReplicationOnly:$false `
    -SiteName "Default-First-Site-Name" `
    -DomainName "POWERSHELL.LOCAL" `
    -ReplicationSourceDC "DC01.POWERSHELL.LOCAL"`
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
    Write-Host "Example of a configuration" -ForegroundColor Cyan
    Write-Host "IPAddress Value: 192.168.10.2" -ForegroundColor Cyan
    Write-Host "DefaultGateway Value: 192.168.10.1" -ForegroundColor Cyan
    Write-Host "InterfaceAlias Value:" (Get-NetAdapter).InterfaceAlias -ForegroundColor Cyan
    Write-Host "PrefixLength Value: 24" -ForegroundColor Cyan
    Write-Host "DNS ServerClient Value: 192.168.10.2" -ForegroundColor Cyan
}

function New-ExampleOfDHCPConf {
    Write-Host "Example of a DHCP-Configuration"
    Write-Host "-Name 'DHCP' -IncludeManagementTools"
    Write-Host "Add-DhcpServerv4Scope -Name DHCP Scope -StartRange 192.168.10.5"
    Write-Host "-EndRange 192.168.10.100 -SubnetMask 255.255.255.0"
    Write-Host "Set-DhcpServerV4OptionValue -DnsServer 192.168.10.2 -Router 192.168.10.1"
    Write-Host "Set-DhcpServerv4Scope -ScopeId 192.168.10.2 -LeaseDuration 1.00:00:00"
    Write-Host "Restart-Service dhcpserver"
}
function New-AddVMToDomain {
    Invoke-Command -VMName $addComputerVMToDomain -Credential (Get-Credential) -ScriptBlock {
        ##This disables IPV6 
        Get-NetAdapterBinding -Name (Get-NetAdapter).Name -ComponentID 'ms_tcpip6' | Disable-NetAdapterBinding -Verbose
        Start-Sleep -Seconds 3
        
        Set-DnsClientServerAddress -InterfaceIndex (Get-DnsClientServerAddress).InterfaceIndex -ServerAddresses $Using:setDNSVMBeforeJoiningDomain
        Start-Sleep -Seconds 3

        Rename-Computer -NewName $Using:addComputerVMToDomain -Force
        Start-Sleep -Seconds 2

        Add-Computer -DomainName $Using:domainNameToJoin -Credential (Get-Credential)
        Write-Host "$Using:addComputerVMToDomain successfully joined "
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
 }
do {
    Write-Host "================ Main Menu ==============="
    Write-Host "1: Provision/Manage Virtual Machines"
    Write-Host "2: Configure Domain Services"
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
                        $domainNameToJoin = Read-Host "Enter Domainname ex. 'Powershell.local'"
                        Write-Host "NOTE, before joining a domain you are required to enter the DNS residing for that domain."
                        $setDNSVMBeforeJoiningDomain = Read-Host "Please enter the DNS, ex: 192.168.10.2"
                        New-AddVMToDomain
                        Write-Host "Press Enter to cancel Option"
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
                    <#$VMName = Read-Host "Enter DC to Configure DHCP-Scope"
                    if(Get-VM -Name $VMName) {
                    $NameOfDCHPScope = Read-Host "Name of DCHP-Scope"
                    $startOfDCHPScope = Read-Host "Start of DHCP-Scope"
                    $endOfDHCPScope = Read-Host "End of DCHP-Scope"
                    $subnetmaskDCHPScope = Read-Host "Enter Prefix-length"
                    $setDNSDHCP = Read-Host "Enter DNS"
                    $routerDHCP = Read-Host "Enter router IP"
                    $enterDHCPScopeId = Read-Host "Enter DHCP Scope ID"
                    $leaseDurationDHCP = Read-Host "Enter DHCP Lease-Duration"
                    New-PCConfigureDHCP
                    } else {
                    Write-Host "Virtual Machine [$VMName] does not exist" -ForegroundColor Cyan
                    } #>
                    } '4' {
                    Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                    $VMName = Read-Host "Enter DC to join Domain"
                    if(Get-VM -Name $VMName) {
                    New-AddDCToExistingDomain
                    } 
                    else { 
                    Write-Host "Virtual Machine [$VMName] does not exist" -ForegroundColor Cyan
                    }
                  }
                }
                pause  
            } until ($WindowsServerADConfigMenu -eq 'B')
        }
    }
} until($MainMenu -eq 'Q')
