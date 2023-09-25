<#
Update-vRA-Networks-CIDR.ps1

This script will update network information in vRA 8.x.  It reads an input file containing a list of networks 
and the corresponding IP information.  It will search vRA networks and update any matching networks that vRA has discovered.

Disclaimer:  This script was obtained from https://github.com/cybersylum
  * You are free to use or modify this code for your own purposes.
  * No warranty or support for this code is provided or implied.  
  * Use this at your own risk.  
  * Testing is highly recommended.
#>

##
## Define Environment Variables
##

$ImportFile = "/users/user/Desktop/vRA Network Import/network-ip-info.csv"   #First row must by header which is used by script - it should be PortGroup,Gateway,SubnetMask,NetworkAddress,CIDR,2ndIP,End
# hard-coded values that will be used for all Networks
$DNS1 = "192.168.1.14"
$DNS2 = "192.168.4.14"
$DNSSearch = "yourdomain.com"
$Domain = "yourdomain.com"
$vRAUser = "user@yourdomain.com"

$DateStamp=Get-Date -format "yyyyMMdd"
$TimeStamp=Get-Date -format "hhmmss"
$RunLog = "Update-vRA-Networks-IP-Info-$DateStamp-$TimeStamp.log"
$RateLimit=30
$RatePause=2

##
## Function declarations
##
function Write-Log  {

    param (
        $LogFile,
        $LogMessage    
    )

    # complex strings may require () around message paramter 
    # Write-Log $RunLog ("Read " + $NetworkData.count + " records from $ImportFile. 1st Row is expected to be Column Names as defined in script.")

    $LogMessage | out-file -FilePath $LogFile -Append
}

function Get-Network-IP-Info {

    param (
        $VLANname,
        $NetworkList    
    )

    $Value="NA"

    foreach ($net in $NetworkList) {
        if ($Net.PortGroup -eq $VLANname) {
            $Value = $net
            break
        }
    }

    return $Value
}


function Update-vRA-Network {

    param (
        $NetworkID,
        $CIDR,
        $IPGateway
    )

#build JSON payload - seems to have syntax requirements to be at line position 1
$json = @"
{
    "domain": "$Domain",
    "defaultGateway": "$IPGateway",
    "dnsServerAddresses": [
        "$DNS1",
        "$DNS2"
    ],
    "dnsSearchDomains": [
        "$DNSSearch"
    ],
    "cidr": "$CIDR"
}
"@

    Try {
        $Results=Invoke-vRARestMethod -Method PATCH -URI "/iaas/api/fabric-networks-vsphere/$NetworkID" -Body $json
        Write-Log $RunLog $Results
    } catch {
        Write-Log $RunLog $("    Unable to update network - " + $NetworkID)
        Write-Log $RunLog $Error
        Write-Log $RunLog $Error[0].Exception.GetType().FullName
    }
}

##
## Main Script
##

# Load input file
write-host "Reading input file for Portgroup IP Information"
if (-not(Test-Path -Path $ImportFile -PathType Leaf)) {
    write-host "Input file '$ImportFile' not found..."
    exit
} else {
    $NetworkData = import-csv $ImportFile
    Write-Log $RunLog ("Read " + $NetworkData.count + " records from $ImportFile. 1st Row is expected to be Column Names as defined in script.")

}

$vRA=connect-vraserver -server $vRAServer -Username "$vRAUser" -IgnoreCertRequirements
if ($null -eq $vRA) {
    write-host "Unable to connect to vRA Server '$vRAServer'..."
    Write-Log $RunLog ("Unable to connect to vRA Server '$vRAServer'...")
    exit
}

# Get vRA-defined Networks (Resources -> Networks) and build lookup table
Write-Host "Searching vRA for discovered networks"
Write-Log $RunLog "Searching vRA for discovered networks"
$Networks = (Invoke-vRARestMethod -Method GET -URI "/iaas/api/fabric-networks-vsphere" -WebRequest).content | ConvertFrom-JSON -AsHashtable

write-host "Updating IP Info on each discovered network"
Write-Log $RunLog "Updating IP Info on each discovered network"
$Counter=0
foreach ($Network in $Networks.content) {
    $ThisNetworkInfo = Get-Network-IP-Info $Network.name $NetworkData
    If ($ThisNetworkInfo -eq "NA") {
        Write-Log $RunLog ("No Network IP information found in input file for " + $Network.name + "/" + $Network.id)
    } else {
        Write-Log $RunLog ("Network " + $ThisNetworkInfo.PortGroup + "/" + $Network.id + " has IP info available - attempting update...")
        write-host -nonewline "."
        Update-vRA-Network $Network.id $ThisNetworkInfo.CIDR $ThisNetworkInfo.Gateway
        #Rate Limit to avoid overload
        $Counter++
        if ($Counter -gt $RateLimit) {
            sleep $RatePause
            $Counter=0
        }
    }
}

# Clean up
Disconnect-vRAServer -Confirm:$false