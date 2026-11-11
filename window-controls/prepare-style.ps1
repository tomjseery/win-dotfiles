#Requires -Version 5.1
# libmsstyle targets .NET Framework; run this helper with Windows PowerShell.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BaseStyle,
    [Parameter(Mandatory)][string]$OutputStyle,
    [Parameter(Mandatory)][string]$Editor,
    [Parameter(Mandatory)][string]$ThemeRoot
)
$ErrorActionPreference = 'Stop'
$settings = Get-Content -LiteralPath (Join-Path $ThemeRoot 'settings.json') -Raw | ConvertFrom-Json
function Assert-Hash([string]$Path, [string]$Expected) {
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $Expected) {
        throw "Fingerprint mismatch: $Path"
    }
}
Assert-Hash $BaseStyle $settings.base_sha256
Assert-Hash $Editor $settings.editor_exe_sha256
if ([IO.Path]::GetFullPath($BaseStyle) -eq [IO.Path]::GetFullPath($OutputStyle)) {
    throw 'Output must be a separate visual style.'
}
if (Test-Path -LiteralPath $OutputStyle) { throw 'Refusing to overwrite an existing style.' }
[Reflection.Assembly]::LoadFrom($Editor) | Out-Null

function Get-Properties($Style) {
    $rows = foreach ($class in $Style.Classes.Values) {
        foreach ($part in $class.Parts.Values) {
            foreach ($state in $part.States.Values) {
                foreach ($property in $state.Properties) {
                    '{0}|{1}|{2}|{3}|{4}|{5}' -f $class.ClassId, $part.PartId, $state.StateId,
                        $property.Header.nameID, $property.Header.typeID, $property.GetValueAsString()
                }
            }
        }
    }
    return ($rows | Sort-Object) -join "`n"
}

function Get-Images($Style) {
    $result = @{}
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        foreach ($class in $Style.Classes.Values) {
            foreach ($part in $class.Parts.Values) {
                foreach ($state in $part.States.Values) {
                    foreach ($property in $state.Properties) {
                        if ($property.Header.typeID -notin @(206, 213)) { continue }
                        $resource = $Style.GetResourceFromProperty($property)
                        if ($null -eq $resource -or $null -eq $resource.Data) { continue }
                        $key = '{0}/{1}' -f $resource.Type, $resource.ResourceId
                        $result[$key] = [BitConverter]::ToString($sha.ComputeHash($resource.Data)).Replace('-', '')
                    }
                }
            }
        }
    } finally { $sha.Dispose() }
    return $result
}

function Get-Strings($Style) {
    $rows = foreach ($key in ($Style.PreferredStringTable.Keys | Sort-Object)) {
        '{0}|{1}' -f $key, $Style.PreferredStringTable[$key]
    }
    return $rows -join "`n"
}

$original = New-Object libmsstyle.VisualStyle
$prepared = New-Object libmsstyle.VisualStyle
try {
    $original.Load($BaseStyle)
    $class = $original.Classes.Values | Where-Object ClassName -eq 'DWMWindow'
    $atlasProperty = @($class.Parts[0].States[0].Properties | Where-Object { $_.Header.typeID -eq 213 })
    if ($atlasProperty.Count -ne 1) { throw 'Expected exactly one DWM caption atlas.' }
    $atlas = $original.GetResourceFromProperty($atlasProperty[0])
    if ($atlas.ResourceId -ne $settings.atlas_resource) { throw 'Unexpected caption atlas resource.' }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $atlasHash = [BitConverter]::ToString($sha.ComputeHash($atlas.Data)).Replace('-', '') }
    finally { $sha.Dispose() }
    if ($atlasHash -ne $settings.source_atlas_sha256) { throw 'Unexpected original caption artwork.' }
    $beforeProperties = Get-Properties $original
    $beforeStrings = Get-Strings $original
    $beforeImages = Get-Images $original
    $replacement = Join-Path $ThemeRoot 'caption-atlas.png'
    Assert-Hash $replacement $settings.output_atlas_sha256
    $original.QueueResourceUpdate($settings.atlas_resource, [libmsstyle.StyleResourceType]::Atlas, $replacement)
    $original.Save($OutputStyle, $true)
    $prepared.Load($OutputStyle)
    if ((Get-Properties $prepared) -cne $beforeProperties) { throw 'Visual style properties changed unexpectedly.' }
    if ((Get-Strings $prepared) -cne $beforeStrings) { throw 'Effective theme strings or fonts changed unexpectedly.' }
    $afterImages = Get-Images $prepared
    if ($beforeImages.Count -ne $afterImages.Count) { throw 'Visual style resource count changed.' }
    $atlasKey = '{0}/{1}' -f $atlas.Type, $atlas.ResourceId
    foreach ($key in $beforeImages.Keys) {
        $expected = if ($key -eq $atlasKey) { $settings.output_atlas_sha256 } else { $beforeImages[$key] }
        if ($afterImages[$key] -ne $expected) { throw "Resource validation failed: $key" }
    }
    $report = [ordered]@{
        base = $BaseStyle; output = $OutputStyle
        base_sha256 = (Get-FileHash -LiteralPath $BaseStyle).Hash.ToLowerInvariant()
        output_sha256 = (Get-FileHash -LiteralPath $OutputStyle).Hash.ToLowerInvariant()
        properties_preserved = $true; strings_preserved = $true; image_resources_checked = $beforeImages.Count
        atlas_resource = $settings.atlas_resource
    }
    $report | ConvertTo-Json | Set-Content -LiteralPath ($OutputStyle + '.validation.json') -Encoding UTF8
    Write-Output 'Prepared and validated caption-only visual style.'
} finally {
    $original.Dispose()
    $prepared.Dispose()
}
