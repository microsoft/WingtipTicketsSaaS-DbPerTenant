<#
.SYNOPSIS
    Returns an integer tenant key from a normalized tenant name for use in the catalog.
#>
function Get-TenantKey
{
    param
    (
        # Tenant name 
        [parameter(Mandatory=$true)]
        [String]$TenantName
    )

    $normalizedTenantName = $TenantName.Replace(' ', '').ToLower()

    # Produce utf8 encoding of tenant name 
    $utf8 = New-Object System.Text.UTF8Encoding
    $tenantNameBytes = $utf8.GetBytes($normalizedTenantName)

    # Produce the md5 hash which reduces the size
    $md5 = new-object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
    $tenantHashBytes = $md5.ComputeHash($tenantNameBytes)

    # Convert to integer for use as the key in the catalog 
    $tenantKey = [bitconverter]::ToInt32($tenantHashBytes,0)

    return $tenantKey
}

function Get-Configuration
{
$configuration = @{`
        TenantDatabaseTemplate = "TenantDatabaseTemplate.json"
        TenantBacpacUrl = "https://wtpdeploystorageaccount.blob.core.windows.net/wingtip-bacpacsvnext/wingtiptenantdb.bacpac"
        CatalogDatabaseName = "tenantcatalog"
        CatalogNameStem = "catalog-"
        TenantServerNameStem = "tenants1-"
        TenantPoolNameStem = "Pool"
        CatalogShardMapName = "tenantcatalog"
        CatalogAdminUserName = "developer"
        CatalogAdminPassword = "P@ssword1"
        TenantAdminUsername = "developer"
        TenantAdminPassword = "P@ssword1"
        StorageKeyType = "SharedAccessKey"
        StorageAccessKey = (ConvertTo-SecureString -String "?" -AsPlainText -Force)
        DefaultVenueType = "multipurpose"
        }
    return $configuration
}




