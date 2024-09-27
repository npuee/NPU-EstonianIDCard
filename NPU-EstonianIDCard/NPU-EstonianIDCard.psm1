#
# By: Nikolai Pulman
#
# On: 3/20/2024
#
 

# Set some global parameters
$global:EstIDLdapURL = "esteid.ldap.sk.ee"
$global:EstIDLdapPort = 636
$global:EstIDLdapDN = "dc=ESTEID,c=EE"
$global:NationalIDDN = "*ou=Authentication,o=Identity card of Estonian citizen,dc=ESTEID,c=EE"
$global:DigitalIDDN = "*ou=Authentication,o=Digital identity card,dc=ESTEID,c=EE"

#
#
#   Version 1.1.0 rewrite
#   Add digital id mapping(Blue cards)
#
#

#
#   Get user mapping from sk.ee as array
#

function Get-IDUserMapping {
    param([Parameter(Mandatory = $true)] [String] $EstonianID) 
    # Define LDAP
    $ldapdn = 'LDAP://' + $global:EstIDLdapURL + ":" + $EstIDLdapPort + "/" + $EstIDLdapDN
    $auth = [System.DirectoryServices.AuthenticationTypes]::Anonymous
    $ldap = New-Object System.DirectoryServices.DirectoryEntry($ldapdn, $null, $null, $auth) 

    # LDAP Searcher
    $ds = New-Object System.DirectoryServices.DirectorySearcher($ldap)
    $IDCodeFilter = "(serialNumber=PNOEE-" + $EstonianID + ")"
    $ds.Filter = $IDCodeFilter
    [void]$ds.PropertiesToLoad.Add("usercertificate;binary")

    # Results
    $SearchResults = $ds.FindAll()

    # Mapping results
    $MappingResults = New-Object System.Collections.Generic.List[System.Object]


    # Search certificates
    foreach ($result in $SearchResults) {
        # National ID
        if ($result.Path -like $global:NationalIDDN ) {
            [byte[]]$ByteCertificate = $Result.Properties.'usercertificate;binary' | out-string -stream
            $mapping = _DecodeCertificate($ByteCertificate)
            $MappingResults.Add( $mapping)
        }
        # Digital ID
        if ($result.Path -like $global:DigitalIDDN ) {
            [byte[]]$ByteCertificate = $Result.Properties.'usercertificate;binary' | out-string -stream
            $mapping = _DecodeCertificate($ByteCertificate)
            $MappingResults.Add( $mapping)
        }

    }

    return $MappingResults
   
}

function Get-ADUserEstonianIDMapping {
    param(
        [Parameter(Mandatory = $true)] [String] $Identity
    )

    # check if activedirectory module exist!
    try {
        Import-Module -name ActiveDirectory
    }
    catch {
        Write-Host "ActiveDirectory Module does not exist"
    }

    # Get AD User mapping
    $userProperties = Get-ADUser -Identity $Identity -Properties altSecurityIdentities
    Return $userProperties.altSecurityIdentities
}



function Set-ADUserEstonianIDMapping {
    [CmdletBinding(DefaultParameterSetName = 'EstonianID')]
    param(
        [Parameter(ParameterSetName = 'EstonianID', Mandatory = $true)]
        [Parameter(ParameterSetName = 'EstonianIDPropertyName')]
        [String]$EstonianID,

        [Parameter(ParameterSetName = 'EstonianIDPropertyName')]
        [string]$EstonianIDPropertyName,
        [Parameter()] [Switch] $Replace,
        [Parameter(Mandatory = $true)] [String] $Identity
    )

    # check if activedirectory module exist!
    try {
        Import-Module -name ActiveDirectory
    }
    catch {
        Write-Host "ActiveDirectory Module does not exist"
    }

    # If we pass national id number
    $_EstonianID = $EstonianID
   
    # If we pass active directory nation ID number property   
    if ($EstonianIDPropertyName) {
        Try {
            $userProperties = Get-ADUser -Identity $Identity -Properties $EstonianIDPropertyName
            $_EstonianID = $userProperties.$EstonianIDPropertyName
        }
        Catch {
            Write-Error 'User national ID code was not found!' -ErrorAction Stop
        }
    }

    # Get ID certificate mapping
    $mapping = Get-IDUserMapping $_EstonianID


    #
    #   Add action if mapping not found
    #

    # Default action is add
    if ($Replace) {
        # For replace we clear first
        Set-ADUser -Identity $Identity -clear altsecurityidentities
    }
    foreach ($map in $mapping) {
        Set-ADUser -Identity $Identity -add @{'altsecurityidentities' = "$map" }
    }   

}


function Set-ADOUEstonianIDMapping {
    param(
        [Parameter(Mandatory = $true)] [String] $DN,
        [Parameter(Mandatory = $true)] [String] $EstonianIDPropertyName,
        [Parameter()] [Switch] $Replace,
        [Parameter()] [Switch] $Force,
        [Parameter()] [Switch] $WhatIf,
        [Parameter()] [int] $Sleep = 0
    )

    # check if activedirectory module exist!
    try {
        Import-Module -name ActiveDirectory
    }
    catch {
        Write-Host "ActiveDirectory does not exist"
    }

    # Collect active users.
    Get-ADUser -Filter 'enabled -eq $true' -SearchBase $DN -Properties $EstonianIDPropertyName | 
    ForEach-Object {
        # Null user variables
        $_samAccountName = ""
        $_nationalID = ""
        $_userCertificateMapping = ""
        $_nationalIDMapping = ""
        $_mappingExists = $false
        $_Can_Be_Replaced = $false
        $_needs_to_be_replaced = $false
        $_replaced = $false
        # Insert User variables
        $_samAccountName = $_.SamAccountName
        $_nationalID = $_.$EstonianIDPropertyName     
        $_userCertificateMapping = Get-ADUserEstonianIDMapping -Identity $_samAccountName

        # If altSecuritymapping mapping needs to be replaced
        if ($_nationalID) {
            try {
                $_nationalIDMapping = Get-IDUserMapping $_nationalID
            }
            catch {
                $_nationalIDMapping = $Null 
            }

            # Check if mapping exist
            if ($_userCertificateMapping -eq $_nationalIDMapping) {
                $_mappingExists = $true
            }
        }

        # If altSecuritymapping can be replaced
        if ($_nationalIDMapping) {
            $_Can_Be_Replaced = $true       
        }

        # If needs to be replaced
        if ($_Can_Be_Replaced -and !$_mappingExists ) {
            $_needs_to_be_replaced = $true    
        }

        # Modify altSecuritymapping that is needed to be replaced
        if ($_needs_to_be_replaced -AND !$WhatIf) {
            if ($Replace) {
                Set-ADUserEstonianIDMapping -Identity $_samAccountName -EstonianIDPropertyName $EstonianIDPropertyName -Replace
            }
            else {
                Set-ADUserEstonianIDMapping -Identity $_samAccountName -EstonianIDPropertyName $EstonianIDPropertyName 
            }
            $_replaced = $true     
        }


        # Modify altSecuritymapping that can be replaced
        if ($_Can_Be_Replaced -AND $Force -AND !$WhatIf) {
            if ($Replace) {
                Set-ADUserEstonianIDMapping -Identity $_samAccountName -EstonianIDPropertyName $EstonianIDPropertyName -Replace
            }
            else {
                Set-ADUserEstonianIDMapping -Identity $_samAccountName -EstonianIDPropertyName $EstonianIDPropertyName 
            }
            $_replaced = $true
        }

        # Output table object.
        new-object psobject -Property @{
            Account              = $_samAccountName
            NationalID           = $_nationalID
            MappingExists        = $_mappingExists  
            Can_Be_Replaced      = $_Can_Be_Replaced
            Needs_to_be_replaced = $_needs_to_be_replaced
            Replaced             = $_replaced
        } 

        # Format output
        Format-Table

        # Seprator
        Write-Host "-----"

        # If sleep is specified then sleep
        if ($Sleep -ge 1) {
            Start-Sleep -Seconds $Sleep
        }
    }# End for each user

}



#
# Helper function to decode certificate:
#

function _DecodeCertificate([byte[]]$CertificateInByte) {
    
    # Create certificate object from byte array
    $Certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2] [byte[]]$CertificateInByte

    # temp variables
    $CertificateSerialArray = $Certificate.SerialNumber.ToCharArray()

    # Reverse certificate serial:
    for ($i = 0; $i -le $CertificateSerialArray.Length; $i = $i + 2 ) {
        $reversed_serial = $CertificateSerialArray[$i] + $CertificateSerialArray[$i + 1] + $reversed_serial 
    }

    # Reverse certificate issuer:
    $CertificateIssuerArray = $Certificate.Issuer.Split(",")

    foreach ($dn in $CertificateIssuerArray) {
        $reversedCertificateIssuer = $dn + "," + $reversedCertificateIssuer
    }

    # Remove empty spaces and trailing coma
    $reversedCertificateIssuer = $reversedCertificateIssuer.replace(', ', ',')
    $reversedCertificateIssuer = $reversedCertificateIssuer.Substring(0, $reversedCertificateIssuer.Length - 1)

    # Strong Name Mapping:
    $mapping = "X509:<I>" + $reversedCertificateIssuer.Trim() + "<SR>" + $reversed_serial
    return $mapping
}
