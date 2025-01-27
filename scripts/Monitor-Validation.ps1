#!/usr/bin/env pwsh

<#
.SYNOPSIS
Queries Azure Function for Attestation status in Microsoft Subscription.

.PARAMETER QueryURI
The OrchestrationId returned from Run-Validation
Alias -id

.EXAMPLE 
Queries the function for attestation status:

C:\> Monitor-Validation -ID <orchestrationId>

#>

Param(
    [Parameter(Mandatory = $true)] [Alias('id')] [string] $OrchestrationId
)

$FunctionUrl = "https://fpga-attestation.azurewebsites.net/api/ComputeFPGA_HttpGetStatus"

$AccountInforamtion = $(az account show)
if ($null -eq $AccountInforamtion) {
    Write-Error -Message "Failed to get account information" -Category InvalidArgument
    Write-Warning 'Check if you are already logged in to the appropriate Azure account'
    exit 1
}

$TenantId = $(az account show --output tsv --query tenantId)
$SubscriptionId = $(az account show --output tsv --query id)

try {
    $RequestBodyProperties = @{
        ClientSubscriptionId = $SubscriptionId;
        ClientTenantId = $TenantId;
        OrchestrationId = $OrchestrationId
    } | ConvertTo-Json| % { [System.Text.RegularExpressions.Regex]::Unescape($_) }

    $postResult = Invoke-WebRequest -Uri $FunctionUrl -Method POST  -ContentType "application/json" -Body $RequestBodyProperties -UseBasicParsing
}
catch {
    $body = $error[0].ErrorDetails.Message
    $StatusCode = [int] $error[0].Exception.Response.StatusCode
    $ReasonPhrase = $error[0].Exception.Response.ReasonPhrase
    Write-Error "Error starting the attestation function"
    Write-Error "${StatusCode} - ${ReasonPhrase}"
    Write-Error $body
}

$postContent = ConvertFrom-Json $postResult.Content

while ("Running" -eq $postContent.orchestrationStatus -or "Pending" -eq $postContent.orchestrationStatus) {
    $runtimeStatus = $postContent.orchestrationStatus
    Write-Output "$(Get-Date -Format "MM/dd/yyyy:HH:mm:ss") Status: ${runtimeStatus}"

    Start-Sleep 30     # seconds

    $postResult = Invoke-WebRequest -Uri $FunctionUrl -Method POST  -ContentType "application/json" -Body $RequestBodyProperties -UseBasicParsing
    $postContent = ConvertFrom-Json $postResult.Content
}

$runtimeStatus = "Failed"
if ($postContent.orchestrationOutput[0] -eq "Attestation process succeeded")
{
    $runtimeStatus = "Completed"
}

Write-Output "$(Get-Date -Format "MM/dd/yyyy:HH:mm:ss") Validation completed. Result: ${runtimeStatus}"

Write-Output "Please check your storage account for output files of this validation."

if ($null -ne $postContent.orchestrationOutput) {
    Write-Output "Output:"
    Write-Output $postContent.orchestrationOutput
}
