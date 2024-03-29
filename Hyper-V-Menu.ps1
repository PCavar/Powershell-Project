#This disables the Firewall
function New-disableNetFirewall {
    Invoke-Command -VMName $VMName -Credential (Get-Credential) -ScriptBlock {
        Write-Host "Shutting down firewall, please hold..." -ForegroundColor Yellow
        Start-Sleep -Seconds 3
        Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled False
        Write-Host "Complete!" -ForegroundColor Yellow
    }
}

#This function adds required stuff and installs the prerequisits for exchange
function New-PerformSomeDvdVHDXStuffOnExchange {

    $validatePrerequisitsForDvdIso = Get-VMDvdDrive -VMName $VMName | Select-Object -ExpandProperty dvdmediatype

    if($validatePrerequisitsForDvdIso -eq "ISO") {
        Write-Host "ISO-File aleady exists in $VMName" -ForegroundColor Yellow
    } else {
    #Add a dvdDrive for the Exchange-Iso and set the location to the Virtual Machine
    Add-VMDvdDrive -VMName $VMName
    Set-VMDvdDrive -VMName $VMName -Path "C:\VM-Sysprep\ExchangeServer\ExchangeServer2019-x64-CU12.ISO"
    Write-Host "Adding DVD-Drive Containing Exchange-ISO.." -ForegroundColor Yellow
    Start-Sleep -Seconds 1
    }

    $validatePrerequisitsVHDXExhange = Get-VMHardDiskDrive -VMName $VMName | Select-Object -ExpandProperty Path

    if($validatePrerequisitsVHDXExhange -eq "C:\VM-Sysprep\$VMName\$VMName.Exchange.vhdx") {
        Write-Host "$VMName already has a VHDX at C:\VM-Sysprep\$VMName\$VMName.Exchange.vhdx" -ForegroundColor Yellow
    } else {
        #Add a new VHDX to the Exchange Server and set the size to 100GB
        New-VHD -Path "C:\VM-Sysprep\$VMName\$VMName.Exchange.vhdx" -SizeBytes 100GB -Dynamic
        Add-VMHardDiskDrive -VMName $VMName -Path "C:\VM-Sysprep\$VMName\$VMName.Exchange.vhdx"
        Write-Host "Adding VHDX to $VMName...." -ForegroundColor Yellow
        Start-Sleep -Seconds 1
        Write-Host "Please enter credentials so we can Initialize the DISK"
    }

    Invoke-Command -VMName $VMName -Credential (Get-Credential) -ScriptBlock {
        #Find disk which is offline 
        $DiskToInitialize = Get-Disk | Where-Object {$_.OperationalStatus -like "offline"}
        Set-Disk -Number $DiskToInitialize.Number -IsOffline $false
        Set-Disk -Number $DiskToInitialize.Number -IsReadOnly $false
        #Initialize disk with a new Partition,Drive-Letter and format it
        Initialize-Disk -Number $DiskToInitialize.Number
        New-Partition -DiskNumber $DiskToInitialize.Number -DriveLetter F -UseMaximumSize
        Format-Volume -DriveLetter F -FileSystem NTFS -NewFileSystemLabel EXDATA -Force
        
        Write-Host "Disk setting up..." -ForegroundColor Yellow

        Write-Host "Disk setup Complete!" -ForegroundColor Yellow
        Write-Host "Name: EXDATA" -ForegroundColor Yellow
        Write-Host "Drive: F" -ForegroundColor Yellow
    }

   #This command copies all files contained in a folder, I have all required files in this folder
   $Items = Get-ChildItem -Path "C:\ExchangeFolder"
    foreach($item in $Items) {
        Copy-VMFile "$VMName" -SourcePath "C:\ExchangeFolder\$($item.name)" -DestinationPath "C:\ExchangeFolder\$($item.name)" -CreateFullPath -FileSource Host -Force
    }

   Write-Host "Copying files needed for Exchange..." -ForegroundColor Yellow
   Start-Sleep -Seconds 1
   Write-Host "Files successfully copied, Location: C:\ExchangeFolder in Virtual Machine $VMName" -ForegroundColor Yellow
}

function New-InstallRequiredPreRequisitsExchange {

    Invoke-Command -VMName $VMName -Credential (Get-Credential) -ScriptBlock {

        Write-Host "Installing Roles and features required for Exchange Server, please wait..." -ForegroundColor Yellow

        ###Install Required Windowsfeatures###
       Install-WindowsFeature -Name NET-Framework-45-Features, Server-Media-Foundation,
       RPC-over-HTTP-proxy, RSAT-Clustering, RSAT-Clustering-CmdInterface,
       RSAT-Clustering-Mgmt, RSAT-Clustering-PowerShell, WAS-Process-Model,
       Web-Asp-Net45, Web-Basic-Auth, Web-Client-Auth, Web-Digest-Auth,
       Web-Dir-Browsing, Web-Dyn-Compression, Web-Http-Errors, Web-Http-Logging,
       Web-Http-Redirect, Web-Http-Tracing, Web-ISAPI-Ext, Web-ISAPI-Filter,
       Web-Lgcy-Mgmt-Console, Web-Metabase, Web-Mgmt-Console, Web-Mgmt-Service,
       Web-Net-Ext45, Web-Request-Monitor, Web-Server, Web-Stat-Compression,
       Web-Static-Content, Web-Windows-Auth, Web-WMI, Windows-Identity-Foundation, RSAT-ADDS

       Start-Sleep -Seconds 2

       Write-Host "Done.." -ForegroundColor Yellow

       Restart-Computer -Force
    }
}

function New-TestingLoopsForExeMSI {
    Invoke-Command -VMName $VMName -Credential (Get-Credential) -ScriptBlock {
           #Here do EXECUTABLES AND MSI - THEN RESTART
            Set-Location -Path "C:\ExchangeFolder"
            .\UcmaRuntimeSetup.exe /q
            Write-Host "UcmaRuntimeSetup.exe Installed" -ForegroundColor Yellow
            .\vcredist_x64.exe /q
            Write-Host "vcredist_x64.exe Installed" -ForegroundColor Yellow
            .\rewrite_amd64_en-US.msi /q
            Write-Host "rewrite_amd64_en-US.msi Installed" -ForegroundColor Yellow
            .\ndp48-x86-x64-allos-enu.exe /q /norestart
            Write-Host "ndp48-x86-x64-allos-enu.exe Installed" -ForegroundColor Yellow

            Write-Host "Computer will restart..." -ForegroundColor Yellow
    }
}

function New-ExtendeADSchemaExchange {

    Invoke-Command -VMName $VMName -Credential (Get-Credential) -ScriptBlock {

    #Set the Drive & Extend AD Schema
    $DVDDriveExchange = Get-WmiObject win32_volume | Where-Object {$_.drivetype -eq '5'}
    Set-Location $DVDDriveExchange.name

    .\Setup.exe /IAcceptExchangeServerLicenseTerms_DiagnosticDataON /PrepareSchema
    .\Setup.exe /IAcceptExchangeServerLicenseTerms_DiagnosticDataON /PrepareAD /OrganizationName:"Mstile"

    Restart-Computer -Force

    }
}

function New-SecondInstallationExchangeServer {
    
    Invoke-Command -VMName $VMName -Credential (Get-Credential) -ScriptBlock {
     
     #Install Exchange

         #Set the Drive & Install Exchange
         $DVDDriveExchange = Get-WmiObject win32_volume | Where-Object {$_.drivetype -eq '5'}
         Set-Location $DVDDriveExchange.name
 
      .\Setup.exe /m:install /roles:m /IAcceptExchangeServerLicenseTerms_DiagnosticDataON /InstallWindowsComponents `
      /TargetDir:"F:\Program Files\Microsoft\Exchange Server\V15"  `
      /LogFolderPath:"F:\Program Files\Microsoft\Exchange Server\V15\LOGS" `
      /MdbName:"Mailbox Database 21121984" `
      /DbFilePath: "F:\Program Files\Microsoft\Exchange Server\V15\Mailboxes\Mailbox Database 21121984.edb"

      Restart-Computer -Force
    }
}

function New-LoginToExchangeServerPowerShell {

}

function New-CreateNewADOrganizationalUnitInAD {
    Invoke-Command -VMName $VMName -Credential (Get-Credential) -ScriptBlock {

    New-ADOrganizationalUnit `
     -Name $Using:NameOfOuInAD `
     -Path "DC=$Using:PathNETBIOSForTheOu,DC=$Using:PathForTheOUEnding" `
     -ProtectedFromAccidentalDeletion $False

    Write-Host "Organizational Group created named $Using:NameOfOuInAD" -ForegroundColor Yellow
    }
}

function New-CreateNewGroupInAD {
    Invoke-Command -VMName $VMName -Credential (Get-Credential) -ScriptBlock {

    New-ADGroup `
    -Name $Using:EnterADGroupName `
    -SamAccountName RODCAdmins `
    -GroupCategory Security `
    -GroupScope Global `
    -Path "OU=$Using:EnterPathForTheADgroupOU,DC=$Using:EnterPathForTheADgroupDCOne,DC=$Using:EnterPathForTheADgroupDCTwo"

    Write-Host "AD-Group created named $Using:EnterADGroupName" -ForegroundColor Yellow
    Write-Host "Path 'OU='$Using:EnterPathForTheADgroupOU 'DC='$Using:EnterPathForTheADgroupDCOne 'DC='$Using:EnterPathForTheADgroupDCTwo" -ForegroundColor Yellow
    }
}

function New-CreateOwnADUsersInAD {
    Invoke-Command -VMName $VMName -Credential (Get-Credential) -ScriptBlock {

        $fullName = $Using:firstNameUser + " " + $Using:surNameUser
        $SAM = $Using:firstNameUser + " "." " + $Using:surNameUser
        $userprincipalname = $Using:firstNameUser+"."+""+$Using:surNameUser + $Using:UPNadUser
        $passWordForADUsers = "Vinter2020"

        New-ADUser `
        -Name $fullName `
        -SamAccountName $SAM `
        -UserPrincipalName $userprincipalname `
        -GivenName $Using:firstNameUser `
        -Surname $Using:surNameUser `
        -DisplayName $fullName `
        -AccountPassword (ConvertTo-SecureString $passWordForADUsers -AsPlainText -Force) `
        -Enabled $true 

        Write-Host "User created" -ForegroundColor Yellow
        Write-Host "$userprincipalname"
    }
}


function New-CreateADUsersFromCSVExample {

    #Import csv-file to AD and store it in a variable $using:
    $csvFileADUsers = "C:\FolderCSVFileUsers\usersExchange.csv"
    Copy-VMFile "$VMName" -SourcePath "$csvFileADUsers" -DestinationPath "$csvFileADUsers" -CreateFullPath -FileSource Host -Force
    Write-Host "Importing CSV-File to $VMName" -ForegroundColor Yellow

    Invoke-Command -VMName $VMName -Credential (Get-Credential) -ScriptBlock {


        $ADUsersImport = Import-Csv -Path "C:\FolderCSVFileUsers\usersExchange.csv"
        $password = "Vinter2020"

        Write-Host "Creating and adding Users to Organizational Unit $Using:EnterPathForTheADUserOU and Security-Group $Using:EnterGroupWithinOUToAddUsers" -ForegroundColor Yellow
 
    foreach ($users in $ADUsersImport) {

        $userName = $users.givenname
        $lastName = $users.surname
        $SAM = $users.SAMaccountname
        $userprincipalname = $users.SAMaccountname + "@" + $Using:EnterPathForTheADUserDCOne + "." + $Using:EnterPathForTheADUserDCTwo
        $fullName = $userName + " " + $lastName

    #takes the output from the foreachloop and creates all the users
    New-ADUser `
        -Name $fullName `
        -SamAccountName $SAM `
        -UserPrincipalName $userprincipalname `
        -GivenName $userName `
        -Surname $lastName `
        -DisplayName $fullName `
        -AccountPassword (ConvertTo-SecureString $password -AsPlainText -Force) `
        -Enabled $true `
        -Path "OU=$Using:EnterPathForTheADUserOU,DC=$Using:EnterPathForTheADUserDCOne,DC=$Using:EnterPathForTheADUserDCTwo"
        
        #Adds users to the chosen group
        Add-ADGroupMember -Identity "CN=$Using:EnterGroupWithinOUToAddUsers,OU=$Using:EnterPathForTheADUserOU,DC=$Using:EnterPathForTheADUserDCOne,DC=$Using:EnterPathForTheADUserDCTwo" -Members $SAM
        Write-Host "$userprincipalname"

        }
    }
}

##NOTE, if somethings bugging and you dont know why, remove the this variable
##for trubleshooting! Thanks :) 


$VMPath = "C:\VM-Sysprep"
$ServerTemplatePath = "C:\VM-Sysprep\Win2019\Virtual Hard Disks\Win2019Template.vhdx"
$ClientTemplatePath = "C:\VM-Sysprep\VM10\Virtual Hard Disks\VM10Template.vhdx"
$CoreTemplatePath = "C:\VM-Sysprep\Win2019Core\Virtual Hard Disks\Win2019Core.vhdx"

function New-PCVM {

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$VMName,

    [Parameter(Mandatory)]
    [ValidateSet("Server","Client","Core")]$MachineType
)
    if((-not(Get-VM $VMName -ErrorAction SilentlyContinue).Name) -eq $VMName) {

        if ($MachineType -like "Server") {
            $TemplatePath = $ServerTemplatePath
        } elseif ($MachineType -like "Client") {
            $TemplatePath = $ClientTemplatePath
        } else {
            $TemplatePath = $CoreTemplatePath
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
    } elseif ($MachineType -like "Client") {
        New-VM `
        -Name $VMName `
        -Path $VMPath `
        -MemoryStartupBytes 1GB `
        -VHDPath $VHDPath `
        -BootDevice VHD `
        -Generation 2 `
        -Switch LAN
    } else {
        New-VM `
        -Name $VMName `
        -Path $VMPath `
        -MemoryStartupBytes 2GB `
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
            Write-Verbose "Domain already exists!"
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
            Write-Verbose "$env:USERDOMAIN already exist!"
            }
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
    -Credential (Get-Credential) `
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
function New-AddVMToDomain {
    Invoke-Command -VMName $addComputerVMToDomain -Credential (Get-Credential) -ScriptBlock {
        Rename-Computer -NewName $Using:addComputerVMToDomain -Force
        Set-DnsClientServerAddress -InterfaceIndex Get-NetAdapter.InterfaceIndex -ServerAddresses $Using:EnterDNSToAddVMtoDomain -Verbose
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

    Install-WindowsFeature -Name 'DHCP' –IncludeManagementTools

    Restart-service dhcpserver

    Start-Sleep -Seconds 10

    Restart-Computer -Force
    }
}

function New-DHCPConfigurationInstallment {
    Write-Host "Enter credentials for Domainname\Administrator" -ForegroundColor Yellow
    Invoke-Command -VMName $VMName -Credential (Get-Credential) -ScriptBlock {

    Add-DhcpServerv4Scope `
    -name "$Using:ScopeNameDHCP" `
    -StartRange $Using:configureDHCPForWindowsServerStartRange `
    -EndRange $Using:configureDHCPForWindowsServerEndRange `
    -SubnetMask $Using:subnetmaskConf

    Set-DhcpServerv4OptionValue `
    -ScopeId $Using:ScopeIdDHCP `
    -Router $Using:RouterDHCPVm `
    -DnsServer $Using:DNSServerDHCP `
    -DnsDomain "$Using:DomainNameDHCP"

    Set-DhcpServerv4Scope `
    -ScopeId $Using:ScopeIdDHCP `
    -LeaseDuration 1.00:00:00

    Write-Host "DHCP Configured Successfully" -ForegroundColor Yellow
    Get-DhcpServerv4Scope -ScopeId $Using:ScopeIdDHCP
    }
}
function New-PCDCFunctionExportVM {
    Export-VM `
    -Name $chooseVmOrDCToExportDisk `
    -Path $pathForExportedVMOrDC 

    Write-Host "VM Exported successfully!" -ForegroundColor Yellow
    Write-Host "Location $pathForExportedVMOrDC\$chooseVmOrDCToExportDisk" -ForegroundColor Yellow
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
     Write-Host "3: Provision a new Server Core"
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
    Write-Host "4: Export a VM to choosen folder"
    Write-Host "5: Shutdown Firewall (Not recommended)"
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
     Write-Host "5: Install DCHP on Server"
     Write-Host "6: Configure DHCP"
 }

 function New-DCVMSessionEnterer {
    param (
        [string]$MenuTitleForEnteringSession = 'Enter a Remote PowerShell Session to a VM'
    )
    Clear-Host
    Write-Host "================ $MenuTitleForEnteringSession ================"
    Write-Host "1: Choose a VM to enter a Remote PSSession"
 }

 function New-ExchangeInstallationMenu {
    param (
        [string]$ExchangeMenuLOL = 'Installation for Exchange Server'
    )
    Clear-Host
    Write-Host "================ $ExchangeMenuLOL ================"
    Write-Host "1: Join choosen domain"
    Write-Host "2: Disable firewall"
    Write-Host "3: Add Required Drives,ISO- and EXE/MSI files for Exchange"
    Write-Host "4: Add Required Roles/Features for Exchange"
    Write-Host "5: Run All Executables and MSI for Exchange Server"
    Write-Host "6: Extend ADSchema Exchange Server"
    Write-Host "7: Run second configuration for Installation Exchange Server"
}

function New-ManageOUGroupsUsersInAD {
    param (
        [string]$MenuForManagingOUsAndUsers = 'Manage your workforce here'
    )
    Clear-Host
    Write-Host "================ $MenuForManagingOUsAndUsers ================"
    Write-Host "1: Create OUs in AD"
    Write-Host "2: Create Groups in AD"
    Write-Host "3: Create own users in AD"
    Write-Host "4: Use attached CSV-File to create random users"
    Write-Host "5: Coming Soon"
}

do {
    Write-Host "================ Main Menu ==============="
    Write-Host "1: Provision/Manage Virtual Machines"
    Write-Host "2: Configure Domain Services"
    Write-Host "3: Enter Remote Powershell Session"
    Write-Host "4: Install Exchange On Server"
    Write-Host "5: Create and manage OUs, ADGroups & Users"
    Write-Host "Q: Press Q to exit."

    $MainMenu = Read-Host "Choose an entrance Or press Q to quit"
    switch ($MainMenu) {
        '1' {
            do { New-DCMENU
                $DCMainMenu = Read-Host "Choose an entrance or Press B for Back"
                switch ($DCMainMenu) {
                    '1' {
                        New-Testing
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
                                    New-PCVM -VMName $VMName -MachineType Client
                                }
                                } '3' {
                                    Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                                    $VMName = Read-Host "Enter name of the Server-Core you want to provision"
                                    if(Get-VM -Name $VMName) {
                                        Write-Host "Virtual Machine with name $VMName already exists!"
                                    } else {
                                        New-PCVM -VMName $VMName -MachineType Core
                                    }
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
                                $VMName = Read-Host "Enter target Server to Install DHCP Services"
                                if(Get-VM -Name $VMName) {
                                New-DHCPServerConfigurationWindows
                                } else {
                                Write-Host "Virtual Machine $VMName does not exist" -ForegroundColor Yellow
                                }
                                } '6' {
                                Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                                Write-Host "Press enter to cancel" -ForegroundColor Yellow
                                $VMName = Read-Host "Enter target Server to configure DHCP"
                                if(Get-VM -Name $VMName) {
                                $ScopeNameDHCP = Read-Host "Enter name for the Scope"
                                $configureDHCPForWindowsServerStartRange = Read-Host "Starting Range"
                                $configureDHCPForWindowsServerEndRange = Read-Host "End Range"
                                $subnetmaskConf = Read-Host "Enter Subnet (ex 255.255.255.0)"
                                $ScopeIdDHCP = Read-Host "Enter ScopeID"
                                $RouterDHCPVm = Read-Host "Enter Default Gateway"
                                $DNSServerDHCP = Read-Host "Enter IP for DNS-Server"
                                $DomainNameDHCP = Read-Host "Enter Domain-Name for server"
                                New-DHCPConfigurationInstallment
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
                    $EnterDNSToAddVMtoDomain = Read-Host "Please enter DNS"
                    Write-Host "NOTE, before joining a domain you are required to Configure the DNS residing for that domain." -ForegroundColor Yellow
                    New-AddVMToDomain
                    } 
                    else {
                    Write-Host "Virtual Machine [$addComputerVMToDomain] does not exist" -ForegroundColor Yellow
                    }
                    } '4' {
                    Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                    Write-Host "Press enter to cancel" -ForegroundColor Yellow
                    $chooseVmOrDCToExportDisk = Read-Host "Enter Virtual Machine to export"
                    $pathForExportedVMOrDC = Read-Host "Where do you want to place the exported files?"
                    if(Get-VM -Name $chooseVmOrDCToExportDisk) {
                        New-PCDCFunctionExportVM
                        } 
                        else {
                        Write-Host "Virtual Machine [$chooseVmOrDCToExportDisk] does not exist" -ForegroundColor Yellow
                        Write-Host "Try Again!" -BackgroundColor Yellow
                        }
                    } '5' {
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                        Write-Host "Press enter to cancel" -ForegroundColor Yellow
                        $VMName = Read-Host "Enter VM you wish to disable Firewall on"
                        if(Get-VM -Name $VMName) {
                            New-disableNetFirewall
                        } else {
                            Write-Host "Virtual Machine $VMName does not exist" -ForegroundColor Yellow
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
        } '4' {
            do {
                New-ExchangeInstallationMenu
                $ExchangeMenuLOL = Read-Host "Choose an entrance or Press B for Back"
                switch($ExchangeMenuLOL){
                '1' {
                    Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                    $addComputerVMToDomain = Read-Host "Enter Server to join Domain"
                if(Get-VM -Name $addComputerVMToDomain) {
                    Write-Host "This will first disable the Firewall and join the chosen Domain" -ForegroundColor Yellow
                    $domainNameToJoin = Read-Host "Enter Domainname ex. 'mstile.se'"
                    $EnterDNSToAddVMtoDomain = Read-Host "Please enter DNS"
                    Write-Host "NOTE, before joining a domain you are required to Configure the DNS residing for that domain." -ForegroundColor Yellow
                    New-AddVMToDomain
                    } else { 
                    Write-Host "Virtual Machine $addComputerVMToDomain does not exist" -ForegroundColor Yellow
                        }
                    } '2' {
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                        $VMName = Read-Host "Enter Server to Disable Firewall"
                        if(Get-VM -Name $VMName) {
                            Write-Host "This will Disable the firewall" -ForegroundColor Yellow
                            Start-Sleep -Seconds 5
                            New-disableNetFirewall
                        } else { 
                            Write-Host "Virtual Machine $VMName does not exist" -ForegroundColor Yellow
                            }
                    } '3' {
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                        Write-Host "This will do the following:" -ForegroundColor Yellow
                        Write-Host "Add a dvdDrive for the Exchange-Iso and set the location to the Virtual Machine" -ForegroundColor Yellow
                        Write-Host "Add a new VHDX to the Exchange Server and set the size to 100GB" -ForegroundColor Yellow
                        Write-Host "Initialize the Disk (F: Drive and named EXDATA)" -ForegroundColor Yellow
                        Write-Host "Copy all files needed for a Exchange Installation from a choosen folder" -ForegroundColor Yellow
                        $VMName = Read-Host "Enter Server to Perform theese actions"
                        if(Get-VM -Name $VMName) {
                            Write-Host "Working on it, please wait..." -ForegroundColor Yellow
                            New-PerformSomeDvdVHDXStuffOnExchange
                        } else {
                            Write-Host "Virtual Machine $VMName does not exist" -ForegroundColor Yellow                        
                        }
                    } '4' {
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                        Write-Host "This Option will install all required Roles/Feature for Exchange Server" -ForegroundColor Yellow
                        $VMName = Read-Host "Enter Server to Perform these actions"
                        if(Get-VM -Name $VMName) {
                            New-InstallRequiredPreRequisitsExchange
                        } else {
                            Write-Host "Virtual Machine $VMName does not exist" -ForegroundColor Yellow                        
                        }
                    } '5' {
                        Get-VM | Select-Object Name,start,CPUUsage,Version | Format-Table
                        Write-Host "Run all Executables and MSI in order for the Exchange Server"
                        $VMName = Read-Host "Enter a server to perform these actions"
                        if(Get-VM -Name $VMName) {
                            New-TestingLoopsForExeMSI
                        } else {
                            Write-Host "Virtual Machine $VMName does not exist" -ForegroundColor Yellow
                        }
                    } '6' {
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                        Write-Host "This will Extend the ADSchema and install Exchange"
                        $VMName = Read-Host "Enter a server to perfom these actions"
                        if(Get-VM -Name $VMName) {
                            New-ExtendeADSchemaExchange
                        } else {
                            Write-Host "Virtual Machine $VMName does not exist" -ForegroundColor Yellow
                        }
                    } '7' {
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                        Write-Host "This will make the last Installations processes for Exchange Server"
                        $VMName = Read-Host "Enter a server to perfom these actions"
                        if(Get-VM -Name $VMName) {
                            New-SecondInstallationExchangeServer
                        } else {
                            Write-Host "Virtual Machine $VMName does not exist" -ForegroundColor Yellow
                        }
                    } 
                }
                Pause
            } until ($ExchangeMenuLOL -eq 'B')
        } '5' {
            do {
                New-ManageOUGroupsUsersInAD
                $enterOuChoice = Read-Host "Choose an entrance or Press B for Back"
                switch($enterOuChoice) {
                    '1' {
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                        Write-Host "Press Enter to cancel" -ForegroundColor Yellow
                        $VMName = Read-Host "Enter Server to add OU"
                        $NameOfOuInAD = Read-Host "Enter name of Organizational Unit"
                        $PathNETBIOSForTheOu = Read-Host "Enter NETBIOS name for the Domain"
                        $PathForTheOUEnding = Read-Host "Enter the TLD (Top Level Domain) (Examples SE or COM)"
                        if(Get-VM -Name $VMName) {
                            New-CreateNewADOrganizationalUnitInAD
                        } else {
                            Write-Host "Virtual Machine $VMName does not exist" -ForegroundColor Yellow
                        }
                    } '2' {
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                        Write-Host "Press Enter to cancel" -ForegroundColor Yellow
                        $VMName = Read-Host "Enter Server to add AD-Group"
                        $EnterADGroupName = Read-Host "Enter AD-Group name"
                        Write-Host "Entering a path-example for the group looks like this" -ForegroundColor Yellow
                        Write-Host "Structure is as followed 'OU=Choose OU',DC=NETBIOS ,DC=TLD" -ForegroundColor Yellow
                        $EnterPathForTheADgroupOU = Read-Host "Enter OU"
                        $EnterPathForTheADgroupDCOne = Read-Host "Enter NETBIOS"
                        $EnterPathForTheADgroupDCTwo = Read-Host "Enter TLD"
                        if(Get-VM -Name $VMName) {
                            New-CreateNewGroupInAD
                        } else {
                            Write-Host "Virtual Machine $VMName does not exist" -ForegroundColor Yellow
                        }
                    } '3' {
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                        Write-Host "Press Enter to cancel" -ForegroundColor Yellow
                        $VMName = Read-Host "Enter Server to add AD-User"
                        $firstNameUser = Read-Host "Enter Firstname"
                        $surNameUser = Read-Host "Enter Surname"
                        $UPNadUser = Read-Host "Enter UPN-Suffix (@example.com)"
                        if(Get-VM -Name $VMName) {
                        New-CreateOwnADUsersInAD
                        } else {
                            Write-Host "Virtual Machine $VMName does not exist" -ForegroundColor Yellow
                        }
                    } '4' {
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                        Write-Host "Press Enter to cancel" -ForegroundColor Yellow
                        $VMName = Read-Host "Enter Server to add AD-Users"
                        $EnterPathForTheADUserOU = Read-Host "Enter Organizational Unit"
                        $EnterPathForTheADUserDCOne = Read-Host "Enter NETBIOS"
                        $EnterPathForTheADUserDCTwo = Read-Host "Enter TLD"
                        $EnterGroupWithinOUToAddUsers = Read-Host "Enter Security Group (CN) within your OU to add Users"
                        if(Get-VM -Name $VMName) {
                        New-CreateADUsersFromCSVExample
                        } else {
                            Write-Host "Virtual Machine $VMName does not exist" -ForegroundColor Yellow
                        }
                    }
                }
                pause
            } until ($enterOuChoice -eq 'B')
        }
    }
} until($MainMenu -eq 'Q')