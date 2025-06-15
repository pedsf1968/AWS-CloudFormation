# Copy files so S3

[CmdletBinding()]
param (
    [String]
    $bucket = "hawkfund-cloudformation",
    [String]
    $bucketKey = "",
    [String]
    $days = 1
)

$resources = @(
    "51_VPCPrivateConnectivityVPCPeering"
    "54_VPCGatewayEndpointForS3"
    "58_VPCInterfaceEndPointForSQS"
    "62_VPCPrivateLink"
    "71_TransitGatewayFullRouting"
    "72_TransitGatewayRestrictedRouting"
    "90_SiteToSiteVpn"
)

foreach ($resource in $resources) {
    $files = $(Get-ChildItem -Path $resource\*.yaml |where {$_.lastwritetime -gt (get-date).adddays(-$days)} | Select-Object Name)

    foreach ($f in $files) {
        $fileName =  $f.Name
        aws s3 cp $resource/$fileName s3://$bucket/$resource/$fileName
    }
}

