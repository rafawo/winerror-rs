<#
    This powershell module contains utilities to parse a file that can compile
    using microsoft's mc.exe (https://docs.microsoft.com/en-us/windows/win32/wes/message-compiler--mc-exe-).
#>

class Severity
{
    [string] $Name
    [int32] $Value

    Severity([string] $Raw)
    {
        $parts = $Raw -split '='

        if ($parts.Count -gt 2)
        {
            throw "Could not parse $Raw as Severity"
        }

        $this.Name = $parts[0].Trim()
        $this.Value = [int32]($parts[1].Trim())
    }
}

class Facility
{
    [string] $Name
    [int32] $Value
    [string] $SymbolicName

    Facility([string] $Raw)
    {
        $parts = $Raw -split '='

        if ($parts.Count -gt 2)
        {
            throw "Could not parse $Raw as Facility"
        }

        $this.Name = $parts[0].Trim()

        $parts = $parts[1] -split ':'

        if ($parts.Count -gt 2)
        {
            throw "Could not parse $Raw as Facility"
        }

        $this.Value = [int32]($parts[0].Trim())
        $this.SymbolicName = $parts[1] -replace '\s+',''
    }
}

class ErrorCode
{
    [int32] $Id
    [int32] $Severity
    [int32] $Facility
    [string] $SymbolicName
    [string[]] $Message

    ErrorCode([int32] $Id, [int32] $Severity, [int32] $Facility, [string] $SymbolicName)
    {
        if (($Id -band 0xFFFF0000) -gt 0)
        {
            throw "Invalid ErrorCode ID $Id"
        }

        if (($Severity -band 0xFFFFFFFFC) -gt 0)
        {
            throw "Invalid ErrorCode Severity $Severity"
        }

        if (($Facility -band 0xFFFFF000) -gt 0)
        {
            throw "Invalid ErrorCode Facility $Facility"
        }

        $this.Id = $Id
        $this.Severity = $Severity
        $this.Facility = $Facility
        $this.SymbolicName = $SymbolicName
    }

    [void] SetMessage([string[]] $Message)
    {
        $this.Message = $Message
    }

    [int32] Value()
    {
        return ($this.Severity -shl 30) -bor ($this.Facility -shl 16) -bor $this.Id
    }
}

class McData
{
    [System.Collections.Generic.Dictionary[string, Severity]] $Severities
    [System.Collections.Generic.Dictionary[string, Facility]] $Facilities
    [System.Collections.Generic.List[ErrorCode]] $ErrorCodes

    hidden [System.Collections.Generic.List[string]] $OrderedListOfSeverities
    hidden [System.Collections.Generic.List[string]] $OrderedListOfFacilities

    McData()
    {
        $this.Severities = [System.Collections.Generic.Dictionary[string, Severity]]::new()
        $this.AddSeverity("Success=0x0")
        $this.AddSeverity("Informational=0x1")
        $this.AddSeverity("Warning=0x2")
        $this.AddSeverity("Error=0x3")
        $this.OrderedListOfSeverities = [System.Collections.Generic.List[string]]::new()

        $this.Facilities = [System.Collections.Generic.Dictionary[string, Facility]]::new()
        $this.AddFacility("System=0x0FF")
        $this.AddFacility("Application=0xFFF")
        $this.OrderedListOfFacilities = [System.Collections.Generic.List[string]]::new()

        $this.ErrorCodes = [System.Collections.Generic.List[ErrorCode]]::new()
    }

    [void] Clear()
    {
        $this.Severities.Clear()
        $this.Facilities.Clear()
        $this.ErrorCodes.Clear()
    }

    [void] AddSeverity([string] $Text)
    {
        if ([string]::IsNullOrEmpty($Text))
        {
            return
        }

        $severity = [Severity]::new($Text)

        if ($this.Severities.ContainsKey($severity.Name))
        {
            $this.Severities[$severity.Name] = $severity
        }
        else
        {
            $this.Severities.Add($severity.Name, $severity)
        }

        if ($null -ne $this.OrderedListOfSeverities)
        {
            $this.OrderedListOfSeverities.Add($severity.Name)
        }
    }

    [void] AddFacility([string] $Text)
    {
        if ([string]::IsNullOrEmpty($Text))
        {
            return
        }

        $facility = [Facility]::new($Text)

        if ($this.Facilities.ContainsKey($facility.Name))
        {
            $this.Facilities[$facility.Name] = $facility
        }
        else
        {
            $this.Facilities.Add($facility.Name, $facility)
        }

        if ($null -ne $this.OrderedListOfFacilities)
        {
            $this.OrderedListOfFacilities.Add($facility.Name)
        }
    }

    [int32] DefaultSeverityValue()
    {
        if (($null -ne $this.OrderedListOfSeverities) -and ($this.OrderedListOfSeverities.Count -ge 1))
        {
            return $this.SeverityValue($this.OrderedListOfSeverities[0])
        }
        else
        {
            return $this.SeverityValue("Success")
        }
    }

    [int32] DefaultFacilityValue()
    {
        if (($null -ne $this.OrderedListOfFacilities) -and ($this.OrderedListOfFacilities.Count -ge 2))
        {
            return $this.FacilityValue($this.OrderedListOfFacilities[1])
        }
        else
        {
            return $this.FacilityValue("Application")
        }
    }

    [int32] SeverityValue([string] $Name)
    {
        return $this.Severities[$Name].Value
    }

    [int32] FacilityValue([string] $Name)
    {
        return $this.Facilities[$Name].Value
    }

    [ErrorCode] ErrorCode([string] $Name)
    {
        return $this.ErrorCodes | ? SymbolicName -eq $Name
    }
}

<#
.SYNOPSIS
    Converts the supplied .mc file to an in-memory representation of its contents.

.DESCRIPTION
    Converts the supplied .mc file to an in-memory representation of its contents.

.PARAMETER McFilePath
    Supplies the file path to a valid .mc file that can be built with mc.exe
#>
function ConvertTo-McData
{
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $McFilePath
    )

    $ErrorActionPreference = "Stop"

    if (!(Test-Path -Path $McFilePath))
    {
        throw "Invalid path $McFilePath!"
    }

    $content = Get-Content -Path $McFilePath

    function CleanupLine
    {
        param(
            [string] $String
        )

        return ($String -split ';')[0].Trim()
    }

    function SplitContentData
    {
        param(
            [string[]] $StringArray,
            [int32] $Index
        )

        $parts = [string]::Join(' ', ([string]::Join(' ', $StringArray) -replace '(\s+:\s+)|(\s+:)|(:\s+)',':' -split '=')).Trim() -split '\s+'
        if (($parts.Count -band 0x1) -eq 0x1)
        {
            throw "[Index: $Index] Expected pair number of parts for $($parts.Count): `"$parts`""
        }

        $i = 0
        [string[]] $contentData = @()
        while ($i -lt $parts.Count)
        {
            $contentData += "$($parts[$i++])=$($parts[$i++])"
        }

        return $contentData
    }

    $i = 0
    $data = [McData]::new()
    [string[]] $severityContent = @()
    [string[]] $facilityContent = @()

    # Parse severities
    while (($i -lt $content.Count) -and !($content[$i] -match '.*SeverityNames.*')) { $i++ }
    $severityContent += (CleanupLine ($content[$i++] -split '\(')[1])
    while (($i -lt $content.Count) -and !$content[$i].Contains(')')) { $severityContent += (CleanupLine $content[$i++]) }
    $severityContent += (CleanupLine ($content[$i++] -split '\)')[0])
    foreach ($item in (SplitContentData $severityContent $i))
    {
        $data.AddSeverity($item)
    }

    # Parse facilities
    while (($i -lt $content.Count) -and !($content[$i] -match '.*FacilityNames.*')) { $i++ }
    $facilityContent += (CleanupLine ($content[$i++] -split '\(')[1])
    while (($i -lt $content.Count) -and !$content[$i].Contains(')')) { $facilityContent += (CleanupLine $content[$i++]) }
    $facilityContent += (CleanupLine ($content[$i++] -split '\)')[0])
    foreach ($item in (SplitContentData $facilityContent $i))
    {
        $data.AddFacility($item)
    }

    [int32] $lastSeverityValue = $data.DefaultSeverityValue()
    [int32] $lastFacilityValue = $data.DefaultFacilityValue()
    [string] $lastUsedFacilityName = ""
    [int32] $lastUsedId = 0

    # Parse until the end of file all Error Codes
    while (($i -lt $content.Count))
    {
        # First lines of an error code contains id, name, severity and facility up to Language
        [string[]] $errorCodeContent = @()

        while (($i -lt $content.Count) -and !($content[$i] -match '.*Language.*'))
        {
            $errorCodeContent += CleanupLine $content[$i++]
        }

        if (($i -ge $content.Count))
        {
            break
        }

        $splittedLanguage = (CleanupLine $content[$i++]) -split 'English'
        $errorCodeContent += "$($splittedLanguage[0])English"
        [string] $errorCodeData = [string]::Join(' ', $errorCodeContent)

        if (($errorCodeData -match "\s*Severity\s*=\s*(?<severity>\S+)\s*"))
        {
            $severity = $matches.severity
        }
        else
        {
            $severity = $null
        }

        if (($errorCodeData -match "\s*Facility\s*=\s*(?<facility>\S+)\s*"))
        {
            $facility = $matches.facility
        }
        else
        {
            $facility = $null
        }

        if (!($errorCodeData -match "\s*SymbolicName\s*=\s*(?<symbolicname>\S+)\s*"))
        {
            # Skip error codes that did not specify a symbolic name
            while (($i -lt $content.Count) -and !((CleanupLine $content[$i]) -eq '.')) { $i++ }
            continue
        }
        $name = $matches.symbolicname

        if (!($errorCodeData -match "\s*MessageId\s*=\s*(?<id>\S+)?\s*")) { throw "Wrong error code metadata ($errorCodeData)" }
        $id = $matches.id

        if ([string]::IsNullOrEmpty($id) -or $id.StartsWith('+'))
        {
            if ($lastUsedFacilityName -ne $facility)
            {
                $lastUsedId = 0
                $lastUsedFacilityName = $facility
            }

            if ([string]::IsNullOrEmpty($id))
            {
                $id = $lastUsedId + 1
            }
            else
            {
                $id = $lastUsedId + [int32](($id -split '+')[1])
            }

            $lastUsedId = $id
        }

        $severity_value = $lastSeverityValue
        if (![string]::IsNullOrEmpty($severity))
        {
            $severity_value = $data.SeverityValue($severity)
            $lastSeverityValue = $severity_value
        }

        $facility_value = $lastFacilityValue
        if (![string]::IsNullOrEmpty($facility))
        {
            $facility_value = $data.FacilityValue($facility)
            $lastFacilityValue = $facility_value
        }

        $errorCode = [ErrorCode]::new($id, $severity_value, $facility_value, $name)

        $remainder = $splittedLanguage[1] -replace '^\s+',''
        [string[]] $message = if ([string]::IsNullOrEmpty($remainder)) { @() } else { $remainder }
        while (($i -lt $content.Count) -and !((CleanupLine $content[$i]) -eq '.')) { $message += $content[$i++] }

        $errorCode.SetMessage($message)
        $data.ErrorCodes.Add($errorCode)

        $i++
    }

    return $data
}

<#
.SYNOPSIS
    Generates rust code for the supplied MC data.

.DESCRIPTION
    Generates rust code for the supplied MC data.
    The generated rust is assumed to be a module, and as such creates a mod.rs file
    in the supplied directory.

.PARAMETER McData
    Supplies the in-memory representation of a .mc file, extracted from running ConvertTo-McData

.PARAMETER Path
    Supplies the parent path where the mod.rs file will be generated.
#>
function New-ModRs
{
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [McData] $McData,

        [ValidateNotNullOrEmpty()]
        [string] $Path = (Get-Location),

        [switch] $Force
    )

    $modrs = Join-Path -Path $Path -ChildPath "mod.rs"
    New-Item -ItemType File -Path $modrs -Force:$Force.IsPresent -ErrorAction Stop | Out-Null

    Add-Content -Path $modrs -Value "#[derive(Debug, Clone)]`n"
    Add-Content -Path $modrs -Value "pub enum Severity {"

    foreach ($severity in $McData.Severities.Values)
    {
        Add-Content -Path $modrs -Value "    $($severity.Name),"
    }

    Add-Content -Path $modrs -Value "}"
    Add-Content -Path $modrs -Value ""
    Add-Content -Path $modrs -Value "impl Into<i32> for Severity {"
    Add-Content -Path $modrs -Value "    fn into(self) -> i32 {"
    Add-Content -Path $modrs -Value "        match self {"

    foreach ($severity in $McData.Severities.Values)
    {
        Add-Content -Path $modrs -Value "            Severity::$($severity.Name) => 0x$('{0:X}' -f $severity.Value),"
    }

    Add-Content -Path $modrs -Value "        }"
    Add-Content -Path $modrs -Value "    }"
    Add-Content -Path $modrs -Value "}"

    Add-Content -Path $modrs -Value ""

    Add-Content -Path $modrs -Value "#[derive(Debug, Clone)]"
    Add-Content -Path $modrs -Value "pub enum Facility {"

    foreach ($facility in $McData.Facilities.Values)
    {
        Add-Content -Path $modrs -Value "    $($facility.Name),"
    }

    Add-Content -Path $modrs -Value "}"
    Add-Content -Path $modrs -Value ""
    Add-Content -Path $modrs -Value "impl Into<i32> for Facility {"
    Add-Content -Path $modrs -Value "    fn into(self) -> i32 {"
    Add-Content -Path $modrs -Value "        match self {"

    foreach ($facility in $McData.Facilities.Values)
    {
        Add-Content -Path $modrs -Value "            Facility::$($facility.Name) => 0x$('{0:X}' -f $facility.Value),"
    }

    Add-Content -Path $modrs -Value "        }"
    Add-Content -Path $modrs -Value "    }"
    Add-Content -Path $modrs -Value "}"
}

Export-ModuleMember *-*
