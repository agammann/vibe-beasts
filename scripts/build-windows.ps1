param([string]$Compiler='clang++',[Parameter(Mandatory=$true)][string]$Raylib)
$ErrorActionPreference='Stop'
$Compiler=(Get-Command $Compiler -ErrorAction Stop).Source
$resourceCompiler=Join-Path (Split-Path $Compiler) 'windres.exe'
if (-not (Test-Path -LiteralPath $resourceCompiler)) {throw 'The Windows compiler must include windres.exe.'}
$Raylib=(Resolve-Path -LiteralPath $Raylib).Path
foreach ($name in @('include/raylib.h','lib/libraylib.a')) {if(-not(Test-Path -LiteralPath (Join-Path $Raylib $name))){throw "Missing raylib 5.5 file: $name"}}
$header=Get-Content -LiteralPath (Join-Path $Raylib 'include/raylib.h') -Raw
if($header -notmatch '#define RAYLIB_VERSION\s+"5\.5"'){throw 'This build requires raylib 5.5.'}
Push-Location (Join-Path $PSScriptRoot '..')
try {
    $build=Join-Path $PWD 'build'
    New-Item -ItemType Directory -Force $build | Out-Null
    $stage=Join-Path $build ('stage-'+[Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force $stage | Out-Null
    $flags=@('-std=c++17','-O2','-Wall','-Wextra','-Werror')
    foreach($test in @('core','save-file')){
        $inputs=if($test -eq 'core'){@('src/game.cpp','tests/core-tests.cpp')}else{@('src/save-file.cpp','tests/save-file-tests.cpp')}
        $testExe=Join-Path $stage ($test+'-tests.exe')
        & $Compiler @flags @inputs -static -o $testExe
        if($LASTEXITCODE -ne 0){throw "$test test compilation failed; previous build kept."}
        & $testExe
        if($LASTEXITCODE -ne 0){throw "$test tests failed; previous build kept."}
    }
    $windows=Join-Path $stage 'windows'
    New-Item -ItemType Directory -Path $windows | Out-Null
    $resource=Join-Path $stage 'version.o'
    & $resourceCompiler -I src -i src/version.rc -o $resource
    if($LASTEXITCODE -ne 0){throw 'Version resource compilation failed; previous build kept.'}
    $exe=Join-Path $windows 'VibeBeasts.exe'
    & $Compiler @flags src/game.cpp src/save-file.cpp src/desktop.cpp $resource "-I$Raylib/include" "$Raylib/lib/libraylib.a" -lopengl32 -lgdi32 -lwinmm -static -o $exe
    if($LASTEXITCODE -ne 0){throw 'Desktop build failed; previous build kept.'}
    Copy-Item -LiteralPath dist/assets -Destination $windows -Recurse
    Copy-Item -LiteralPath assets/RAYLIB-LICENSE.txt,dist/icon-192.png -Destination $windows
    Copy-Item -LiteralPath packaging/Play.cmd,packaging/Install.cmd,packaging/install.ps1,packaging/README.md,CREDITS.md,LICENSE -Destination $windows
    $versionHeader=Get-Content -LiteralPath src/version.h -Raw
    if($versionHeader -notmatch '#define VIBE_VERSION "([0-9]+\.[0-9]+\.[0-9]+)"'){throw 'Source has no stable version.'}
    $version=$Matches[1]
    $details=[Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
    if($details.FileVersion -ne $version -or $details.ProductVersion -ne $version){throw 'Executable version differs from source.'}
    $inputs=@{}
    Get-ChildItem -LiteralPath src -File | ForEach-Object {$inputs['src/'+$_.Name]=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
    $receipt=[ordered]@{version=$version;inputs=$inputs;executableSha256=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant();raylibVersion='5.5';raylibSha256=(Get-FileHash -LiteralPath (Join-Path $Raylib 'lib/libraylib.a') -Algorithm SHA256).Hash.ToLowerInvariant()}
    [IO.File]::WriteAllText((Join-Path $windows 'BUILD.json'),($receipt|ConvertTo-Json -Depth 4)+"`n",(New-Object Text.UTF8Encoding($false)))
    $final=Join-Path $build 'windows'
    $previous=Join-Path $build ('previous-'+[Guid]::NewGuid().ToString('N'))
    foreach($path in @($stage,$final,$previous)) {if(-not ([IO.Path]::GetFullPath($path).StartsWith([IO.Path]::GetFullPath($build)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase))){throw 'Build path escaped its output directory.'}}
    if(Test-Path -LiteralPath $final){Move-Item -LiteralPath $final -Destination $previous}
    try{Move-Item -LiteralPath $windows -Destination $final}catch{if(Test-Path -LiteralPath $previous){Move-Item -LiteralPath $previous -Destination $final};throw}
    foreach($test in @('core','save-file')){Copy-Item -LiteralPath (Join-Path $stage ($test+'-tests.exe')) -Destination $build -Force}
    Write-Output "Built Vibe Beasts $version in build/windows. Previous build kept at $previous when one existed."
}finally{Pop-Location}
