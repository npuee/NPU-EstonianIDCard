# NPU-EstonianIDCard

## Description
Provides an easy interface for Estonian National ID Card certificate mapping to active directiry user altSecurityIdentities.

NB: Input for commands have changed.


## Installation
 Copy NPU-EstonianIDCard  folder to windows powershell module location (C:\Program Files\WindowsPowerShell\Modules).  
If you don't want to install module you can import from running powershell console.
```powershell
    #Navigate to NPU-EstonianIDCard folder:
    PS C:\> cd C:\Temp\NPU-EstonianIDCard\
    #Import module from file:
    PS C:\Temp\NPU-EstonianIDCard> Import-Module .\NPU-EstonianIDCard.psm1 -Force
```
## NPU-EstonianIDCard Command  
    Get-ADUserEstonianIDMapping
    Set-ADUserEstonianIDMapping
    Set-ADOUEstonianIDMapping
    Get-EstonianIDMapping


## Get-ADUserEstonianIDMapping:
### Syntax
```powershell
Get-ADUserEstonianIDMapping
    [-Identity] <string>
```
### Description
    Get Active Directory User altSecurityIdentities.
### Example
```powershell
PS C:\temp> Get-ADUserEstonianIDMapping -Identity jjoeorg
X509:<I>C=EE,O=SK ID Solutions AS,OID.2.5.4.97=NTREE-10747013,CN=ESTEID2018<SR>48D9BEEA2D33795C2FD344ED29DE2D30
```
### Parameters
    -Identity
        Active Directory samAccountName.


## Set-ADUserEstonianIDMapping
### Syntax
```powershell
Set-ADUserEstonianIDMapping 
    [-Identity <string>] 
    [-EstonianID <string>]
    [-EstonianIDPropertyName <string>]
    [-Replace <Switch>]
```
### Description
    Set Active Directory User altSecurityIdentities.
### Example
```powershell
PS C:\temp> Set-ADUserEstonianIDMapping -Identity jjoeorg -EstonianIDPropertyName isikukood -Replace
or
PS C:\temp> Set-ADUserEstonianIDMapping -Identity jjoeorg -EstonianID 38001085718 -Replace

```
### Parameters
    -Identity
        Active Directory samAccountName.
    -EstonianID
        Estonian identification (ID) code. (Use EstonianID OR EstonianIDPropertyName)    
    -EstonianIDPropertyName
        Active Directory User object attribute where Estonian identification (ID) code is stored. (Use EstonianID OR EstonianIDPropertyName)
    -Replace
        Replace or Add altSecurityIdentities. Default is Add.


## Set-ADOUEstonianIDMapping
### Syntax
```powershell
Set-ADOUEstonianIDMapping
    [-DN] <string>
    [-EstonianIDPropertyName] <string>
    [[-Replace] <Switch>]
    [[-Force] <Switch>]
    [[-WhatIf] <Switch>]
```
### Description
    Set Active Directory Users altSecurityIdentities in specific OU.
### Example
```powershell
PS C:\temp> Set-ADOUEstonianIDMapping -DN "OU=Users,DC=example,DC=com" -EstonianIDProperty "isikukood" -Replace  -WhatIf

```
### Parameters
    -DN
        OU in Active Directory.
    -EstonianIDPropertyName
        Active Directory User object attribute where Estonian identification (ID) code is stored.
    -Replace
        Replace or Add altSecurityIdentities. Default is Add.
    -Force
        If multiple mappings exist, replaces all existing ones. Use with -Replace
    -WhatIf        
        Display output without altering user accounts.


## Get-EstonianIDMapping
### Syntax
```powershell
Get-EstonianIDMapping
    [-EstonianID] <string>
```
### Description
    Displays secure altSecurityIdentities mapping from esteid.ldap.sk.ee.
### Example
```powershell
PS C:\temp> Get-EstonianIDMapping -EstonianID 38001085718 
X509:<I>C=EE,O=SK ID Solutions AS,OID.2.5.4.97=NTREE-10747013,CN=ESTEID2018<SR>48D9BEEA1D33795C2FD054ED29DE2D30
```
### Parameters
    -EstonianID
        Active Directory samAccountName.




