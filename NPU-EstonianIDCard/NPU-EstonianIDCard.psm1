#
# Module: NPU-EstonianIDCard
# By: Nikolai Pulman
#

# Script-scoped configuration (does not pollute global caller session)
$script:EstIDLdapURL = "esteid.ldap.sk.ee"
$script:EstIDLdapPort = 636
$script:EstIDLdapDN = "dc=ESTEID,c=EE"
$script:NationalIDDN = "*ou=Authentication,o=Identity card of Estonian citizen,dc=ESTEID,c=EE"
$script:DigitalIDDN = "*ou=Authentication,o=Digital identity card,dc=ESTEID,c=EE"

$script:ThalesLdapURL = "ldap.eidpki.ee"
$script:ThalesLdapPort = 636
$script:ThalesLdapDN = "dc=ldap,dc=eidpki,dc=ee"
$script:ThalesNationalIDDN = "*ou=Authentication,o=IdentityCardEstonianCitizen,dc=ESTEID,c=EE,dc=ldap,dc=eidpki,dc=ee"
$script:ThalesDigitalIDDN = "*ou=Authentication,o=DigitalIdentityCardOfE-Residents,dc=ESTEID,c=EE,dc=ldap,dc=eidpki,dc=ee"
$script:ThalesEUIDDN = "*ou=Authentication,o=IdentityCardOfEuropeanUnionCitizen,dc=ESTEID,c=EE,dc=ldap,dc=eidpki,dc=ee"
$script:ThalesResidencePermitDN = "*ou=Authentication,o=ResidencePermitCard*,dc=ESTEID,c=EE,dc=ldap,dc=eidpki,dc=ee"

#
# Caching Configuration (Protects against Zetes 60 req/hr rate limits)
#
$script:CacheFolder = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'NPU_EstID_Cache'
$script:CacheTTLHours = 24
$script:MemoryCache = @{}

function Get-CachedMapping {
    param([string]$ID)

    # 1. Check in-memory cache
    if ($script:MemoryCache.ContainsKey($ID)) {
        $entry = $script:MemoryCache[$ID]
        if ((([DateTime]::UtcNow) - $entry.Timestamp).TotalHours -lt $script:CacheTTLHours) {
            return $entry.Mappings
        }
    }

    # 2. Check disk cache
    $cacheFile = Join-Path -Path $script:CacheFolder -ChildPath "$ID.json"
    if (Test-Path -LiteralPath $cacheFile) {
        try {
            $data = Get-Content -LiteralPath $cacheFile -Raw | ConvertFrom-Json
            $timestamp = [DateTime]::Parse($data.Timestamp, [System.Globalization.CultureInfo]::InvariantCulture)
            if ((([DateTime]::UtcNow) - $timestamp).TotalHours -lt $script:CacheTTLHours) {
                $script:MemoryCache[$ID] = @{ Timestamp = $timestamp; Mappings = [string[]]$data.Mappings }
                return [string[]]$data.Mappings
            }
        } catch { }
    }
    return $null
}

function Set-CachedMapping {
    param(
        [string]$ID,
        [string[]]$Mappings
    )
    $now = [DateTime]::UtcNow
    # 1. Store in memory
    $script:MemoryCache[$ID] = @{ Timestamp = $now; Mappings = $Mappings }

    # 2. Store on disk
    try {
        if (-not (Test-Path -LiteralPath $script:CacheFolder)) {
            New-Item -ItemType Directory -Path $script:CacheFolder -Force | Out-Null
        }
        $cacheFile = Join-Path -Path $script:CacheFolder -ChildPath "$ID.json"
        $obj = @{
            Timestamp = $now.ToString("o")
            Mappings  = $Mappings
        }
        $json = $obj | ConvertTo-Json
        Set-Content -LiteralPath $cacheFile -Value $json -Encoding utf8
    } catch { }
}

#
# Internal Helpers
#

function Assert-ActiveDirectoryModule {
    if (-not (Get-Module -Name ActiveDirectory)) {
        try {
            Import-Module -Name ActiveDirectory -ErrorAction Stop
        }
        catch {
            throw "ActiveDirectory module is required for this operation but is not available in the current PowerShell environment."
        }
    }
}

function _Test-IdenticalMappings {
    param(
        [string[]]$MappingsA,
        [string[]]$MappingsB
    )

    $listA = @($MappingsA | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
    $listB = @($MappingsB | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })

    if ($listA.Count -ne $listB.Count) {
        return $false
    }

    foreach ($item in $listA) {
        if ($listB -notcontains $item) {
            return $false
        }
    }

    return $true
}

function _DecodeCertificate {
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$CertificateInByte
    )

    $cert = $null
    try {
        $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($CertificateInByte)

        # Reverse certificate serial (2-byte chunks from big-endian to little-endian representation)
        $serialChars = $cert.SerialNumber.ToCharArray()
        $reversedSerial = ""
        for ($i = 0; $i -lt $serialChars.Length; $i += 2) {
            $reversedSerial = $serialChars[$i] + $serialChars[$i + 1] + $reversedSerial
        }

        # Reverse certificate issuer DN components
        $issuerParts = $cert.Issuer.Split(",")
        $reversedIssuer = ""
        foreach ($part in $issuerParts) {
            $reversedIssuer = $part + "," + $reversedIssuer
        }
        $reversedIssuer = $reversedIssuer.Replace(', ', ',')
        $reversedIssuer = $reversedIssuer.Substring(0, $reversedIssuer.Length - 1)

        # Strong Name Mapping:
        return "X509:<I>" + $reversedIssuer.Trim() + "<SR>" + $reversedSerial
    }
    finally {
        if ($cert) { $cert.Dispose() }
    }
}

#
# Exported Cmdlets
#

function Get-IDUserMapping {
    <#
    .SYNOPSIS
    Queries Estonian eID LDAP directories and generates Active Directory altSecurityIdentities mappings.

    .DESCRIPTION
    Searches both SK ID Solutions (esteid.ldap.sk.ee) and Thales / Zetes (ldap.eidpki.ee) LDAPS services
    for authentication certificates belonging to the specified 11-digit Estonian personal code.
    Returns the decoded X.509 Strong Name Mapping string (X509:<I>...<SR>...).

    .PARAMETER EstonianID
    11-digit Estonian personal identification code (isikukood). Accepts pipeline input.

    .PARAMETER UseCache
    Enables local disk and in-memory caching to avoid rate limits during bulk queries. Disabled by default (live queries).

    .EXAMPLE
    Get-IDUserMapping -EstonianID '38001085718'

    .EXAMPLE
    # Use cached certificate if available
    Get-IDUserMapping -EstonianID '38001085718' -UseCache

    .EXAMPLE
    '38001085718', '48001085718' | Get-IDUserMapping
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        [ValidatePattern('^\d{11}$')]
        [string]$EstonianID,

        [Parameter()]
        [switch]$UseCache
    )

    process {
        if ($UseCache) {
            $cached = Get-CachedMapping -ID $EstonianID
            if ($cached) {
                Write-Verbose "Retrieved mapping for ID '$EstonianID' from cache."
                foreach ($m in $cached) {
                    Write-Output $m
                }
                return
            }
        }

        $MappingResults = [System.Collections.Generic.List[string]]::new()
        $IDCodeFilter = "(serialNumber=PNOEE-$EstonianID)"

        # 1. Search SK ID Solutions LDAP (esteid.ldap.sk.ee)
        $skUrl  = if ($global:EstIDLdapURL)  { $global:EstIDLdapURL }  else { $script:EstIDLdapURL }
        $skPort = if ($global:EstIDLdapPort) { $global:EstIDLdapPort } else { $script:EstIDLdapPort }
        $skDN   = if ($global:EstIDLdapDN)   { $global:EstIDLdapDN }   else { $script:EstIDLdapDN }

        $ldap = $null
        $ds   = $null
        try {
            $ldapdn = "LDAP://$skUrl`:$skPort/$skDN"
            $auth = [System.DirectoryServices.AuthenticationTypes]::Anonymous
            $ldap = New-Object System.DirectoryServices.DirectoryEntry($ldapdn, $null, $null, $auth)

            $ds = New-Object System.DirectoryServices.DirectorySearcher($ldap)
            $ds.Filter = $IDCodeFilter
            [void]$ds.PropertiesToLoad.Add("usercertificate;binary")

            $searchResults = $ds.FindAll()
            foreach ($result in $searchResults) {
                if ($result.Path -like $script:NationalIDDN -or $result.Path -like $script:DigitalIDDN) {
                    $rawVal = $result.Properties['usercertificate;binary'][0]
                    $byteCert = if ($rawVal -is [byte[]]) { $rawVal } else { [byte[]]($result.Properties.'usercertificate;binary' | Out-String -Stream) }
                    $mapping = _DecodeCertificate -CertificateInByte $byteCert
                    if ($mapping -and -not $MappingResults.Contains($mapping)) {
                        $MappingResults.Add($mapping)
                    }
                }
            }
        }
        catch {
            Write-Warning "Could not query SK LDAP ($skUrl): $($_.Exception.Message)"
        }
        finally {
            if ($ds)   { $ds.Dispose() }
            if ($ldap) { $ldap.Dispose() }
        }

        # 2. Search Thales / Zetes LDAP (ldap.eidpki.ee)
        $thalesUrl  = if ($global:ThalesLdapURL)  { $global:ThalesLdapURL }  else { $script:ThalesLdapURL }
        $thalesPort = if ($global:ThalesLdapPort) { $global:ThalesLdapPort } else { $script:ThalesLdapPort }
        $thalesDN   = if ($global:ThalesLdapDN)   { $global:ThalesLdapDN }   else { $script:ThalesLdapDN }

        $thalesLdap = $null
        $thalesDs   = $null
        try {
            $thalesLdapDn = "LDAP://$thalesUrl`:$thalesPort/$thalesDN"
            # Zetes LDAP requires FastBind to prevent 0x80005000 directory schema discovery errors
            $thalesAuth = [System.DirectoryServices.AuthenticationTypes]::FastBind
            $thalesLdap = New-Object System.DirectoryServices.DirectoryEntry($thalesLdapDn, $null, $null, $thalesAuth)

            $thalesDs = New-Object System.DirectoryServices.DirectorySearcher($thalesLdap)
            $thalesDs.Filter = $IDCodeFilter
            [void]$thalesDs.PropertiesToLoad.Add("usercertificate;binary")

            $thalesResults = $thalesDs.FindAll()
            foreach ($result in $thalesResults) {
                if ($result.Path -like $script:ThalesNationalIDDN -or
                    $result.Path -like $script:ThalesDigitalIDDN -or
                    $result.Path -like $script:ThalesEUIDDN -or
                    $result.Path -like $script:ThalesResidencePermitDN -or
                    $result.Path -like "*ou=Authentication*") {

                    $rawVal = $result.Properties['usercertificate;binary'][0]
                    $byteCert = if ($rawVal -is [byte[]]) { $rawVal } else { [byte[]]($result.Properties.'usercertificate;binary' | Out-String -Stream) }
                    $mapping = _DecodeCertificate -CertificateInByte $byteCert
                    if ($mapping -and -not $MappingResults.Contains($mapping)) {
                        $MappingResults.Add($mapping)
                    }
                }
            }
        }
        catch {
            Write-Warning "Could not query Thales/Zetes LDAP ($thalesUrl): $($_.Exception.Message)"
        }
        finally {
            if ($thalesDs)   { $thalesDs.Dispose() }
            if ($thalesLdap) { $thalesLdap.Dispose() }
        }

        # Cache discovered mappings if caching was requested
        if ($UseCache -and $MappingResults.Count -gt 0) {
            Set-CachedMapping -ID $EstonianID -Mappings ([string[]]$MappingResults)
        }

        # Emit mapped results to pipeline
        foreach ($map in $MappingResults) {
            Write-Output $map
        }
    }
}

function Get-ADUserEstonianIDMapping {
    <#
    .SYNOPSIS
    Retrieves altSecurityIdentities attribute values from an Active Directory user account.

    .DESCRIPTION
    Queries Active Directory for the specified user identity and returns the altSecurityIdentities attribute.

    .PARAMETER Identity
    The Active Directory user account (samAccountName, DistinguishedName, SID, or UserPrincipalName). Accepts pipeline input.

    .EXAMPLE
    Get-ADUserEstonianIDMapping -Identity jjoeorg

    .EXAMPLE
    Get-ADUser -Filter 'department -eq "Finance"' | Get-ADUserEstonianIDMapping
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, Position = 0)]
        [string]$Identity
    )

    process {
        Assert-ActiveDirectoryModule
        $userProperties = Get-ADUser -Identity $Identity -Properties altSecurityIdentities
        return $userProperties.altSecurityIdentities
    }
}

function Set-ADUserEstonianIDMapping {
    <#
    .SYNOPSIS
    Sets or adds Estonian ID card certificate mappings to an Active Directory user's altSecurityIdentities.

    .DESCRIPTION
    Resolves an Estonian personal code to certificate mappings via Get-IDUserMapping and updates
    the target Active Directory user account. Supports native -WhatIf and -Confirm.

    .PARAMETER Identity
    Active Directory user account identity. Accepts pipeline input.

    .PARAMETER EstonianID
    11-digit Estonian personal identification code.

    .PARAMETER EstonianIDPropertyName
    Active Directory user attribute name where the Estonian personal code is stored (e.g. 'isikukood').

    .PARAMETER Replace
    If specified, replaces existing altSecurityIdentities with resolved mappings. By default, new mappings are added.

    .PARAMETER Force
    Forces writing to Active Directory even if existing altSecurityIdentities already match.

    .PARAMETER UseCache
    Enables local caching to avoid LDAP rate limits during bulk queries.

    .EXAMPLE
    Set-ADUserEstonianIDMapping -Identity jjoeorg -EstonianID '38001085718' -Replace

    .EXAMPLE
    Set-ADUserEstonianIDMapping -Identity jjoeorg -EstonianIDPropertyName isikukood -WhatIf
    #>
    [CmdletBinding(DefaultParameterSetName = 'EstonianID', SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'EstonianID', Mandatory = $true, Position = 1)]
        [ValidatePattern('^\d{11}$')]
        [string]$EstonianID,

        [Parameter(ParameterSetName = 'EstonianIDPropertyName', Mandatory = $true, Position = 1)]
        [string]$EstonianIDPropertyName,

        [Parameter()]
        [switch]$Replace,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$UseCache,

        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, Position = 0)]
        [string]$Identity
    )

    process {
        Assert-ActiveDirectoryModule

        $resolvedID = $EstonianID
        $existingMappings = @()

        if ($PSCmdlet.ParameterSetName -eq 'EstonianIDPropertyName') {
            try {
                $user = Get-ADUser -Identity $Identity -Properties $EstonianIDPropertyName, altSecurityIdentities
                $resolvedID = $user.$EstonianIDPropertyName
                $existingMappings = @($user.altSecurityIdentities)
            }
            catch {
                throw "Failed to retrieve attribute '$EstonianIDPropertyName' for user '$Identity': $($_.Exception.Message)"
            }

            if (-not $resolvedID) {
                Write-Warning "User '$Identity' has no value in attribute '$EstonianIDPropertyName'. Skipping."
                return
            }

            if ($resolvedID -notmatch '^\d{11}$') {
                Write-Warning "Attribute '$EstonianIDPropertyName' for user '$Identity' ('$resolvedID') is not an 11-digit numeric ID. Skipping."
                return
            }
        }
        else {
            try {
                $user = Get-ADUser -Identity $Identity -Properties altSecurityIdentities
                $existingMappings = @($user.altSecurityIdentities)
            }
            catch {
                throw "Failed to retrieve user '$Identity' from Active Directory: $($_.Exception.Message)"
            }
        }

        $mappings = @(Get-IDUserMapping -EstonianID $resolvedID -UseCache:$UseCache)
        if (-not $mappings -or $mappings.Count -eq 0) {
            Write-Warning "No certificates found in LDAP for ID '$resolvedID'. User '$Identity' was not modified."
            return
        }

        # Avoid unnecessary writes if values are already the same
        if ($Replace) {
            $isIdentical = _Test-IdenticalMappings -MappingsA $existingMappings -MappingsB $mappings
            if ($isIdentical -and -not $Force) {
                Write-Verbose "altSecurityIdentities for user '$Identity' already match the resolved certificate mapping(s). No write required."
                return
            }

            $actionDesc = "Replace altSecurityIdentities with $($mappings.Count) mapping(s)"
            if ($PSCmdlet.ShouldProcess("ADUser: $Identity", $actionDesc)) {
                Set-ADUser -Identity $Identity -Replace @{ altSecurityIdentities = [string[]]$mappings }
                Write-Verbose "Successfully replaced altSecurityIdentities for user '$Identity'."
            }
        }
        else {
            # Add mode: only add mappings not already present
            $toAdd = @($mappings | Where-Object { $existingMappings -notcontains $_.Trim() })
            if ($toAdd.Count -eq 0) {
                Write-Verbose "All resolved certificate mapping(s) already exist in altSecurityIdentities for user '$Identity'. No write required."
                return
            }

            $actionDesc = "Add $($toAdd.Count) mapping(s) to altSecurityIdentities"
            if ($PSCmdlet.ShouldProcess("ADUser: $Identity", $actionDesc)) {
                Set-ADUser -Identity $Identity -Add @{ altSecurityIdentities = [string[]]$toAdd }
                Write-Verbose "Successfully added $($toAdd.Count) mapping(s) to altSecurityIdentities for user '$Identity'."
            }
        }
    }
}

function Set-ADOUEstonianIDMapping {
    <#
    .SYNOPSIS
    Batch updates Estonian ID certificate mappings for active Active Directory users in an Organizational Unit (OU).

    .DESCRIPTION
    Scans enabled users in an OU, reads the personal identification code from the specified attribute,
    resolves certificates from LDAP, and updates user altSecurityIdentities. Emits structured PSCustomObject
    results to the pipeline. Supports native -WhatIf and -Confirm.

    .PARAMETER DN
    DistinguishedName of the Active Directory Organizational Unit (e.g. "OU=Users,DC=example,DC=com").

    .PARAMETER EstonianIDPropertyName
    Active Directory user attribute name where the personal code is stored (e.g. "isikukood").

    .PARAMETER Replace
    Replace existing altSecurityIdentities rather than appending.

    .PARAMETER Force
    Update even if a mapping already exists.

    .PARAMETER Sleep
    Optional delay in seconds between processing each user account.

    .EXAMPLE
    Set-ADOUEstonianIDMapping -DN "OU=Employees,DC=corp,DC=local" -EstonianIDPropertyName "isikukood" -WhatIf

    .EXAMPLE
    Set-ADOUEstonianIDMapping -DN "OU=Employees,DC=corp,DC=local" -EstonianIDPropertyName "isikukood" -Replace | Format-Table
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$DN,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$EstonianIDPropertyName,

        [Parameter()]
        [switch]$Replace,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$UseCache,

        [Parameter()]
        [int]$Sleep = 0
    )

    process {
        Assert-ActiveDirectoryModule

        $users = Get-ADUser -Filter 'enabled -eq $true' -SearchBase $DN -Properties $EstonianIDPropertyName, altSecurityIdentities
        foreach ($user in $users) {
            $samAccountName    = $user.SamAccountName
            $nationalID        = $user.$EstonianIDPropertyName
            $existingMappings  = @($user.altSecurityIdentities)
            $newMappings       = @()
            $mappingExists     = $false
            $canBeReplaced     = $false
            $needsToBeReplaced = $false
            $replaced          = $false

            if ($nationalID -and $nationalID -match '^\d{11}$') {
                try {
                    $newMappings = @(Get-IDUserMapping -EstonianID $nationalID -UseCache:$UseCache)
                }
                catch {
                    $newMappings = @()
                }

                if ($newMappings.Count -gt 0) {
                    $canBeReplaced = $true

                    if ($Replace) {
                        # In Replace mode, mappingExists is true ONLY if existing mappings match new mappings identically
                        $mappingExists = _Test-IdenticalMappings -MappingsA $existingMappings -MappingsB $newMappings
                        $needsToBeReplaced = (-not $mappingExists)
                    }
                    else {
                        # In Add mode, mappingExists is true if all new mappings are already present in existing
                        $toAdd = @($newMappings | Where-Object { $existingMappings -notcontains $_.Trim() })
                        $mappingExists = ($toAdd.Count -eq 0)
                        $needsToBeReplaced = (-not $mappingExists)
                    }
                }
            }

            # Determine whether to modify
            $shouldModify = ($needsToBeReplaced -or ($canBeReplaced -and $Force))

            if ($shouldModify) {
                if ($Replace) {
                    $targetDesc = "Replace mappings for $samAccountName ($($newMappings.Count) mapping(s))"
                    if ($PSCmdlet.ShouldProcess("ADUser: $samAccountName", $targetDesc)) {
                        Set-ADUser -Identity $samAccountName -Replace @{ altSecurityIdentities = [string[]]$newMappings }
                        $replaced = $true
                    }
                }
                else {
                    $toAdd = @($newMappings | Where-Object { $existingMappings -notcontains $_.Trim() })
                    if ($toAdd.Count -gt 0) {
                        $targetDesc = "Add $($toAdd.Count) mapping(s) for $samAccountName"
                        if ($PSCmdlet.ShouldProcess("ADUser: $samAccountName", $targetDesc)) {
                            Set-ADUser -Identity $samAccountName -Add @{ altSecurityIdentities = [string[]]$toAdd }
                            $replaced = $true
                        }
                    }
                }
            }

            [PSCustomObject]@{
                Account           = $samAccountName
                NationalID        = $nationalID
                MappingExists     = $mappingExists
                CanBeReplaced     = $canBeReplaced
                NeedsToBeReplaced = $needsToBeReplaced
                Replaced          = $replaced
            }

            if ($Sleep -gt 0) {
                Start-Sleep -Seconds $Sleep
            }
        }
    }
}
