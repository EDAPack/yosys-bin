#Requires -Version 5.1
# Build script for yosys-bin on Windows using MSVC (via vcxsrc / MSBuild).
#
# Pre-conditions:
#   - yosys-win32-vcxsrc.zip present in $PWD (from the vcxsrc CI artifact)
#   - $env:yosys_version set to the release version string
#
# Output:
#   release/yosys-bin-windows-x64-<version>.zip
$ErrorActionPreference = "Stop"

$rootDir    = $PWD.Path
$yosysVer   = if ($env:yosys_version) { $env:yosys_version } else { "1.0.0" }
$releaseDir = "$rootDir\release\yosys-$yosysVer"
$rlsPlat    = "windows-x64"

Write-Host "=== Preparing release directory ==="
foreach ($sub in @("bin", "share\yosys")) {
    New-Item -ItemType Directory -Force -Path "$releaseDir\$sub" | Out-Null
}

# ── Extract vcxsrc ────────────────────────────────────────────────────────────
Write-Host "=== Extracting vcxsrc ==="
Expand-Archive -LiteralPath "yosys-win32-vcxsrc.zip" -DestinationPath "$rootDir" -Force

$vcxsrcRoot = "$rootDir\yosys-win32-vcxsrc"

# Locate the generated vcxproj (create_vcxsrc.sh puts it under YosysVS/)
$vcxprojItem = Get-ChildItem -Path $vcxsrcRoot -Filter "YosysVS.vcxproj" -Recurse `
    | Select-Object -First 1
if (-not $vcxprojItem) {
    Write-Host "Archive contents:"; Get-ChildItem -Path $vcxsrcRoot -Recurse
    throw "YosysVS.vcxproj not found after extraction"
}
Write-Host "  vcxproj: $($vcxprojItem.FullName)"

# ── Patch vcxproj to add Release|x64 configuration ───────────────────────────
# The YosysVS template only ships Release|Win32; we duplicate it as Release|x64
# and set PlatformToolset to v143 (VS 2022) so msbuild can produce a 64-bit build.
Write-Host "=== Patching vcxproj for x64 ==="

[xml]$vcx = Get-Content $vcxprojItem.FullName
$ns = "http://schemas.microsoft.com/developer/msbuild/2003"

# Helper: clone an XML element and update its Condition attribute
function Clone-WithCondition([System.Xml.XmlElement]$node, [string]$condition) {
    $clone = $node.CloneNode($true)
    $clone.SetAttribute("Condition", $condition)
    return $clone
}

$x64Cond = "'`$(Configuration)|`$(Platform)'=='Release|x64'"
$win32Cond = "'`$(Configuration)|`$(Platform)'=='Release|Win32'"

# 1. Add <ProjectConfiguration Include="Release|x64"> to the ItemGroup
$cfgGroup = $vcx.Project.ItemGroup | Where-Object { $_.Label -eq "ProjectConfigurations" }
$x64CfgNode = $vcx.CreateElement("ProjectConfiguration", $ns)
$x64CfgNode.SetAttribute("Include", "Release|x64")
$cfgNode = $vcx.CreateElement("Configuration", $ns); $cfgNode.InnerText = "Release"
$platNode = $vcx.CreateElement("Platform", $ns);     $platNode.InnerText = "x64"
$x64CfgNode.AppendChild($cfgNode) | Out-Null
$x64CfgNode.AppendChild($platNode) | Out-Null
$cfgGroup.AppendChild($x64CfgNode) | Out-Null

# 2. Clone the Release|Win32 Configuration PropertyGroup as Release|x64
$srcPropGroup = $vcx.Project.PropertyGroup | Where-Object {
    $_.Condition -eq $win32Cond -and $_.Label -eq "Configuration"
}
if ($srcPropGroup) {
    $cloned = Clone-WithCondition $srcPropGroup $x64Cond
    $cloned.PlatformToolset = "v143"  # VS 2022 toolset
    $srcPropGroup.ParentNode.InsertAfter($cloned, $srcPropGroup) | Out-Null
}

# 3. Clone the Release|Win32 non-labelled PropertyGroup (LinkIncremental etc.)
$srcPropGroup2 = $vcx.Project.PropertyGroup | Where-Object {
    $_.Condition -eq $win32Cond -and (-not $_.Label)
}
if ($srcPropGroup2) {
    $cloned2 = Clone-WithCondition $srcPropGroup2 $x64Cond
    $srcPropGroup2.ParentNode.InsertAfter($cloned2, $srcPropGroup2) | Out-Null
}

# 4. Clone the Release|Win32 ItemDefinitionGroup (compiler/linker settings)
$srcIDG = $vcx.Project.ItemDefinitionGroup | Where-Object {
    $_.Condition -eq $win32Cond
}
if ($srcIDG) {
    $clonedIDG = Clone-WithCondition $srcIDG $x64Cond
    $srcIDG.ParentNode.InsertAfter($clonedIDG, $srcIDG) | Out-Null
}

$vcx.Save($vcxprojItem.FullName)
Write-Host "  Patched: Release|x64 config added with PlatformToolset=v143"

# ── Build yosys with MSBuild ──────────────────────────────────────────────────
# Build the vcxproj directly (not through the sln) so we can specify x64
# without needing to patch the sln's platform list.
Write-Host "=== Building yosys (Release|x64, MSVC v143) ==="
& msbuild $vcxprojItem.FullName /p:Configuration=Release /p:Platform=x64 /m /nologo
if ($LASTEXITCODE -ne 0) { throw "MSBuild failed ($LASTEXITCODE)" }

# ── Install yosys binaries ────────────────────────────────────────────────────
Write-Host "=== Installing yosys binaries ==="
$exes = Get-ChildItem -Path $vcxprojItem.DirectoryName -Filter "*.exe" -Recurse
if (-not $exes) {
    Write-Host "No .exe found; full tree:"; Get-ChildItem $vcxsrcRoot -Recurse
    throw "No executables after MSBuild"
}
foreach ($exe in $exes) {
    Copy-Item $exe.FullName "$releaseDir\bin\"
    Write-Host "  Installed bin\$($exe.Name)"
}

# Copy the tech-library share/ from the vcxsrc archive
$vcxShare = "$vcxsrcRoot\share"
if (Test-Path $vcxShare) {
    Copy-Item "$vcxShare\*" -Destination "$releaseDir\share\yosys" -Recurse -Force
    Write-Host "  Installed share/yosys"
}

# ── sby (pure Python, no compilation) ────────────────────────────────────────
Write-Host "=== Installing sby ==="
git clone --depth=1 https://github.com/YosysHQ/sby "$rootDir\sby"
if ($LASTEXITCODE -ne 0) { throw "git clone sby failed" }
$sbySrc = "$rootDir\sby"
foreach ($f in @("sbyw","sby")) {
    if (Test-Path "$sbySrc\$f") {
        Copy-Item "$sbySrc\$f" "$releaseDir\bin\sby"
        Write-Host "  Installed bin\sby"
        break
    }
}
if (Test-Path "$sbySrc\share") {
    Copy-Item "$sbySrc\share\*" "$releaseDir\share\yosys" -Recurse -Force -ErrorAction SilentlyContinue
}

# ── mcy (pure Python) ────────────────────────────────────────────────────────
Write-Host "=== Installing mcy ==="
git clone --depth=1 https://github.com/YosysHQ/mcy "$rootDir\mcy"
if ($LASTEXITCODE -ne 0) { throw "git clone mcy failed" }
$mcySrc = "$rootDir\mcy"
foreach ($f in @("mcy.py","mcy")) {
    if (Test-Path "$mcySrc\$f") { Copy-Item "$mcySrc\$f" "$releaseDir\bin\mcy"; break }
}
foreach ($f in @("mcy-dash.py","mcy-dash")) {
    if (Test-Path "$mcySrc\$f") { Copy-Item "$mcySrc\$f" "$releaseDir\bin\mcy-dash"; break }
}
New-Item -ItemType Directory -Force -Path "$releaseDir\share\mcy" | Out-Null
foreach ($sub in @("dash","scripts")) {
    if (Test-Path "$mcySrc\$sub") {
        Copy-Item "$mcySrc\$sub" -Destination "$releaseDir\share\mcy\$sub" -Recurse
    }
}

# ── eqy (Python launcher only; plugin .so compilation is skipped on Windows) ──
Write-Host "=== Installing eqy ==="
git clone --depth=1 https://github.com/YosysHQ/eqy "$rootDir\eqy"
if ($LASTEXITCODE -ne 0) { throw "git clone eqy failed" }
$eqySrc = "$rootDir\eqy"
foreach ($f in @("eqy","eqy.py")) {
    if (Test-Path "$eqySrc\$f") { Copy-Item "$eqySrc\$f" "$releaseDir\bin\eqy"; break }
}

# ── Static files ──────────────────────────────────────────────────────────────
foreach ($f in @("LICENSE","ivpm.yaml")) {
    if (Test-Path "$rootDir\$f") { Copy-Item "$rootDir\$f" "$releaseDir\" }
}

# ── Package ───────────────────────────────────────────────────────────────────
Write-Host "=== Packaging $rlsPlat release ==="
New-Item -ItemType Directory -Force -Path "$rootDir\release" | Out-Null
$zipPath = "$rootDir\release\yosys-bin-$rlsPlat-$yosysVer.zip"
Compress-Archive -Path "$releaseDir" -DestinationPath $zipPath -Force
Write-Host "Created: $zipPath"
