<#
  .SYNOPSIS
    Function: Remove-AzureDevOpsWorkItemTags
    Author: @JamesDBartlett3@techhub.social (James D. Bartlett III)

  .DESCRIPTION
    This script removes one or more tags from a project in Azure DevOps.

  .PARAMETER OrganizationName
    The name of the Azure DevOps organization.

  .PARAMETER ProjectName
    The name of the Azure DevOps project.
  
  .PARAMETER PersonalAccessToken
    The personal access token (PAT) to use for authentication.
    This token must have the following scopes:
      - Work items (Read, write, and manage)
  
  .PARAMETER TagIdOrName
    The ID or name of the tag to be removed.

  .PARAMETER ApiVersion
    The version of the Azure DevOps REST API to use.
    Default: 7.1-preview.1

  .EXAMPLE
    # Remove a single tag
    .\Remove-AzureDevOpsWorkItemTags.ps1 -OrganizationName "MyOrg" -ProjectName "MyProject" -PersonalAccessToken "MyPAT" -TagIdOrName "MyTag"

  .EXAMPLE
    # Remove multiple tags
    .\Remove-AzureDevOpsWorkItemTags.ps1 -OrganizationName "MyOrg" -ProjectName "MyProject" -PersonalAccessToken "MyPAT" -TagIdOrName "MyTag1", "MyTag2"

  .OUTPUTS
    None

  .NOTES
    
#>

Param(
  [Parameter(Mandatory=$true)]
    [string]$OrganizationName
  ,[Parameter(Mandatory=$true)]
    [string]$ProjectName
  ,[Parameter(Mandatory=$true)]
    [string]$PersonalAccessToken
  ,[Parameter(Mandatory=$true)]
    [string[]]$TagIdOrName
  ,[Parameter(Mandatory=$false)]
    [string]$ApiVersion = "7.1-preview.1"
)

# Create the Authorization header
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($PersonalAccessToken)"))

# Call the endpoint for each tag
foreach ($tag in $TagIdOrName) {

  # Define the URL to call the Tags - List endpoint
  $url = "https://dev.azure.com/$OrganizationName/$ProjectName/_apis/wit/tags/$($tag)?api-version=$ApiVersion"

  # Call the endpoint
  $response = Invoke-RestMethod -Uri $url -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Method DELETE

  # Output the response
  $response
}