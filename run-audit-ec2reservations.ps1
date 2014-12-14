param(
    $knownAMIsFile = "$(Split-Path (Get-Variable MyInvocation).Value.MyCommand.Path)\knownAMIs.json"
)

$verbosePreference = "Continue";


$scriptDirectory =  Split-Path (Get-Variable MyInvocation).Value.MyCommand.Path ;

Remove-Module audit-ec2reservations
Import-Module $scriptDirectory\audit-ec2reservations.psm1 


# Get the regexes we'll use to match the AMI descriptions to Reservation types
$AMIDescriptionRegexes = $(Get-Content $scriptDirectory\reservationRegexMatching.json | Out-String | ConvertFrom-Json)

# Get known AMIs that we've spidered before
$knownAMIs = $(Get-Content $knownAMIsFile | Out-String | ConvertFrom-Json)

$ReservationMatches = @();

<#
     Match EC2 instances in all regions with their reservations!
#>

foreach($region in (Get-EC2Region).RegionName){
    
    Write-Verbose "Auditing $region"
    
    if($ec2instances = $(Get-EC2InstancesEnrichedWithInstanceType -region $region -AMIDescriptionRegexes $AMIDescriptionRegexes -knownAMIs $knownAMIs)){
        $ReservationMatches += Find-EC2InstanceReservationMatches -region $region -EnrichedInstances $ec2instances -Verbose;
    }
}
$EnrichedInstances = $ReservationMatches.EnrichedInstances; 

<#
     Print results
#>

Write-Host "The following instances are not reserved";

# Bring pertinent information to the front and format it nicely
$EnrichedInstances | ?{$_.reserved -ne $true -and $_."ImageType"} | Select-Object @{L="AvailabilityZone";E={$_.instanceObj.RunningInstance.Placement.AvailabilityZone}}, 
        @{L="Name";E={$_.instanceObj.RunningInstance.tags | ?{$_.key -eq "name"} | Select-Object -ExpandProperty Value}},
        @{L="InstanceType";E={$_.instanceObj.RunningInstance.InstanceType}}, 
        "ImageType" | Sort-Object -Property InstanceType | Format-Table -AutoSize

Write-Host "The following reservations are not used";
$ReservationMatches.reservations  | ?{$_.instanceCount -gt 0} | Select-Object AvailabilityZone, InstanceType, ProductDescription, InstanceCount, End | Format-Table -AutoSize

Write-Host "The following EC2 instances could not be matched";
$EnrichedInstances | ?{!$_."ImageType"} | Select-Object @{L="AvailabilityZone";E={$_.instanceObj.RunningInstance.Placement.AvailabilityZone}}, 
        @{L="Name";E={$_.instanceObj.RunningInstance.tags | ?{$_.key -eq "name"} | Select-Object -ExpandProperty Value}},
        @{L="InstanceType";E={$_.instanceObj.RunningInstance.InstanceType}}, 
        @{L="ImageID";E={$_.instanceObj.RunningInstance.ImageID}},
        "ImageType" | Sort-Object -Property InstanceType | Format-Table -AutoSize

Write-Verbose "Updating known AMI list (please commit the cache back to GIT repo if GIT shows changes!)";
Set-Content $knownAMIsFile $($knownAMIs + $($EnrichedInstances | ?{$_."ImageType"} | select "ImageType", @{L="ImageID";E={$_.instanceObj.RunningInstance.ImageID}}) | select -Unique ImageType, ImageID | ConvertTo-Json)