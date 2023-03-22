#
# 
#
# By: Nikolai Pulman
#
# 
# 


#Set some global parameters
$global:EstIDLdapURL = "esteid.ldap.sk.ee"
$global:EstIDLdapPort = 636
$global:EstIDLdapDN = "ou=Authentication,o=Identity card of Estonian citizen,dc=ESTEID,c=EE"

function Get-EstonianIDMapping {
    param(
        [Parameter(Mandatory = $true)] [String] $EstonianID
    )
  
    #Define LDAP
    $ldapdn = 'LDAP://' + $global:EstIDLdapURL + ":" + $EstIDLdapPort + "/" + $EstIDLdapDN
    $auth = [System.DirectoryServices.AuthenticationTypes]::Anonymous
    $ldap = New-Object System.DirectoryServices.DirectoryEntry($ldapdn, $null, $null, $auth) 

    #LDAP Searcher
    $ds = New-Object System.DirectoryServices.DirectorySearcher($ldap)
    $IDCodeFilter = "(serialNumber=PNOEE-" + $EstonianID + ")"

    $ds.Filter = $IDCodeFilter
    [void]$ds.PropertiesToLoad.Add("usercertificate;binary")

    #Results
    $SearchResults = $ds.FindAll()

    #Terminate if National Certificate was not found:
    if ($SearchResults.Count -Eq 0) {
        Write-Error 'User Certificate not found!' -ErrorAction Stop
    }

    #Export certificate to byte array
    [byte[]]$ByteCertificate = $SearchResults[0].Properties.'usercertificate;binary' | out-string -stream

    #Create certificate object from byte array
    $Certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2] [byte[]]$ByteCertificate

    #temp variables
    $CertificateSerialArray = $Certificate.SerialNumber.ToCharArray()

    #Reverse certificate serial:
    for ($i = 0; $i -le $CertificateSerialArray.Length; $i = $i + 2 ) {
        $reversed_serial = $CertificateSerialArray[$i] + $CertificateSerialArray[$i + 1] + $reversed_serial 
    }

    #Reverse certificate issuer:
    $CertificateIssuerArray = $Certificate.Issuer.Split(",")

    foreach ($dn in $CertificateIssuerArray) {
        $reversedCertificateIssuer = $dn + "," + $reversedCertificateIssuer
    }

    #Remove empty spaces and trailing coma
    $reversedCertificateIssuer = $reversedCertificateIssuer.replace(', ', ',')
    $reversedCertificateIssuer = $reversedCertificateIssuer.Substring(0, $reversedCertificateIssuer.Length - 1)

    #Strong Name Mapping:
    $mapping = "X509:<I>" + $reversedCertificateIssuer.Trim() + "<SR>" + $reversed_serial
    return $mapping
}

function Get-ADUserEstonianIDMapping {
    param(
        [Parameter(Mandatory = $true)] [String] $Identity
    )

    #check if activedirectory module exist!
    try {
        Import-Module -name ActiveDirectory
    }
    catch {
        Write-Host "ActiveDirectory does not exist"
    }

    #Get AD User mapping
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
        [Parameter()] [Boolean] $Replace = $false,
        [Parameter(Mandatory = $true)] [String] $Identity
    )

    #check if activedirectory module exist!
    try {
        Import-Module -name ActiveDirectory
    }
    catch {
        Write-Host "ActiveDirectory does not exist"
    }

    #If we pass national id number
    $_EstonianID = $EstonianID
   
    #If we pass active directory nation ID number property   
    if ($EstonianIDPropertyName) {
        Try {
            $userProperties = Get-ADUser -Identity $Identity -Properties $EstonianIDPropertyName
            $_EstonianID = $userProperties.$EstonianIDPropertyName
        }
        Catch {
            Write-Error 'User national ID code was not found!' -ErrorAction Stop
        }
    }

    #Get ID certificate mapping
    $mapping = Get-EstonianIDMapping $_EstonianID

    #Default action is add
    if ($Replace) {
        Set-ADUser -Identity $Identity -replace @{'altsecurityidentities' = "$mapping" }
    }
    else {
        Set-ADUser -Identity $Identity -add @{'altsecurityidentities' = "$mapping" }
    }

}


function Set-ADOUEstonianIDMapping {
    param(
        [Parameter(Mandatory = $true)] [String] $DN,
        [Parameter(Mandatory = $true)] [String] $EstonianIDPropertyName,
        [Parameter()] [Boolean] $Replace = $false,
        [Parameter()] [Boolean] $Force = $false,
        [Parameter()] [Boolean] $safe = $false
    )

    #check if activedirectory module exist!
    try {
        Import-Module -name ActiveDirectory
    }
    catch {
        Write-Host "ActiveDirectory does not exist"
    }

    #Collect active users.
    $ActiveDirectoryUsers = Get-ADUser -Filter 'enabled -eq $true' -SearchBase $DN -Properties $EstonianIDPropertyName

    #Loop collected users.
    foreach ($user in $ActiveDirectoryUsers) {
        #Null user variables
        $_samAccountName = ""
        $_nationalID = ""
        $_userCertificateMapping = ""
        $_nationalIDMapping = ""
        $_mappingExists = $false
        $_Can_Be_Replaced = $false
        $_needs_to_be_replaced = $false
        $_replaced = $false
        #Insert User variables
        $_samAccountName = $user.SamAccountName
        $_nationalID = $user.$EstonianIDPropertyName     
        $_userCertificateMapping = Get-ADUserEstonianIDMapping -Identity $_samAccountName

        #If alt mapping needs to be replaced
        if ($_nationalID) {
            $_nationalIDMapping = Get-EstonianIDMapping $_nationalID
            #Check if mapping exist
            if ($_userCertificateMapping -eq $_nationalIDMapping) {
                $_mappingExists = $true
            }
        }

        #If mapping can be replaced
        if ($_nationalIDMapping) {
            $_Can_Be_Replaced = $true
        
        }

        #If needs to be replaced
        if ($_Can_Be_Replaced -and !$_mappingExists ) {
            $_needs_to_be_replaced = $true    
        }

        #Replace altSecuritymapping that is needed to be replaced
        if ($_needs_to_be_replaced -AND !$safe) {
            Set-ADUserEstonianIDMapping -Identity $_samAccountName -EstonianIDPropertyName $EstonianIDPropertyName -Replace $Replace 
            $_replaced = $true     
        }

        #Replace all that can be replaced
        if ($_Can_Be_Replaced -AND $Force -AND !$safe) {
            Set-ADUserEstonianIDMapping -Identity $_samAccountName -EstonianIDPropertyName $EstonianIDPropertyName -Replace $Replace
            $_replaced = $true
        }


        #Output table object.
        new-object psobject -Property @{
            Account              = $_samAccountName
            NationalID           = $_nationalID
            MappingExists        = $_mappingExists  
            Existing_Mapping     = $_userCertificateMapping
            New_Mapping          = $_nationalIDMapping
            Can_Be_Replaced      = $_Can_Be_Replaced
            Needs_to_be_replaced = $_needs_to_be_replaced
            Replaced             = $_replaced
        } 
        #Format output
        Format-Table
        # Suspend the script for 1 seconds
        Start-Sleep -Seconds 1
    }# End for each user
}
