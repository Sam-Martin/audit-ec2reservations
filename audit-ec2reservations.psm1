
function Find-EC2InstanceReservationMatches{
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true)]
        [string]$region,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [array]$EnrichedInstances
    )
    # Fetch reservations that exist in this account and are active
    $reservations = Get-EC2ReservedInstance -Region $region | ?{$_.state -eq 'active'}; 


    # Loop through identified instances and match them to reservations
    foreach($instance in $($EnrichedInstances | ?{$_."ImageType"})){
    
        Write-Verbose "Trying to match reservation for $($instance.InstanceObj.RunningInstance.InstanceID)"
        # Match the instance to reservations based on relevant criteria
        $matchedReservations = $reservations | ?{
            $_.AvailabilityZone -eq $instance.instanceObj.RunningInstance.Placement.AvailabilityZone -and 
            $_.InstanceType -eq $instance.instanceObj.RunningInstance.InstanceType -and 
            $_.ProductDescription -eq $instance."ImageType" -and
            $_.InstanceCount -gt 0}
    
        # If we didn't match the instance to a reservation to a reservation, just skip to the next instance
        if(!$matchedReservations){
            $matchedReservations = $null;
            continue;
        }    
    
        # Get the first matched reservation and decrement its count
        $matchedReservations[0].InstanceCount--;

        # Mark the instance as reserved
        $instance.reserved = $true;
    }
    return New-Object PSObject -Property @{"EnrichedInstances"=$EnrichedInstances;"Reservations"=$reservations};
}

function Get-ReservationType{
    param(
        [parameter(Mandatory=$true)]
        [Amazon.EC2.Model.Reservation]$instance,
        [parameter(Mandatory=$true)]
        [string]$ImageDescription,
        [parameter(Mandatory=$true)]
        $AMIDescriptionRegexes
    )
    


    Write-Verbose "checking reservation type"
   
    $result = $null;

    foreach($regex in $AMIDescriptionRegexes){
        if($imageDescription -match $regex.Regex){
            $result = $regex.result
            break;
        }
    }

    # If we've identified the instance and the instance is in a VPC, add it to the name
    if($result -and $instance.RunningInstance.vpcID){
        return $result + " (Amazon VPC)";
    }else{
        return $result
    }

}

Function Get-ImageDescription {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true)]
        [Amazon.EC2.Model.Reservation]$instance
    );
    
    $imageID = $instance.RunningInstance.imageid

    # Try to get the image's description from Amazon's API
    try{
        $imageDescription = Get-EC2Image -ImageIds $imageID | select -ExpandProperty description
    }catch{}
    if(!$imageDescription){

        # Amazon doesn't return a result? Better check thecloudmarket.com!
        try{
            Write-Verbose "Accessing http://thecloudmarket.com/image/$($imageID)";
            $cloudMarketResult = Invoke-WebRequest "http://thecloudmarket.com/image/$($imageID)" -ErrorAction Stop
            $imageDescription = ((($cloudMarketResult.AllElements |?{$_.id -eq "detailsform"}).innertext -split "`r`n" | ?{$_.contains("Description")}) -replace "Description").trim();
        }catch{
            Write-Verbose "Unable to find id at http://thecloudmarket.com/image/$($imageID)"
            
        }
    }

    return $imageDescription
}

function Get-EC2InstancesEnrichedWithInstanceType{
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true)]
        [string]$region,
        [parameter(Mandatory=$true)]
        $AMIDescriptionRegexes,
        [parameter(Mandatory=$false)]
        $knownAMIs
    )
    # Prepare arrays
    $EnrichedInstances = @();

    # Get instances
    Write-Verbose "Fetching EC2 instances from $region";
    $instances = Get-EC2Instance -Region $region |
         # Return only running instances
        ?{$_.RunningInstance.State.Name -eq "Running"} 

    # Loop through and identify instances' reservation types
    foreach($instance in $instances){
        
        Write-Verbose "Enriching $($instance.RunningInstance.InstanceID)";

        # Try to match our instance against known AMIs, if not, try to resolve it manually!
        if($reservationType = $($knownAMIs | ?{$_.ImageID -eq $instance.RunningInstance.ImageID}).ImageType){
            Write-Verbose "We already know $( $instance.RunningInstance.ImageID) as $instanceType";
        }else{
            $imageDescription = Get-ImageDescription -instance $instance
       
            # Try to identify the reservation type from the AMI description
            if($imageDescription){
                $reservationType = $(Get-ReservationType -instance $instance -imageDescription $imageDescription -AMIDescriptionRegexes $AMIDescriptionRegexes)
            }else{
                $reservationType = $null;
            }
        }
        
        # Add the information we found to the enriched instance!
        $EnrichedInstances += "" | select @{L="Image Description";E={ $imageDescription}}, 
            @{L="InstanceID";E={$instance.RunningInstance.InstanceID}},
            @{L="ImageType";E={$reservationType}},
            @{L="InstanceObj";E={$instance}},
            @{L="Reserved";E={$null}}
    
    } 
    return $EnrichedInstances;
}