<#
  .SYNOPSIS
    Function: Get-AzureDevOpsWorkItemTags
    Author: @JamesDBartlett3@techhub.social (James D. Bartlett III)

  .DESCRIPTION
    This script gets a list of all Work Item tags for a project in Azure DevOps.

  .PARAMETER OrganizationName
    The name of the Azure DevOps organization.

  .PARAMETER ProjectName
    The name of the Azure DevOps project.
  
  .PARAMETER PersonalAccessToken
    The personal access token (PAT) to use for authentication.
    This token must have the following scopes:
      - Work items (Read)
  
  .PARAMETER ApiVersion
    The version of the Azure DevOps REST API to use.
    Default: 7.1-preview.1

  .EXAMPLE
    .\Get-AzureDevOpsWorkItemTags.ps1 -OrganizationName "MyOrg" -ProjectName "MyProject" -PersonalAccessToken "MyPAT"

  .OUTPUTS
    Table of tags with the following columns:
      - name
      - id

  .NOTES

#>

Param(
  [Parameter(Mandatory=$true)]
    [string]$OrganizationName
  ,[Parameter(Mandatory=$true)]
    [string]$ProjectName
  ,[Parameter(Mandatory=$true)]
    [string]$PersonalAccessToken
  ,[Parameter(Mandatory=$false)]
    [string]$ApiVersion = "7.1-preview.1"
)

# Create the Authorization header
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($PersonalAccessToken)"))

# Define the URL to call the Tags - List endpoint
$url = "https://dev.azure.com/$OrganizationName/$ProjectName/_apis/wit/tags?api-version=$ApiVersion"

# Call the endpoint
$response = Invoke-RestMethod -Uri $url -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}

# Output the response
$response.value | Select-Object name, id