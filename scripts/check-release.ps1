param([string]$Artifacts,[Parameter(Mandatory=$true)][string]$Out,[Parameter(Mandatory=$true)][string]$Compiler,[Parameter(Mandatory=$true)][string]$Raylib,[switch]$VerifyWindow)
$ErrorActionPreference='Stop'
if(-not $Artifacts){$Artifacts=Join-Path (Split-Path $PSScriptRoot) 'release-artifacts'}
$Artifacts=(Resolve-Path -LiteralPath $Artifacts).Path;$Out=[IO.Path]::GetFullPath($Out)
if(Test-Path -LiteralPath $Out){throw 'Use a fresh consumer folder; existing files are never replaced.'}
$lines=@(Get-Content -LiteralPath (Join-Path $Artifacts 'SHA256SUMS') | Where-Object {$_})
if($lines.Count -ne 3){throw 'Expected source, browser and Windows checksums.'}
$names=@();$versions=@()
foreach($line in $lines){
    if($line -notmatch '^([0-9a-f]{64})  (vibe-beasts_([0-9]+\.[0-9]+\.[0-9]+)_(source|browser|windows-x64)\.zip)$'){throw 'Invalid checksum format or filename.'}
    $expected=$Matches[1];$name=$Matches[2];$versions+=$Matches[3]
    if($names -contains $name){throw 'Duplicate archive name.'};$names+=$name
    if((Get-FileHash -LiteralPath (Join-Path $Artifacts $name) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected){throw "Checksum mismatch: $name"}
    if([IO.File]::ReadAllText((Join-Path $Artifacts ($name+'.sha256'))) -ne $line+"`n"){throw 'Individual checksum differs.'}
}
if(@($versions|Select-Object -Unique).Count -ne 1){throw 'Archive versions differ.'}
$expectedNames=@($names+@($names|ForEach-Object{$_+'.sha256'})+'SHA256SUMS')|Sort-Object
if(Compare-Object $expectedNames @(Get-ChildItem -LiteralPath $Artifacts -File|Select-Object -ExpandProperty Name|Sort-Object)){throw 'Artifact file set differs.'}
New-Item -ItemType Directory -Path $Out | Out-Null
$roots=@{}
foreach($kind in @('source','browser','windows-x64')){
    $name="vibe-beasts_$($versions[0])_$kind.zip";$destination=Join-Path $Out $kind
    Expand-Archive -LiteralPath (Join-Path $Artifacts $name) -DestinationPath $destination
    $folders=@(Get-ChildItem -LiteralPath $destination -Directory)
    if($folders.Count -ne 1){throw 'Expected a single package root.'};$roots[$kind]=$folders[0].FullName
}
$source=$roots.source;$browser=$roots.browser;$windows=$roots.'windows-x64'
$json=[IO.File]::ReadAllText((Join-Path $source 'RELEASE.json'))
foreach($root in @($browser,$windows)){if($json -ne [IO.File]::ReadAllText((Join-Path $root 'RELEASE.json'))){throw 'Package identities differ.'}}
$meta=$json|ConvertFrom-Json
if($meta.name -ne 'vibe-beasts' -or $meta.version -ne $versions[0] -or $meta.commit -notmatch '^[0-9a-f]{40}$' -or $meta.tree -notmatch '^[0-9a-f]{40}$'){throw 'Invalid release identity.'}
$sourcePaths=@($meta.sourceFiles|ForEach-Object{$_.path})
if(@($sourcePaths|Select-Object -Unique).Count -ne $sourcePaths.Count){throw 'Duplicate source paths.'}
$actual=@(Get-ChildItem -LiteralPath $source -Recurse -File -Force|ForEach-Object{$_.FullName.Substring($source.Length+1).Replace('\','/')})|Sort-Object
if(Compare-Object (@($sourcePaths+'RELEASE.json')|Sort-Object) $actual){throw 'Source file set differs from the manifest.'}
foreach($file in $meta.sourceFiles){
    if($file.path -match '(^/|\\|(^|/)\.\.(/|$))' -or $file.blob -notmatch '^[0-9a-f]{40}$'){throw 'Invalid source path or blob.'}
    $bytes=[IO.File]::ReadAllBytes((Join-Path $source $file.path));$prefix=[Text.Encoding]::ASCII.GetBytes("blob $($bytes.Length)`0");$hash=[Security.Cryptography.SHA1]::Create()
    try{$value=[BitConverter]::ToString($hash.ComputeHash([byte[]]($prefix+$bytes))).Replace('-','').ToLowerInvariant()}finally{$hash.Dispose()}
    if($value -ne $file.blob){throw "Source blob differs: $($file.path)"}
    if($file.path.StartsWith('dist/')){
        if((Get-FileHash -LiteralPath (Join-Path $browser $file.path) -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath (Join-Path $source $file.path) -Algorithm SHA256).Hash){throw "Browser file differs: $($file.path)"}
    }
}
$windowsPaths=@($meta.windowsFiles|ForEach-Object{$_.path})
$actualWindows=@(Get-ChildItem -LiteralPath $windows -Recurse -File|ForEach-Object{$_.FullName.Substring($windows.Length+1).Replace('\','/')})|Sort-Object
if(Compare-Object (@($windowsPaths+'RELEASE.json')|Sort-Object) $actualWindows){throw 'Windows file set differs.'}
foreach($file in $meta.windowsFiles){if($file.path -match '(^/|\\|(^|/)\.\.(/|$))' -or $file.sha256 -notmatch '^[0-9a-f]{64}$'){throw 'Invalid Windows path or hash.'};if((Get-FileHash -LiteralPath (Join-Path $windows $file.path) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.sha256){throw "Windows file differs: $($file.path)"}}
$game=Join-Path $windows 'VibeBeasts.exe'
if((Get-FileHash -LiteralPath $game -Algorithm SHA256).Hash.ToLowerInvariant() -ne $meta.executableSha256){throw 'Executable hash differs.'}
$details=[Diagnostics.FileVersionInfo]::GetVersionInfo($game)
if($details.FileVersion -ne $meta.version -or $details.ProductVersion -ne $meta.version){throw 'Executable version differs.'}
foreach($options in @('--version','--unknown','--save','--version --smoke-test')){
    $process=Start-Process -FilePath $game -ArgumentList $options -WorkingDirectory $Out -WindowStyle Hidden -PassThru
    try{if(-not $process.WaitForExit(5000)){$process.Kill();throw 'CLI check unexpectedly opened a game.'};if(($options -eq '--version' -and $process.ExitCode -ne 0) -or ($options -ne '--version' -and $process.ExitCode -eq 0)){throw "Unexpected option result: $options"}}finally{$process.Dispose()}
}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source 'scripts/build-windows.ps1') -Compiler $Compiler -Raylib $Raylib
if($LASTEXITCODE -ne 0){throw 'Delivered Windows source build failed.'}
Push-Location $source
try{
    & node scripts/web-receipt.mjs --verify; if($LASTEXITCODE -ne 0){throw 'Delivered browser receipt failed.'}
    & node tests/web-core.mjs; if($LASTEXITCODE -ne 0){throw 'Delivered actual WASM interoperability failed.'}
    & node tests/web-save.mjs; if($LASTEXITCODE -ne 0){throw 'Delivered browser save checks failed.'}
    & node tests/assets.mjs; if($LASTEXITCODE -ne 0){throw 'Delivered artwork manifest failed.'}
}finally{Pop-Location}
if($VerifyWindow){
    $save=Join-Path $Out 'native-smoke.save';$snapshot=Join-Path $Out 'native-preview.png'
    $process=Start-Process -FilePath $game -ArgumentList @('--save',('"'+$save+'"'),'--snapshot',('"'+$snapshot+'"')) -WorkingDirectory $Out -WindowStyle Hidden -PassThru
    try{if(-not $process.WaitForExit(30000)){$process.Kill();throw 'Native render timed out.'};if($process.ExitCode -ne 0){throw 'Actual delivered native render failed.'};if(-not(Test-Path -LiteralPath $save) -or -not(Test-Path -LiteralPath $snapshot)){throw 'Native render did not produce isolated save and screenshot.'}}finally{$process.Dispose()}
}
Write-Host "PASS: paired source/browser/Windows identities, all $($sourcePaths.Count) source blobs, native files and versions, CLI, delivered source rebuild and actual WASM checks. Native window checked: $VerifyWindow."
