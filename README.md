# NPU-EstonianIDCard

## Description
Provides a PowerShell module for mapping Estonian National ID Card, Digital ID, and eID certificates to Active Directory user `altSecurityIdentities`. Supports both **SK ID Solutions** (`esteid.ldap.sk.ee` / ESTEID2018) and **Thales & Zetes** (`ldap.eidpki.ee` / ESTEID2025) directories.

## Installation
Copy the `NPU-EstonianIDCard` module folder to your PowerShell modules directory (e.g. `C:\Program Files\WindowsPowerShell\Modules`), or import directly from the module manifest:

```powershell
Import-Module .\NPU-EstonianIDCard\NPU-EstonianIDCard.psd1 -Force
```

## Commands
* `Get-IDUserMapping`
* `Get-ADUserEstonianIDMapping`
* `Set-ADUserEstonianIDMapping`
* `Set-ADOUEstonianIDMapping`

---

## Get-IDUserMapping

### Description
Queries LDAP directories (`esteid.ldap.sk.ee` and `ldap.eidpki.ee`) for authentication certificates and returns the X.509 Strong Name Mapping string (`X509:<I>...<SR>...`). Queries are **live by default**. For bulk jobs and repeated runs, the `-UseCache` switch enables local caching (in-memory and disk with a 24-hour TTL) to protect against Zetes 60 req/hr rate limits. Supports pipeline input.

### Syntax
```powershell
Get-IDUserMapping [-EstonianID] <string> [-UseCache]
```

### Examples
```powershell
# Live lookup (default)
Get-IDUserMapping -EstonianID '38001085718'

# Bulk / cached lookup (stores/retrieves from local cache)
Get-IDUserMapping -EstonianID '38001085718' -UseCache

# Pipeline lookup
'38001085718', '48001085718' | Get-IDUserMapping
```

---

## Get-ADUserEstonianIDMapping

### Description
Retrieves existing Active Directory user `altSecurityIdentities`. Supports pipeline input from `Get-ADUser`.

### Syntax
```powershell
Get-ADUserEstonianIDMapping [-Identity] <string>
```

### Examples
```powershell
Get-ADUserEstonianIDMapping -Identity jjoeorg

# Via pipeline
Get-ADUser -Filter 'department -eq "IT"' | Get-ADUserEstonianIDMapping
```

---

## Set-ADUserEstonianIDMapping

### Description
Sets or adds Estonian ID certificate mappings to an Active Directory user's `altSecurityIdentities`. Supports native `-WhatIf`, `-Confirm`, `-UseCache`, and `-Force`. If the user's `altSecurityIdentities` already match the resolved certificate mapping(s), no write operation is performed unless `-Force` is specified.

### Syntax
```powershell
Set-ADUserEstonianIDMapping -Identity <string> -EstonianID <string> [-Replace] [-Force] [-UseCache] [-WhatIf] [-Confirm]
Set-ADUserEstonianIDMapping -Identity <string> -EstonianIDPropertyName <string> [-Replace] [-Force] [-UseCache] [-WhatIf] [-Confirm]
```

### Examples
```powershell
# Update by explicit ID code (skips writing if already identical)
Set-ADUserEstonianIDMapping -Identity jjoeorg -EstonianID '38001085718' -Replace

# Update by reading personal code from an AD user attribute (e.g. isikukood)
Set-ADUserEstonianIDMapping -Identity jjoeorg -EstonianIDPropertyName isikukood -Replace

# Force write even if altSecurityIdentities already match
Set-ADUserEstonianIDMapping -Identity jjoeorg -EstonianID '38001085718' -Replace -Force

# Update using cached certificates (if available)
Set-ADUserEstonianIDMapping -Identity jjoeorg -EstonianID '38001085718' -UseCache

# Test changes safely with WhatIf
Set-ADUserEstonianIDMapping -Identity jjoeorg -EstonianID '38001085718' -WhatIf
```

---

## Set-ADOUEstonianIDMapping

### Description
Batch updates certificate mappings for enabled users in an Active Directory Organizational Unit (OU). Accounts whose `altSecurityIdentities` already match the resolved certificate mapping(s) are skipped (no write operation is performed) unless `-Force` is specified. Emits structured `PSCustomObject` stream to the pipeline for easy formatting or CSV export. Supports native `-WhatIf`, `-Confirm`, and `-UseCache`.

### Syntax
```powershell
Set-ADOUEstonianIDMapping [-DN] <string> [-EstonianIDPropertyName] <string> [-Replace] [-Force] [-UseCache] [-Sleep <int>] [-WhatIf] [-Confirm]
```

### Examples
```powershell
# Dry run with WhatIf
Set-ADOUEstonianIDMapping -DN "OU=Users,DC=example,DC=com" -EstonianIDPropertyName "isikukood" -Replace -WhatIf

# Run with caching enabled (recommended for large bulk updates to avoid Zetes 60 req/hr rate limits)
Set-ADOUEstonianIDMapping -DN "OU=Users,DC=example,DC=com" -EstonianIDPropertyName "isikukood" -Replace -UseCache

# Run and format output as a table
Set-ADOUEstonianIDMapping -DN "OU=Users,DC=example,DC=com" -EstonianIDPropertyName "isikukood" -Replace | Format-Table

# Run and export audit report to CSV
Set-ADOUEstonianIDMapping -DN "OU=Users,DC=example,DC=com" -EstonianIDPropertyName "isikukood" -Replace | Export-Csv -Path 'C:\Reports\IDMappingReport.csv' -NoTypeInformation
```
