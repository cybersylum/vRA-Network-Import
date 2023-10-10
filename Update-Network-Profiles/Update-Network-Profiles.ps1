<#
Update-Network-Profiles.ps1

This script will update Network Profiles configured in vRA 8.x.  It reads an input file containing a list of networks 
and the corresponding Network information.  The script will look for networks that are in the same 
Cloud Account as the existing Network Profiles, and update the Network Profile with any network that is listed in the
input file using a name match on the PortGroup data.  It does overwrite any existing networks attached to the Network 
Profile.

Input File Column Headers
 * PortGroup
 * Gateway
 * SubnetMask
 * NetworkAddress
 * CIDR
 * StartAddr
 * LastAddr

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
$RunLog = "Update-Network-Profiles-$DateStamp-$TimeStamp.log"
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

function FilterNetworks {

    param (
        $AllNetworks
    )
    <#
    Takes the a list of Network IDs and returns the Network IDs that match up with network names provided in the input file
    #>

    $Results = @()
    $ExcludedNetworks = @()
    $counter=0

    foreach ($NetworkID in $AllNetworks) {
        # get the full record for the current network
        $thisNetwork = $DefinedNetworks | where-object -Property Id -eq $NetworkID
        #Does the name of the current network exist in the input file (PortGroup field)?
        $IncludeNetwork = $NetworkData | where-object -Property PortGroup -eq $thisNetwork.name
        if ($null -eq $IncludeNetwork.PortGroup) {
            #no match tally count
            $counter++
            $ExcludedNetworks += $NetworkID
        } else {
            $Results += $NetworkID
        }

    }

    if ($counter -gt 0) {
        Write-Log $RunLog $("Found " + $counter + " networks that are not in the input file.  They will be excluded:")
        Write-Log $RunLog $($ExcludedNetworks)
        Write-Log $RunLog " "
    }

    return $Results

}

function ReformatNetworkIDList {

    param (
        $TempList
    )

    <#
    Takes the filtered network collection and reformats into a quoted, comma-delimited list that can be used in an API call
    #>

    $counter=1
    $Last=$TempList.Count
    $Result = ""
    foreach ($NetworkID in $TempList) {
        if ($counter -eq $Last) {
            #add quotes; no comma needed after the last item
            $Result += '"' + $NetworkID + '"'
        } else {
            #add quotes and a comma
            $Result += '"' + $NetworkID + '",'
        }
        $counter++
    }

    return $Result
}


##
## Main Script
##

# Load input file
write-host "Reading input file for Network Information"
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

#Grab the bearer token for use with invoke-restmethod (which is needed for queries with more than 100 results)
$APItoken= $vRA.token | ConvertTo-SecureString -AsPlainText -Force

# Load vRA Network Profiles
write-host "Searching $vRAServer for Network Profiles"
Write-Log $RunLog $("Searching $vRAServer for Network Profiles")

$Body = @{
    '$top' = $QueryLimit
}
$APIparams = @{
    Method = "GET"
    Uri = "https://$vRAServer/iaas/api/network-profiles"
    Authentication = "Bearer"
    Token = $APItoken
    Body = $Body
}

try{
    $NetworkProfiles = (Invoke-RestMethod @APIparams -SkipCertificateCheck).content
} catch {
    Write-Log $RunLog $("    Unable to get network profiles from vRA")
    Write-Log $RunLog $Error
    Write-Log $RunLog $Error[0].Exception.GetType().FullName
}

Write-Log $RunLog $("Found " + $NetworkProfiles.Count + " network profiles in " + $vRAServer)
foreach ($Profile in $NetworkProfiles) {
    Write-Log $RunLog $("    " + $Profile.name + " using Cloud Account -  " + $Profile.cloudAccountId)
}

# Load the defined vRA Networks
write-host "Searching $vRAServer for Defined Networks"
Write-Log $RunLog $("Searching $vRAServer for defined networks")

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

Write-Log $RunLog $("Found " + $DefinedNetworks.Count + " defined networks in " + $vRAServer)

<# 
Loop through each Network Profile. 
    Use the CloudAccountID to get list of Networks that link to that Cloud Account using Where-object
    Take the resulting Network IDs and filter out any Networks that are not included in the input file.
    Then reformat the final list into a quoted, comma-delimited list for API call.
    Update each network profile with that list - overwriting any pre-existing associated Networks
#>

Write-Host "Updating Network Profiles with matching Networks"
Write-Log $RunLog "Updating Network Profiles with matching Networks"

foreach ($NetworkProfile in $NetworkProfiles) {

    Write-Log $RunLog $("Searching for Networks that should reside in Network Profile " + $NetworkProfile.name + " - Cloud Account " + $NetworkProfile.cloudAccountId)
    $CloudMatchNetworkIDs = ""
    $CloudMatchNetworkIDs = $DefinedNetworks | where-object -Property cloudAccountIds -eq $NetworkProfile.cloudAccountId
    Write-Log $RunLog $("   Found " + $CloudMatchNetworkIDs.Count + " networks using that cloud account")

## Need to filter out networks that do not match PortGroup name in input file
    $InputMatchingNetworks = FilterNetworks $CloudMatchNetworkIDs.id

    # convert the array of Cloud Account IDs into a Quoted, comma-delimited list usable in the API call
    $APINetworkIDs = ReformatNetworkIDList $InputMatchingNetworks
    Write-Log $RunLog $("Final list of networks to update in " + $NetworkProfile.name)
    Write-Log $RunLog $APINetworkIDs
    
    write-Log $RunLog $("Updating Network Profile - " + $NetworkProfile.name + " / " + $NetworkProfile.id)
$json = @"
{
    "fabricNetworkIds": [
        $APINetworkIDs
    ]
}
"@  
    $URI =  "/iaas/api/network-profiles/" + $NetworkProfile.id
    
    try {
        $Results=Invoke-vRARestMethod -Method PATCH -URI $URI -Body $json
    } catch {
        Write-Log $RunLog $("       Unable to Update Network Profile")
        Write-Log $RunLog $Results
        Write-Log $RunLog $Error
        Write-Log $RunLog $Error[0].Exception.GetType().FullName
    }

    write-host -NoNewline "."
    Write-Log $RunLog " "
   
}

# Clean up
write-host
Write-Host "More details available in the log - $RunLog"
Disconnect-vRAServer -Confirm:$false