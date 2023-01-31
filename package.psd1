@{
    Root = 'c:\Users\James\GitHub\PoshBits\Start-TabbyHidden.ps1'
    OutputPath = 'c:\Users\James\GitHub\PoshBits\out'
    Package = @{
        Enabled = $true
        Obfuscate = $false
        HideConsoleWindow = $true
        DotNetVersion = 'v4.6.2'
        FileVersion = '1.0.0'
        FileDescription = ''
        ProductName = ''
        ProductVersion = ''
        Copyright = ''
        RequireElevation = $false
        ApplicationIconPath = ''
        PackageType = 'Console'
    }
    Bundle = @{
        Enabled = $true
        Modules = $false
        # IgnoredModules = @()
    }
}
        