param(
    [Parameter(Mandatory)]
    [string]$SearchTerm,

    [string]$Path = $PWD.Path,  # Default to the current directory if not specified

    # Switch to disable recursive search. By default the script searches all subfolders.
    [switch]$NoRecurse,

    [string[]]$FileTypes = @("*.xlsx", "*.xls", "*.xlsm"),

    # Include hidden/system folders (e.g. Recycle Bin, System Volume Information)
    [switch]$IncludeHidden
)

# Search inside Excel files by contents
# Prefers Excel COM object; falls back to ImportExcel module if Excel is not installed

# Build a hashtable of parameters for Get-ChildItem so we can conditionally add -Recurse
# (splatting: @gciParams passes each key-value pair as a named parameter)
$gciParams = @{
    Path        = $Path
    Include     = $FileTypes
    ErrorAction = 'SilentlyContinue'
}
if (-not $NoRecurse) { $gciParams['Recurse'] = $true }
# -Force makes Get-ChildItem include hidden and system files/folders
if ($IncludeHidden) { $gciParams['Force'] = $true }

# --- Try Excel COM approach first ---
# The COM object launches a hidden Excel process in the background.
# This requires Excel to be installed on the machine.
$useExcelCom = $false
try {
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false        # Don't show the Excel window
    $excel.DisplayAlerts = $false  # Suppress prompts (e.g. "enable macros?")
    $useExcelCom = $true
} catch {
    # COM creation fails if Excel isn't installed — fall back to the ImportExcel module,
    # an open-source PowerShell module that reads Excel files without needing Excel installed.
    # Note: ImportExcel supports .xlsx/.xlsm but NOT legacy .xls files.
    Write-Host "Excel COM not available. Falling back to ImportExcel module..."
    if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
        Write-Host "Installing ImportExcel module (CurrentUser scope)..."
        Install-Module -Name ImportExcel -Scope CurrentUser -Force
    }
    Import-Module ImportExcel
}

# --- Search files ---
Get-ChildItem @gciParams | ForEach-Object {
    $file = $_.FullName
    try {
        if ($useExcelCom) {
            # Open workbook: arg2 0 = no update links, arg3 $true = read-only
            $wb = $excel.Workbooks.Open($file, 0, $true)
            foreach ($ws in $wb.Worksheets) {
                # .Find() parameters: What, After, LookIn, LookAt
                # The 4th argument (LookAt) = 2 means xlPart (substring match),
                # vs. 1 = xlWhole (exact cell match). [Missing] skips optional params.
                $found = $ws.Cells.Find($SearchTerm, [System.Reflection.Missing]::Value, [System.Reflection.Missing]::Value, 2)
                if ($found) {
                    Write-Host "FOUND in: $file | Sheet: $($ws.Name)"
                }
            }
            $wb.Close($false)  # $false = don't save changes
        } else {
            $sheets = Get-ExcelSheetInfo -Path $file
            foreach ($sheet in $sheets) {
                # -NoHeader treats every row the same (no column-name assumptions)
                $data = Import-Excel -Path $file -WorksheetName $sheet.Name -NoHeader -ErrorAction SilentlyContinue
                foreach ($row in $data) {
                    # Each row is a PSObject whose properties are the cell values.
                    # Check every cell value in the row for a substring match.
                    $match = $row.PSObject.Properties.Value | Where-Object { $_ -like "*$SearchTerm*" }
                    if ($match) {
                        Write-Host "FOUND in: $file | Sheet: $($sheet.Name)"
                        break  # Stop checking rows once we have a hit on this sheet
                    }
                }
            }
        }
    } catch {
        Write-Host "Could not open: $file"
    }
}

# --- Cleanup ---
# Release the COM object to close the background Excel process and free memory.
# Without this, an orphaned EXCEL.EXE process would remain running.
if ($useExcelCom) {
    $excel.Quit()
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
}
