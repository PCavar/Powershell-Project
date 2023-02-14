# HyperV-Project
Easy and simple way to Provision Domain Controllers and Virtual Machines

My first project in PowerShell.
This script has a Menu for Provisioning Domain Controllers/AD and Virtual Machines.
You can Provision, remove, start,turnoff DC/VM and even install some AD/DS features.(Features that aren't in the code but you want to add them, simlpe!) 
You can always add and configure it how you like but I find the baseline neat.

To break out of a option, usually it says "Press B for back,if not. You can break out by simple pressing Enter-Key"

NOTE: 3 variables are hardcoded, theese variables represent the path for the sysprep.
#$VMPath = "C:\VM-Sysprep"
#$ServerTemplatePath = "C:\VM-Sysprep\Win2019\Virtual Hard Disks\Win2019Template.vhdx"
#$ClientTemplatePath = "C:\VM-Sysprep\VM10\Virtual Hard Disks\VM10Template.vhdx"
    
First one represents path for the vm folders.
Second represents parent path where a new copy from the Windows Server template(.VHDX) is made.
Third represents parent path where a new copy from the Windows 10 template(.VHDX) is made.

Requirements for this to work without any hassle is a SysPrep WS2012-2022 for DC/AD And Windows 10 Pro(Clients) for VMs.(I'm using .VHDX)
Recommended to use Powershell Core 7.3.0 and higher.
NOTE: As you are managing Hyper-V with provisioning, elevated accessrights(admin) are required.
To be clear, you will also need ISO files for the OS Windows Server/Windows 10 Pro. If you choose 2012,2016,2019 or even 2022 for server it's up to you! (Some feature might be working better for newer versions). 


I have added Exchange installation: 
1 Prerequisits with roles/features 
2 Executables required, MSI
3 Prepare AD / Schema Extension and much more.

Required for this is ISO-Exchange (https://www.microsoft.com/en-us/download/details.aspx?id=104131)
UCMARuntimeSetup (https://www.microsoft.com/en-us/download/details.aspx?id=34992)
vcredist_x64 (https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist?view=msvc-170)
rewrite_amd64_en-US (https://www.iis.net/downloads/microsoft/url-rewrite)
ndp48-x86-x64-allos-enu (https://support.microsoft.com/en-us/topic/microsoft-net-framework-4-8-offline-installer-for-windows-9d23f658-3b97-68ab-d013-aa3c3e7495e0)

Requirements are basic knowledge of windows server and Active Directory.
Now what steps to do when. These steps need to be done in order. Have fun!

I am will continue push for commits and expand the functionality while keeping it 100% powershell based. Thanks!

Have fun!
