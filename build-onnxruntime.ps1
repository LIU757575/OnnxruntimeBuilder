<#
.SYNOPSIS
    Build ONNX Runtime for Windows with specified architecture, VS version, CRT linkage, and configuration.
.DESCRIPTION
    This script wraps the official ONNX Runtime build.py and CMake commands.
.PARAMETER VsArch
    Target architecture: x64, x86, arm64.
.PARAMETER VsVer
    Visual Studio toolset version: v143 for VS2022, v142 for VS2019, etc.
.PARAMETER VsCRT
    CRT linkage: mt (static) or md (dynamic).
.PARAMETER Config
    Build configuration: Debug or Release.
.EXAMPLE
    .\build-onnxruntime.ps1 -VsArch x64 -VsVer v143 -VsCRT mt -Config Release
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("x64", "x86", "arm64")]
    [string]$VsArch,

    [Parameter(Mandatory=$true)]
    [string]$VsVer,

    [Parameter(Mandatory=$true)]
    [ValidateSet("mt", "md")]
    [string]$VsCRT,

    [Parameter(Mandatory=$true)]
    [ValidateSet("Debug", "Release")]
    [string]$Config
)

$ErrorActionPreference = "Stop"

# Determine build directory name
$buildDir = "build-$VsArch-$VsVer-$VsCRT"
Write-Host "Build directory: $buildDir"
Write-Host "Configuration: $Config"

# Determine MSVC static runtime flag
$staticCrtFlag = if ($VsCRT -eq "mt") { "--enable_msvc_static_runtime" } else { "" }

# Determine machine flag for build.py
$machineFlag = if ($VsArch -eq "x86") { "--x86" } else { "--build_java" }  # '--build_java' is just a placeholder for non-x86 to avoid x86-only restriction

# Determine CMake generator based on VS version
$cmakeGenerator = if ($VsVer -eq "v143") { "Visual Studio 17 2022" } else { "Visual Studio 16 2019" }

# Base build.py command
$buildPyArgs = @(
    "tools/ci_build/build.py",
    "--build_dir", $buildDir,
    "--config", $Config,
    "--parallel",
    "--skip_tests",
    "--build_shared_lib",
    $machineFlag,
    "--cmake_generator", "`"$cmakeGenerator`"",
    "--cmake_extra_defines", "CMAKE_INSTALL_PREFIX=./install", "onnxruntime_BUILD_UNIT_TESTS=OFF"
)

if ($staticCrtFlag) {
    $buildPyArgs += $staticCrtFlag
}

Write-Host "Executing: python $($buildPyArgs -join ' ')"
$buildPyCommand = "python " + ($buildPyArgs -join ' ')
Invoke-Expression $buildPyCommand
if ($LASTEXITCODE -ne 0) { throw "build.py failed" }

# Change to build directory and run CMake build
Push-Location "$buildDir/$Config"
try {
    Write-Host "Running cmake --build . --config $Config -j $env:NUMBER_OF_PROCESSORS"
    cmake --build . --config $Config -j $env:NUMBER_OF_PROCESSORS
    if ($LASTEXITCODE -ne 0) { throw "CMake build failed" }

    # Run install
    cmake --build . --config $Config --target install
    if ($LASTEXITCODE -ne 0) { throw "CMake install failed" }

    # Collect static libraries (simplified version, adjust as needed)
    if (Test-Path "install") {
        # Copy headers
        New-Item -ItemType Directory -Force -Path "install-static/include" | Out-Null
        Copy-Item -Recurse -Force "install/include/*" "install-static/include/"
        
        # Collect .lib files for static linking
        $libFiles = Get-ChildItem -Path "onnxruntime.dir/$Config" -Filter "*.lib" -Recurse | Where-Object { $_.FullName -notmatch "onnxruntime\.lib" }
        New-Item -ItemType Directory -Force -Path "install-static/lib" | Out-Null
        foreach ($lib in $libFiles) {
            Copy-Item $lib.FullName "install-static/lib/"
        }
        # Also copy onnxruntime.lib (the main import lib) to static folder for convenience
        if (Test-Path "$Config/onnxruntime.lib") {
            Copy-Item "$Config/onnxruntime.lib" "install-static/lib/"
        }
    }
}
finally {
    Pop-Location
}

Write-Host "Build completed successfully."
