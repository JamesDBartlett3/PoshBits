<#
.SYNOPSIS
	Function: Rename-AzureDevOpsWorkItemTag
	Author: @JamesDBartlett3@techhub.social (James D. Bartlett III)

.DESCRIPTION
	This script renames a tag in a project in Azure DevOps.

.PARAMETER OrganizationName
	The name of the Azure DevOps organization.

.PARAMETER ProjectName
	The name of the Azure DevOps project.

.PARAMETER PersonalAccessToken
	The personal access token (PAT) to use for authentication.
	This token must have the following scopes:
		- Work items (Read, write, and manage)

.PARAMETER TagId
	The ID of the tag to be renamed.

.PARAMETER NewTagName
	The new name for the tag.

.PARAMETER ApiVersion
	The version of the Azure DevOps REST API to use.
	Default: 7.1-preview.1
#>

Param(
  [Parameter(Mandatory)]
    [string]$OrganizationName
  ,[Parameter(Mandatory)]
    [string]$ProjectName
  ,[Parameter(Mandatory)]
    [string]$PersonalAccessToken
  ,[Parameter(Mandatory)]
    [string]$TagId
	,[Parameter(Mandatory)]
		[string]$NewTagName
  ,[Parameter(Mandatory=$false)]
    [string]$ApiVersion = "7.1-preview.1"
)

begin {

	# Create the Authorization header
	$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($PersonalAccessToken)"))

}

process {

	# Define the URL to call the Tags - Update endpoint
	$uri = "https://dev.azure.com/$OrganizationName/$ProjectName/_apis/wit/tags/$($TagId)?api-version=$($ApiVersion)"

	# Define the body of the request
	$body = @{
		"id" = "$TagId"
		"name" = "$NewTagName"
		"url" = "$uri"
	} | ConvertTo-Json

	# # Call the endpoint
	$response = Invoke-RestMethod -Uri $uri -Headers @{
		Authorization = ("Basic {0}" -f $base64AuthInfo)
	} -Method PATCH -Body $body -ContentType "application/json"

	# Output the response
	$response

}