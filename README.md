# HyperV-Project
Easy and simple way to Provision Domain Controllers and Virtual Machines

My first project in PowerShell.
This script has a Menu for Provisioning Domain Controllers/AD and Virtual Machines.
You can Provision, remove, start,turnoff DC/VM and even install some AD/DS features.(Features that aren't in the code but you want to add them, simlpe!) 
You can always add and configure it how you like but I find the baseline neat.

NOTE: 3 variables are hardcoded, theese variables represent the path for the sysprep.
    $pathForTemplate = "C:\VM-Sysprep\Win2019\Virtual Hard Disks\Win2019Template.vhdx"
    $pathForDCVirtualMachines = "C:\VM-Sysprep\Win2019\Virtual Machines"
    $pathForVHDX = "C:\VM-Sysprep\Win2019\Virtual Hard Disks\$choosenDCToProvision.vhdx"
    
    First one represents where the template(.VHDX) is located for the Cmdlet New-VHD (-ParentPath),(-Differencing).
    Second one represents where the mapp for the virtual machine will reside.
    Lastly the third one represents where the copy(.vhdx) from the template will reside.

Requirements for this to work without any hassle is a SysPrep WS2012-2022 for DC/AD And WindowsPro(Clients) for VMs.(I'm using .VHDX)
Recommended to use Powershell Core 7.3.0 and higher.
NOTE: As you are managing Hyper-V with provisioning, elevated accessrights(admin) are required.

I am will continue push for commits and expand the functionality while keeping it 100% powershell based. Thanks!

Have fun!
