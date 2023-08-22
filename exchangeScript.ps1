#Launch Powershell Exchange Management Shell
LaunchEMS

Start-Sleep -Seconds 15

#Fetch all the users in the Group and chose UPN
$users = Get-ADUser -Filter * -SearchBase "OU=MSTILE,DC=MSTILE,DC=SE"
$usersExpand = $users | Select-Object -ExpandProperty UserPrincipalName

#If you wanna create new mailbox
New-MailboxDatabase -Name "CoreMailboxDatabase" -EdbFilePath D:\ExchangeDatabases\DB1\DB1.edb

#Loop through every User and enable their mailbox and add the Database
foreach ($user in $usersExpand) {
    Enable-Mailbox -Identity $user -Database CoreMailboxDatabase
}

#create shared mailbox and set attributes
New-Mailbox -Shared -Name "alla@mstile.se" -DisplayName "Alla" -Alias Alla
#fetch shared mailbox
Get-Mailbox -RecipientTypeDetails SharedMailbox
#Set permissions to receive and send on behalf of chosen group

$users = Get-ADUser -Filter * -SearchBase "OU=TEST,DC=MSTILE,DC=SE"
$usersExpand = $users | Select-Object -ExpandProperty UserPrincipalName

$usersExpand = $newArray
$newArray[0,1,2]
