#*****************************************************************************#
#    Copyright (C) 2009 Aali132                                               #
#    Copyright (C) 2018 quantumpencil                                         #
#    Copyright (C) 2018 Maxime Bacoux                                         #
#    Copyright (C) 2020 myst6re                                               #
#    Copyright (C) 2020 Chris Rizzitello                                      #
#    Copyright (C) 2020 John Pritchard                                        #
#    Copyright (C) 2026 Julian Xhokaxhiu                                      #
#                                                                             #
#    This file is part of FFNx                                                #
#                                                                             #
#    FFNx is free software: you can redistribute it and\or modify             #
#    it under the terms of the GNU General Public License as published by     #
#    the Free Software Foundation, either version 3 of the License            #
#                                                                             #
#    FFNx is distributed in the hope that it will be useful,                  #
#    but WITHOUT ANY WARRANTY; without even the implied warranty of           #
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            #
#    GNU General Public License for more details.                             #
#*****************************************************************************#

Set-StrictMode -Version Latest

# === 无论任何分支、任何标签触发，一律无条件强行判定为金丝雀（Canary）构建 ===
$env:_IS_BUILD_CANARY = "true"     # 强行开闸：确保 100% 走 Canary 发布路线，避开无 Tag 报错！
$env:_IS_GITHUB_RELEASE = "true"   # 强行开闸：激活发布流程

# 只保留基础的版本号规整，防止发布时因无 tag 报错
if ($env:_BUILD_BRANCH -like "refs/tags/*")
{
  $env:_CHANGELOG_VERSION = $env:_BUILD_VERSION.Substring(0,$env:_BUILD_VERSION.LastIndexOf('.')).Replace('.','')
  $env:_BUILD_VERSION = $env:_BUILD_VERSION.Substring(0,$env:_BUILD_VERSION.LastIndexOf('.')) + ".0"
}
$env:_RELEASE_VERSION = "v${env:_BUILD_VERSION}"

$vcpkgRoot = ".\vcpkg"
$vcpkgBaseline = [string](jq --arg baseline "builtin-baseline" -r '.[$baseline]' vcpkg.json)
$vcpkgOriginUrl = &"git" -C $vcpkgRoot remote get-url origin
$vcpkgTagName = &"git" -C $vcpkgRoot describe --exact-match --tags

$releasePath = [string](jq -r '.configurePresets[0].binaryDir' CMakePresets.json).Replace('${sourceDir}/', '')

Write-Output "--------------------------------------------------"
Write-Output "BUILD CONFIGURATION: $env:_RELEASE_CONFIGURATION"
Write-Output "RELEASE VERSION: $env:_RELEASE_VERSION"
Write-Output "VCPKG ORIGIN: $vcpkgOriginUrl"
Write-Output "VCPKG TAG: $vcpkgTagName"
Write-Output "VCPKG BASELINE: $vcpkgBaseline"
Write-Output "--------------------------------------------------"

Write-Output "_BUILD_VERSION=${env:_BUILD_VERSION}" >> ${env:GITHUB_ENV}
Write-Output "_RELEASE_VERSION=${env:_RELEASE_VERSION}" >> ${env:GITHUB_ENV}
Write-Output "_IS_BUILD_CANARY=${env:_IS_BUILD_CANARY}" >> ${env:GITHUB_ENV}
Write-Output "_IS_GITHUB_RELEASE=${env:_IS_GITHUB_RELEASE}" >> ${env:GITHUB_ENV}
Write-Output "_CHANGELOG_VERSION=${env:_CHANGELOG_VERSION}" >> ${env:GITHUB_ENV}

# Load vcvarsall environment for x86
$vcvarspath = &"${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -prerelease -latest -property InstallationPath
cmd.exe /c "call `"$vcvarspath\VC\Auxiliary\Build\vcvarsall.bat`" x86 && set > %temp%\vcvars.txt"
Get-Content "$env:temp\vcvars.txt" | Foreach-Object {
  if ($_ -match "^(.*?)=(.*)$") {
    Set-Content "env:\$($matches[1])" $matches[2]
  }
}

# 强制锁死 VCPKG_ROOT，确保所有编译出的 Pkg 实体都能被系统抓取到 ===
$env:VCPKG_ROOT = "$(Get-Location)\vcpkg"

# === 安全改造：完全移除原库主遗留的私有 NuGet 越权登录鉴权代码 ===
Write-Output "Skipping external NuGet registry. Relying on GHA Native Caching instead."
# =====================================================================

# Vcpkg setup
cmd.exe /c "call $vcpkgRoot\bootstrap-vcpkg.bat"

vcpkg integrate install

# Start the build
cmake --preset "${env:_RELEASE_CONFIGURATION}" -D_DLL_VERSION="$env:_BUILD_VERSION"
cmake --build --preset "${env:_RELEASE_CONFIGURATION}"

# Start the packaging
mkdir .dist\pkg\FF7_1998 | Out-Null
mkdir .dist\pkg\FF8_2000 | Out-Null
mkdir .dist\pkg\FFNx_Steam | Out-Null
Copy-Item -R "$releasePath\bin\*" .dist\pkg\FF7_1998
Copy-Item -R "$releasePath\bin\*" .dist\pkg\FF8_2000
Copy-Item -R "$releasePath\bin\*" .dist\pkg\FFNx_Steam
Remove-Item .dist\pkg\FF7_1998\FF8.reg
Remove-Item .dist\pkg\FF8_2000\FF7.reg
Remove-Item .dist\pkg\FFNx_Steam\FF7.reg
Remove-Item .dist\pkg\FFNx_Steam\FF8.reg
Remove-Item .dist\pkg\FF7_1998\AF4DN.P
Remove-Item .dist\pkg\FF8_2000\AF4DN.P
Move-Item .dist\pkg\FF7_1998\FF7.reg .dist\pkg\FF7_1998\FFNx.reg
Move-Item .dist\pkg\FF8_2000\FF8.reg .dist\pkg\FF8_2000\FFNx.reg
Move-Item .dist\pkg\FF8_2000\FFNx.dll .dist\pkg\FF8_2000\eax.dll
Move-Item .dist\pkg\FFNx_Steam\FFNx.dll .dist\pkg\FFNx_Steam\AF3DN.P

7z a ".\.dist\${env:_RELEASE_NAME}-FF7_1998-${env:_RELEASE_VERSION}.zip" ".\.dist\pkg\FF7_1998\*"
7z a ".\.dist\${env:_RELEASE_NAME}-FF8_2000-${env:_RELEASE_VERSION}.zip" ".\.dist\pkg\FF8_2000\*"
7z a ".\.dist\${env:_RELEASE_NAME}-Steam-${env:_RELEASE_VERSION}.zip" ".\.dist\pkg\FFNx_Steam\*"

Remove-Item -Recurse -Force .dist\pkg
