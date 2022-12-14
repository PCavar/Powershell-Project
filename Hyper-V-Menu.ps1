function New-PCDC {
    $pathForTemplate = "C:\VM-Sysprep\Win2019\Virtual Hard Disks\Win2019Template.vhdx"
    $pathForDCVirtualMachines = "C:\VM-Sysprep\Win2019\Virtual Machines"
    $pathForVHDX = "C:\VM-Sysprep\Win2019\Virtual Hard Disks\$choosenDCToProvision.vhdx"

    New-VHD -ParentPath "$pathForTemplate" -Path ($pathForVHDX) -Differencing -Verbose
    
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
}
function Remove-PCDC {
    $pathForDCVirtualMachines = "C:\VM-Sysprep\VM10\Virtual Machines\$removeChoosenDC"
    $pathForVHDX = "C:\VM-Sysprep\VM10\Virtual Hard Disks\$removeChoosenDC.vhdx"

    Remove-VM $removeChoosenDC
    Remove-Item $pathForVHDX , $pathForDCVirtualMachines
}

function Remove-PCVM {
    $pathForVMVirtualMachines = "C:\VM-Sysprep\Win2019\Virtual Machines\$removeChooseVM"
    $pathForVHDX = "C:\VM-Sysprep\Win2019\Virtual Hard Disks\$removeChoosenVM.vhdx"

    Remove-VM $removeChoosenVM
    Remove-Item $pathForVHDX , $pathForVMVirtualMachines
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
        
            ##installera och konfa AD/DS
            Install-ADDSForest `
            -CreateDnsDelegation:$false `
            -DatabasePath "C:\Windows\NTDS" `
            -DomainMode "WinThreshold" `
            -DomainName "petcav.online" `
            -DomainNetbiosName "PETCAV" `
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

            Start-Sleep -Seconds 1
            Rename-Computer -NewName $Using:choosenDCForADDSInstallation
            Start-Sleep -Seconds 2
            Restart-Computer -Force

        } else {  
            Write-Verbose "petcav.online already exists!"
            }
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
    Write-Host "6: Install AD/DS Roles on DC"
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
 }

do {
    Write-Host "================ Provision Domain Controllers or VMs ==============="
    Write-Host "1: Domain Controllers Menu"
    Write-Host "2: Virtual Machines Menu"
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
                        $choosenDCToStart = Read-Host "What VM would you like to start?"
                        $choosenDCToStart | Start-VM -Verbose
                     } '3' {
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                        $turnOffChoosenDC = Read-Host "What VM would you like to turn off?"
                        $turnOffChoosenDC | Stop-VM -Verbose
                     } '4' {
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                        $removeChoosenDC = Read-Host "What VM would you like to remove?"
                        Remove-PCDC -Verbose
                     } '5' {
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                        $choosenDCToProvision = Read-Host "Enter name of the VM you want to provision"
                        New-PCDC -Verbose
                     } '6' {
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                        $choosenDCForADDSInstallation = Read-Host "Enter VM to install AD/DS Services"
                        Install-PCADDS -Verbose
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
                        $choosenVMtoStart | Start-VM -Verbose
                     } '3' {
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                        $turnOffChoosenVM = Read-Host "What VM would you like to turn off?"
                        $turnOffChoosenVM | Stop-VM -Verbose
                     } '4' {
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                        $removeChoosenVM = Read-Host "What VM would you like to remove?"
                        Remove-PCVM -Verbose
                     } '5' {
                        Get-VM | Select-Object Name,State,CPUUsage,Version | Format-Table
                        $choosenVMToProvision = Read-Host "Enter name of the VM you want to provision"
                        New-PCVM -Verbose
                     }
                 }      
                 pause
            } until ($VMMainMenu -eq 'B')
        }
    }
} until($MainMenu -eq 'Q')
