$resourceModulePath = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
$modulesFolderPath = Join-Path -Path $resourceModulePath -ChildPath 'Modules'

$aDCommonModulePath = Join-Path -Path $modulesFolderPath -ChildPath 'ActiveDirectoryDsc.Common'
Import-Module -Name $aDCommonModulePath

$dscResourceCommonModulePath = Join-Path -Path $modulesFolderPath -ChildPath 'DscResource.Common'
Import-Module -Name $dscResourceCommonModulePath

$script:localizedData = Get-LocalizedData -DefaultUICulture 'en-US'

<#
    .SYNOPSIS
        Returns the current state of the specified service principal name.

    .PARAMETER ServicePrincipalName
        The full SPN to add or remove, e.g. HOST/LON-DC1.
#>
function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ServicePrincipalName
    )

    Write-Verbose -Message ($script:localizedData.GetServicePrincipalName -f $ServicePrincipalName)

    $spnAccounts = Get-ADObject -Filter { ServicePrincipalName -eq $ServicePrincipalName } -Properties 'SamAccountName' |
        Select-Object -ExpandProperty 'SamAccountName'

    if ($spnAccounts.Count -eq 0)
    {
        # No SPN found
        Write-Verbose -Message ($script:localizedData.ServicePrincipalNameAbsent -f $ServicePrincipalName)

        $returnValue = @{
            Ensure               = 'Absent'
            ServicePrincipalName = $ServicePrincipalName
            Account              = ''
        }
    }
    else
    {
        # One or more SPN(s) found, return the account name(s)
        Write-Verbose -Message ($script:localizedData.ServicePrincipalNamePresent -f $ServicePrincipalName, ($spnAccounts -join ';'))

        $returnValue = @{
            Ensure               = 'Present'
            ServicePrincipalName = $ServicePrincipalName
            Account              = $spnAccounts -join ';'
        }
    }

    return $returnValue
}

<#
    .SYNOPSIS
        Add or remove the service principal name.

    .PARAMETER Ensure
        Specifies if the service principal name should be added or removed.

    .PARAMETER ServicePrincipalName
        The full SPN to add or remove, e.g. HOST/LON-DC1.

    .PARAMETER Account
        The user or computer account to add or remove the SPN to , e.g. User1 or
        LON-DC1$.
#>
function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [Parameter()]
        [ValidateSet('Present', 'Absent')]
        [System.String]
        $Ensure = 'Present',

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ServicePrincipalName,

        [Parameter()]
        [AllowEmptyString()]
        [System.String]
        $Account
    )

    # Test if the resource needs changing if called with Invoke-DscResource -Method Set
    $inDesiredConfiguration = Test-TargetResource @PSBoundParameters
    if ($inDesiredConfiguration)
    {
        return
    }

    # Get all Active Directory object having the target SPN configured.
    $spnAccounts = Get-ADObject -Filter { ServicePrincipalName -eq $ServicePrincipalName } -Properties 'SamAccountName', 'DistinguishedName'

    if ($Ensure -eq 'Present')
    {
        <#
            Throw an exception, if no account was specified or the account does
            not exist.
        #>
        if ([System.String]::IsNullOrEmpty($Account) -or ($null -eq (Get-ADObject -Filter { SamAccountName -eq $Account })))
        {
            throw ($script:localizedData.AccountNotFound -f $Account)
        }

        # Remove the SPN(s) from any extra account.
        foreach ($spnAccount in $spnAccounts)
        {
            if ($spnAccount.SamAccountName -ne $Account)
            {
                Write-Verbose -Message ($script:localizedData.RemoveServicePrincipalName -f $ServicePrincipalName, $spnAccount.SamAccountName)

                Set-ADObject -Identity $spnAccount.DistinguishedName -Remove @{
                    ServicePrincipalName = $ServicePrincipalName
                }
            }
        }

        <#
            Add the SPN to the target account. Use Get-ADObject to get the target
            object filtered by SamAccountName. Set-ADObject does not support the
            field SamAccountName as Identifier.
        #>
        if ($spnAccounts.SamAccountName -notcontains $Account)
        {
            Write-Verbose -Message ($script:localizedData.AddServicePrincipalName -f $ServicePrincipalName, $Account)

            Get-ADObject -Filter { SamAccountName -eq $Account } |
                Set-ADObject -Add @{
                    ServicePrincipalName = $ServicePrincipalName
                }
        }
    }

    # Remove the SPN from any account
    if ($Ensure -eq 'Absent')
    {
        foreach ($spnAccount in $spnAccounts)
        {
            Write-Verbose -Message ($script:localizedData.RemoveServicePrincipalName -f $ServicePrincipalName, $spnAccount.SamAccountName)

            Set-ADObject -Identity $spnAccount.DistinguishedName -Remove @{
                ServicePrincipalName = $ServicePrincipalName
            }
        }
    }
}

<#
    .SYNOPSIS
        Tests the service principal name.

    .PARAMETER Ensure
        Specifies if the service principal name should be added or removed.

    .PARAMETER ServicePrincipalName
        The full SPN to add or remove, e.g. HOST/LON-DC1.

    .PARAMETER Account
        The user or computer account to add or remove the SPN to, e.g. User1 or
        LON-DC1$.
#>
function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter()]
        [ValidateSet('Present', 'Absent')]
        [System.String]
        $Ensure = 'Present',

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ServicePrincipalName,

        [Parameter()]
        [AllowEmptyString()]
        [System.String]
        $Account
    )

    $currentConfiguration = Get-TargetResource -ServicePrincipalName $ServicePrincipalName

    $desiredConfigurationMatch = $currentConfiguration.Ensure -eq $Ensure

    if ($Ensure -eq 'Present')
    {
        $desiredConfigurationMatch = $desiredConfigurationMatch -and
        $currentConfiguration.Account -eq $Account
    }

    if ($desiredConfigurationMatch)
    {
        Write-Verbose -Message ($script:localizedData.ServicePrincipalNameInDesiredState -f $ServicePrincipalName)
    }
    else
    {
        Write-Verbose -Message ($script:localizedData.ServicePrincipalNameNotInDesiredState -f $ServicePrincipalName)
    }

    return $desiredConfigurationMatch
}
