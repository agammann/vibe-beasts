$ErrorActionPreference='Stop'
Set-Location (Split-Path $PSScriptRoot)
if(-not(Get-Command git -ErrorAction SilentlyContinue)){throw 'Packaging requires Git; playing and source builds do not.'}
if(git status --porcelain --untracked-files=normal){throw 'Package a clean committed source tree.'}
$commit=(git rev-parse HEAD).Trim();$tree=(git rev-parse 'HEAD^{tree}').Trim()
if($env:GITHUB_SHA -and $env:GITHUB_SHA -ne $commit){throw 'Workflow checkout differs from the release commit.'}
$header=Get-Content -LiteralPath src/version.h -Raw
if($header -notmatch '#define VIBE_VERSION "([0-9]+\.[0-9]+\.[0-9]+)"'){throw 'Missing stable version.'}
$version=$Matches[1]
& node scripts/web-receipt.mjs --verify
if($LASTEXITCODE -ne 0){throw 'Browser build receipt failed.'}
$windows=Join-Path $PWD 'build/windows'
$game=Join-Path $windows 'VibeBeasts.exe'
$native=Get-Content -LiteralPath (Join-Path $windows 'BUILD.json') -Raw | ConvertFrom-Json
if($native.version -ne $version -or $native.executableSha256 -ne (Get-FileHash -LiteralPath $game -Algorithm SHA256).Hash.ToLowerInvariant()){throw 'Native build receipt does not match the executable.'}
$inputs=@(Get-ChildItem -LiteralPath src -File)
if($inputs.Count -ne @($native.inputs.PSObject.Properties).Count){throw 'Native build input set changed.'}
foreach($inputFile in $inputs){if($native.inputs.('src/'+$inputFile.Name) -ne (Get-FileHash -LiteralPath $inputFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant()){throw "Native input changed: $($inputFile.Name). Rebuild."}}
$details=[Diagnostics.FileVersionInfo]::GetVersionInfo($game)
if($details.FileVersion -ne $version -or $details.ProductVersion -ne $version){throw 'Executable and source versions differ.'}
$directory=Join-Path $PWD 'release-artifacts'
New-Item -ItemType Directory -Force $directory | Out-Null
$archives=@("vibe-beasts_${version}_source.zip","vibe-beasts_${version}_browser.zip","vibe-beasts_${version}_windows-x64.zip")
foreach($name in @($archives+@($archives|ForEach-Object{$_+'.sha256'})+'SHA256SUMS')){if(Test-Path -LiteralPath (Join-Path $directory $name)){throw "Artifact exists: $name. Use a fresh checkout."}}
$sourceFiles=@(git ls-tree -r HEAD | ForEach-Object {if($_ -notmatch '^100644 blob ([0-9a-f]{40})\t(.+)$'){throw 'Only regular source files may be packaged.'};[ordered]@{path=$Matches[2];blob=$Matches[1]}})
$windowsFiles=@(Get-ChildItem -LiteralPath $windows -Recurse -File | ForEach-Object{[ordered]@{path=$_.FullName.Substring($windows.Length+1).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}})
$web=Get-Content -LiteralPath dist/BUILD.json -Raw | ConvertFrom-Json
$metadata=[ordered]@{name='vibe-beasts';version=$version;commit=$commit;tree=$tree;executableSha256=$native.executableSha256;webBuild=$web;sourceFiles=$sourceFiles;windowsFiles=$windowsFiles}
$json=($metadata|ConvertTo-Json -Depth 8)+"`n";$utf8=New-Object Text.UTF8Encoding($false)
$stage=Join-Path $PWD ('release-staging/'+[Guid]::NewGuid().ToString('N'))
$windowsRoot=Join-Path $stage "Vibe-Beasts-$version"
$browserRoot=Join-Path $stage "vibe-beasts-$version-browser"
New-Item -ItemType Directory -Force $windowsRoot,$browserRoot | Out-Null
Get-ChildItem -LiteralPath $windows | Copy-Item -Destination $windowsRoot -Recurse
Copy-Item -LiteralPath dist -Destination $browserRoot -Recurse
Copy-Item -LiteralPath scripts/serve.mjs -Destination $browserRoot
Copy-Item -LiteralPath CREDITS.md,LICENSE -Destination $browserRoot
$browserReadme="# Vibe Beasts $version browser edition`n`nRun ``node serve.mjs`` from this folder, then open http://localhost:4173. Node.js 22 or later is required for the local server. Keep the complete dist folder. For HTTPS hosting, upload dist/ and serve .wasm as application/wasm. Do not open index.html through file://.`n`nExport backups in Game & saves. Clearing browser data can erase progress. Browser and Windows saves share one format. Pokémon artwork and trademarks retain their separate rights; see CREDITS.md. Source and ready-to-play Windows packages are available in the same release.`n"
[IO.File]::WriteAllText((Join-Path $browserRoot 'README.md'),$browserReadme,$utf8)
foreach($root in @($windowsRoot,$browserRoot)){[IO.File]::WriteAllText((Join-Path $root 'RELEASE.json'),$json,$utf8)}
$sourceZip=Join-Path $directory $archives[0]
& git -c core.autocrlf=false archive --format=zip "--prefix=vibe-beasts-$version/" "--output=$sourceZip" HEAD
if($LASTEXITCODE -ne 0){throw 'Source archive failed.'}
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::Open($sourceZip,[IO.Compression.ZipArchiveMode]::Update)
try{$entry=$archive.CreateEntry("vibe-beasts-$version/RELEASE.json");$stream=$entry.Open();try{$bytes=$utf8.GetBytes($json);$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}}finally{$archive.Dispose()}
Compress-Archive -LiteralPath $browserRoot -DestinationPath (Join-Path $directory $archives[1]) -CompressionLevel Optimal
Compress-Archive -LiteralPath $windowsRoot -DestinationPath (Join-Path $directory $archives[2]) -CompressionLevel Optimal
$combined=''
foreach($name in $archives){$line=(Get-FileHash -LiteralPath (Join-Path $directory $name) -Algorithm SHA256).Hash.ToLowerInvariant()+'  '+$name+"`n";[IO.File]::WriteAllText((Join-Path $directory ($name+'.sha256')),$line,$utf8);$combined+=$line}
[IO.File]::WriteAllText((Join-Path $directory 'SHA256SUMS'),$combined,$utf8)
Write-Host "Packaged Vibe Beasts $version source, browser and Windows from $commit."
