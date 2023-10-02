<#
Update-IP-Ranges.ps1

This script will update network IP Ranges configured in vRA 8.x.  It reads an input file containing a list of networks 
and the corresponding IP information.  It will search the configured IP Ranges in vRA8, and create IP Ranges to match 
networks found in Input file, as well as associate VLANs/Portgroups defined in the Input file.  If the IP Range exists, 
it will be updated with information from the input file.

Disclaimer:  This script was obtained from https://github.com/cybersylum
  * You are free to use or modify this code for your own purposes.
  * No warranty or support for this code is provided or implied.  
  * Use this at your own risk.  
  * Testing is highly recommended.
#>

##
## Define Environment Variables
##

$ImportFile = "network-ip-info.csv"   #First row must by header which is used by script - it should be PortGroup,Gateway,SubnetMask,NetworkAddress,CIDR,2ndIP,End
# hard-coded values that will be used for all Networks

#Verify Import File exists
if ((Test-Path -Path $ImportFile -PathType Leaf) -eq $False) {
    write-host ""
    write-host "Import File not found - " + $Import File + " - cannot continue..."
    write-host ""
    exit
}

$vRAServer = "vra8.domain.com"
$vRAUser = "user@domain.com"
$DateStamp=Get-Date -format "yyyyMMdd"
$TimeStamp=Get-Date -format "hhmmss"
$RunLog = "Update-vRA-Networks-IP-Info-$DateStamp-$TimeStamp.log"
$RateLimit=30
$RatePause=2
#QueryLimit is used to control the max rows returned by invoke-restmethod (which has a default of 100)
$QueryLimit=9999

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

function Get-IP-Range {

    param (
        $IpRangeName    
    )

    $results=$false

    #$DefinedRanges = (Invoke-vRARestMethod -Method GET -URI "/iaas/api/network-ip-ranges" -WebRequest).content | ConvertFrom-JSON -AsHashtable
    #Load IP Ranges from vRA
$Body = @{
    '$top' = $QueryLimit
}
$APIparams = @{
    Method = "GET"
    Uri = "https://$vRAServer/iaas/api/network-ip-ranges"
    Authentication = "Bearer"
    Token = $APItoken
    Body = $Body
}
try{
    $DefinedRanges = (Invoke-RestMethod @APIparams -SkipCertificateCheck).content
} catch {
    Write-Log $RunLog $("    Unable to get IP Ranges from vRA")
    Write-Log $RunLog $Error
    Write-Log $RunLog $Error[0].Exception.GetType().FullName
}

    foreach ($range in $DefinedRanges) {
        if ($range.name -eq $IpRangeName) {
            $results=$range.id
            break
        }
    }

    return $results
}

function Get-Matching-NetworkIDs {

    param (
        $PortGroup    
    )

    $MatchingNetworkIDs = @{} 

    Write-Log $RunLog $("       searching for networks called - " + $PortGroup)

    #$DefinedNetworks = (Invoke-vRARestMethod -Method GET -URI "/iaas/api/fabric-networks-vsphere" -WebRequest).content | ConvertFrom-JSON -AsHashtable
    $Body = @{
        '$top' = $QueryLimit
    }
    $APIparams = @{
        Method = "GET"
        Uri = "https://$vRAServer/iaas/api/fabric-networks-vsphere"
        Authentication = "Bearer"
        Token = $APItoken
        Body = $Body
    }
    try{
        $DefinedNetworks = (Invoke-RestMethod @APIparams -SkipCertificateCheck).content
    } catch {
        Write-Log $RunLog $("    Unable to get networks from vRA")
        Write-Log $RunLog $Error
        Write-Log $RunLog $Error[0].Exception.GetType().FullName
    }
    foreach ($item in $DefinedNetworks) {
        if ($item.name -eq $PortGroup) {
            $MatchingNetworkIDs.add($item.id,$item.id)
            Write-Log $RunLog $("       Found Matching network id - " + $Item.id)
        }
    }

    $Results=""
    foreach ($item in $MatchingNetworkIDs.keys) {
        $Results += '"' + $($item) + '",'
    }

    #Remove trailing comma
    $Results = $Results.Substring(0,($Results.length-1))

    return $Results
}

function Update-IP-Range { 
    param (
        $ID,
        $Name,
        $StartIP,
        $EndIP,
        $Network
    )   

    Write-Log $RunLog $("Updating IP Range - " + $Name + "/" + $ID)

        #get fabicNetworkIDs for all matching networks to associate them with this IP Range
        Write-Log $RunLog $("   Looking up all fabric ids that match name - " + $Network)
        $FabricRefs = Get-Matching-NetworkIDs $Network
    
$json = @"
{
    "fabricNetworkIds": [
        $FabricRefs
    ],
    "startIPAddress": "$StartIP",
    "endIPAddress": "$EndIP"
}
"@   

    Try {
        $Results=Invoke-vRARestMethod -Method PATCH -URI "/iaas/network-ip-ranges/$ID" -Body $json
        Write-Log $RunLog $Results
    } catch {
        Write-Log $RunLog "    Unable to update IP Range - " + $Name + "/" + $ID
        Write-Log $RunLog $Error
        Write-Log $RunLog $Error[0].Exception.GetType().FullName
    }
}

function Create-IP-Range { 
    param (
        $Name,
        $StartIP,
        $EndIP,
        $Network
    )   

    Write-Log $RunLog $("Creating IP Range - " + $Name)

    #get fabicNetworkIDs for all matching networks to associate them with this IP Range
    Write-Log $RunLog $("   Looking up all fabric ids that match name - " + $Network)
    $FabricRefs = Get-Matching-NetworkIDs $Network

$json = @"
{
    "fabricNetworkIds": [
        $FabricRefs
    ],
    "ipVersion": "IPv4",
    "name": "$Name",
    "startIPAddress": "$StartIP",
    "endIPAddress": "$EndIP"
}
"@

Try {
    $Results=Invoke-vRARestMethod -Method POST -URI "/iaas/network-ip-ranges" -Body $json
    Write-Log $RunLog $Results
} catch {
    Write-Log $RunLog "    Unable to create IP Range - " + $Name
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

#Connect to vRA
write-host "Connecting to Aria Automation - $vRAServer as $vRAUser"
$vRA=connect-vraserver -server $vRAServer -Username "$vRAUser" -IgnoreCertRequirements
if ($vRA -eq $null) {
    write-host "Unable to connect to vRA Server '$vRAServer'..."
    Write-Log $RunLog ("Unable to connect to vRA Server '$vRAServer'...")
    exit
}

#Grab the bearer token for use with invoke-restmethod
$APItoken= $vRA.token | ConvertTo-SecureString -AsPlainText -Force


write-host "Updating IP Ranges with information from $ImportFile"
Write-Log $RunLog $("Updating IP Ranges with information from $ImportFile")

#Store Networks (portgroup/vlan) that have been updated to avoid duplicate effort (input file could have multiple like named networks)
$UpdatedNetworks = @{}  

$RateCounter = 0
foreach ($IpRange in $NetworkData.GetEnumerator()) {

    if ($UpdatedNetworks.$($IpRange.PortGroup) -ne $true) {
        $IpRangeID = Get-IP-Range $($IpRange.NetworkAddress)

        #Update or Create the IP Range
        if ($IpRangeID -ne $false) {
            Update-IP-Range $IpRangeID $IpRange.NetworkAddress $IpRange.StartAddr $IpRange.LastAddr $IpRange.PortGroup
        } else {
            Create-IP-Range $IpRange.NetworkAddress $IpRange.StartAddr $IpRange.LastAddr $IpRange.PortGroup
        }
    
        #Add this portgroup to the UpdatedNetworks tracker
        $UpdatedNetworks.add($IpRange.PortGroup,$true)

        #Rate Limit to avoid overload
        $RateCounter++
        if ($RateCounter -gt $RateLimit) {
            sleep $RatePause
            $RateCounter=0
        }

    } else {
        #Portgroup for this input file item has already been processed.  When IP Range is added, all networks with same name are associated with the IP Range
        Write-Log $RunLog ("IP Range for " + $($IPRange.PortGroup) + "/" + $($IPRange.NetworkAddress) + " has already been processed - skipping...")
    }

    write-host -NoNewline "."
   
}

# Clean up
write-host
Write-Host "More details available in the log - $RunLog"
Disconnect-vRAServer -Confirm:$false