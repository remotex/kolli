<#

Usage:

  PS> set-alias kolli ./kolli.ps1
  PS> kolli

#>

$kolliErrors = new-object System.Collections.ArrayList
$showLogInfo = $env:DEBUG -match "kolli:(info|\*)"
$stopwatch = new-object System.Diagnostics.Stopwatch
$kolliJson = "kolli.json"
$buildDirName = "build"
$defaultPort = 8000

function newZip {
	param(
		[parameter(mandatory=$true)]
		$target,
		[parameter(mandatory=$true, ValueFromPipelineByPropertyName=$true)]
		[alias("FullName")]
		[string[]]$files
	)
	begin {
		Add-type -AssemblyName "System.IO.Compression.FileSystem"
		if(Test-Path $target) { Remove-Item $target -force }
		$zip = [System.IO.Compression.ZipFile]::Open( $target, "Create" )
	}
	process {
		$files | Resolve-Path | ls -recurse -force -file | % FullName | % {
			$relativePath = Resolve-Path $_ -Relative
			[void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_, $relativePath.TrimStart(".\"), [System.IO.Compression.CompressionLevel]::Optimal)
		}
	}
	end {
		$zip.Dispose()
		Get-Item $target
	}
}
function expandZip {
	param(
		[parameter(mandatory=$true)]
		$path,
		$target = $pwd
	)

	Add-type -AssemblyName "System.IO.Compression.FileSystem"
	$path = Get-Item $path | % FullName

	if( !(Test-Path $target)) {
		mkdir $target | out-null
	}

	$zip = [System.IO.Compression.ZipFile]::Open( $path, "Read" )
	try {
		$zip.Entries | % {			
			$entryPath = join-path $target $_.FullName
			if( $_.Name -eq '' ) {
				mkdir $entryPath -force | out-null
			} else {
				$directory = $entryPath | Split-Path
				if( !(Test-Path $directory)) {
					mkdir $directory -force | out-null
				}
				[System.IO.Compression.ZipFileExtensions]::ExtractToFile( $_, $entryPath, $true )
			}
		}
	} finally {
		if( $zip -ne $null ) {
			$zip.Dispose()
		}
	}
}

function readInput {
	param( 
		$prompt,
		$default,
		[switch] $mandatory
	)

	$response = $null
	do {
		$response = read-host ("{0} [{1}]" -f $prompt, $default)
		if( $default -and -not $response ) {
			$response = $default
		}
	} while( $mandatory -and -not $response )

	$response
}

function logHeader {
	param( $color, $text )
	$time = $stopwatch.Elapsed
	write-host -foregroundcolor gray ("[{0:d2}:{1:d2}.{2:d3}]" -f $time.Minutes, $time.Seconds, $time.Milliseconds) -nonewline
	write-host -foregroundcolor $color ( "[{0}] " -f $text.PadRight(10, " ") ) -nonewline
}

function logError {
	logHeader red "error"
	$kolliErrors.Add( $args ) | out-null
	$args | out-host
}

function logInfo {
	if( -not $showLogInfo ) { 
		return 
	}
	logHeader yellow "info"
	$args | out-host
}

function logSuccess {
	logHeader green "success"
	$args | out-host
}

filter checkFiles {
	$_.GetAbsoluteFilePaths() | %{
		if( -not ( Test-Path $_ ) ) {
			logError "Missing file '$_'"
		}
	}
	$_
}

function hasValidName {
	param( $kolli )
	if( -not $kolli.name -or $kolli.name -notmatch "^[\w\d\-_]+$" ) {
		throw "Invalid kolli name: '$($kolli.name)' in $path. Name can only contain alphanumerics, dash and underscore characters."
	}
}

function readJson {
	param( [parameter(mandatory = $true)] $path )

	$kolli = get-content $path | out-string | convertfrom-json

	$dir = $path | Split-Path
	$getAbsoluteFilePaths = [ScriptBlock]::Create("`$this.files | % { join-path ""$dir"" `$_ } ")
	$kolli | add-member -passthru `
		-membertype ScriptMethod `
		-name GetAbsoluteFilePaths `
		-value $getAbsoluteFilePaths 
}

function writeJson {
	param(
		[string] $path,
		$kolliObject
	)

	hasValidName $kolliObject

	$files = $kolliObject.files | % { """{0}""" -f $_ }
	$dependencies = @()
	if( $kolliObject.dependencies ) {
		$dependencies = $kolliObject.dependencies | gm -membertype NoteProperty | % { """{0}"": ""{1}""" -f $_.Name, ( $kolliObject.dependencies | % $_.Name ) }
	}
	$dependenciesString = ""

	if( $dependencies ) {
		$dependenciesString = [string]::Join( ",`r`n    ", $dependencies )
	}

	$json = @"
{
  "name": "$($kolliObject.name)",
  "version": "$($kolliObject.version)",
  "files": [
    $( [string]::Join( ",`r`n    ", $files ) )
  ],
  "dependencies": {
    $dependenciesString
  }
}
"@

	set-content -path $path -value $json -Encoding UTF8

	logInfo ( "Wrote {0}" -f $path )
}

function kolliInit {
	$path = join-path $PWD $kolliJson
	if( Test-Path $path ) {
		return logError "A $kolliJson file does already exist in $PWD"
	}

	writeJson $path (new-object psobject -property @{ `
		"name" = (readInput 'Package name' -mandatory);
		"version" = (readInput 'Version' -default '1.0.0')
	})

	logSuccess "Wrote $kolliJson"
	readJson $path | out-host
	write-host ""
}

$tempFilesToDelete = new-object System.Collections.ArrayList

function getTempWebFile {
	param( $source, $fileName )

	$sourceCacheDirName = $source -replace "[:/]", "_"
	$cacheDir = join-path $env:tmp "kolli\cache\$sourceCacheDirName"
	if( -not (test-path $cacheDir ) ) {
		mkdir $cacheDir | out-null
	}

	$tempFilePath = join-path $cacheDir $fileName
	$tempFilesToDelete.Add( $tempFilePath ) | out-null

	logInfo "Adding temp file path $tempFilePath"

	$tempFilePath
}

function cleanupTempFiles {
	$tempFilesToDelete | % {
		$path = $_
		if( -not (test-path $path) ) {
			continue
		}
		try {
			rm -force $path
			logInfo "Removed $path"
		} catch {
			logError "Failed to clean up cached file: $path"
		}
	}
	$tempFilesToDelete.Clear()
}

function getLocalOrGlobalDir {
	param( [string] $dirOrGlobalFlag )

	$dir = $buildDirName
	if( $dirOrGlobalFlag -eq "-g" ) {
		$dir = join-path $env:userprofile "kolli\$buildDirName"
	} elseif( $dirOrGlobalFlag ) {
		$dir = $dirOrGlobalFlag
	}
	if( -not [System.IO.Path]::IsPathRooted( $dir ) ) {
		$dir = join-path $PWD $dir
	}
	if( -not (test-path -pathtype container $dir ) ) {
		mkdir $dir | out-null
	}
	$fullName = Resolve-Path $dir | Get-Item | % FullName

	logInfo "Selecting path $fullName"

	$fullName
}

function kolliBuild {
	param(
		$buildDir
	)

	$buildDir = getLocalOrGlobalDir $buildDir

	$path = join-path $PWD $kolliJson
	$kolli = readJson $path | checkFiles
	hasValidName $kolli

	if(!(Test-Path $buildDir)) {
		mkdir $buildDir | out-null
		logInfo "Created $buildDir"
	}

	$kolliFilename = "{0}-{1}" -f $kolli.name, $kolli.version
	$outputZip = join-path $buildDir ( $kolliFilename + ".zip" )
	$outputJson = join-path $buildDir ( $kolliFilename + ".json" )

	cp $path $outputJson
	logSuccess "Created $outputJson"

	$tempZipPath = [System.IO.Path]::GetTempFileName()
	$kolli.GetAbsoluteFilePaths() | Get-Item | newZip -target $tempZipPath | out-null
	mv $tempZipPath $outputZip -force
	logSuccess "Created $outputZip"

}

function kolliSet {
	param( 
		[string] $property,
		$value
	)

	$path = join-path $PWD $kolliJson
	$kolli = readJson $path

	if( $property -eq "files" ) {
		$files = $value | %{ ls -recurse ( join-path $PWD $_ ) | %{ $_.FullName.Replace( $PWD.Path + "\", "" ).Replace( "\", "/" ) } }
		$files | %{
			logInfo "File $_"
		}
		$kolli.files = $files
		logInfo ("Total: {0}" -f ($kolli.files | measure).Count)
		writeJson $path $kolli
	} elseif( $property -eq "name" ) {
		$kolli.name = $value
		logInfo ("Setting name to: {0}" -f $value)
		writeJson $path $kolli
	} elseif( $property -eq "version" ) {
		if( -not ( $value -match "(\d+\.)\d+(-[\w\-\d]+)?") ) {
			return logError ("The value '{0}' does not seem to be a valid version number" -f $value )
		}
		$kolli.version = $value
		logInfo ("Setting version to: {0}" -f $value)
		writeJson $path $kolli
	} else {
		logError ( "Invalid option '{0}' to command 'kolli set'" -f $property )
	}
}

function getKolliFromSources {
	param( 
		[string] $kolliName,
		[string[]] $sources 
	)

	foreach( $source in $sources ) {
		$kolliSource = getKolliFromSource $kolliName $source
		if( $kolliSource.Json ) {
			logSuccess ( "Found '{0}' at source {1}" -f $kolliName, $source )
			return $kolliSource
		}
	}
	if( -not $kolliSource.Json ) {
		logError ("Could not find kolli '{0}' at any source" -f $kolliName, $source)
		return $kolliSource
	}
}

function getKolliFromSource {
	param( $kolliName, $source )

	$json = {}
	$jsonPath = $null
	$zipPath = $null
	$jsonFileName = "${kolliName}.json"
	$zipFileName = "${kolliName}.zip"
	if( $source.StartsWith( "http" ) ) {
		$source = $source.TrimEnd("/") + "/"
		$jsonUrl = (new-object System.Uri( $source, $jsonFileName, [System.UriKind]::Absolute )).AbsoluteUri
		$zipUrl = (new-object System.Uri( $source, $zipFileName, [System.UriKind]::Absolute )).AbsoluteUri
		$webclient = New-Object System.Net.WebClient
		$zipPath = getTempWebFile $source $zipFileName
		$jsonPath = getTempWebFile $source $jsonFileName
		try {
			logInfo "Downloading $jsonUrl"
			$webclient.DownloadFile($jsonUrl, $jsonPath)
		} catch {
			return logInfo "Failed to get '$kolliName' from source '$source' $_"
		}
		try {
			logInfo "Downloading $zipUrl"
			$webclient.DownloadFile($zipUrl, $zipPath)
		} catch {
			return logInfo "Failed to get zip archive for kolli '$kolliName' from source '$source' $_"
		}
	} else {
		$jsonPath = join-path $source $jsonFileName
		if(!(Test-Path $jsonPath)) {
			return logInfo "Could not find kolli '$kolliName' at source '$source'"
		}
		$zipPath = join-path $source $zipFileName
		if(!(Test-Path $zipPath)) {
			return logInfo "Could not find zip archive for kolli '$kolliName' at source '$source'"
		}
	}

	$json = readJson $jsonPath
	new-object psobject -property @{ KolliName = $kolliName; JsonPath = $jsonPath; ZipPath = $zipPath; Json = $json }
}

function kolliInstall {
	param(
		$kolliName,
		$kolliSource,
		[string[]] $sources,
		[string] $targetDir,
		[switch] $verifyOnly
	)

	if( -not $kolliName -and -not $kolliSource ) {
		return logError "Kolli name is required"
	}
	if( -not $sources.Length ) {
		return logError "A source is required"
	}

	if( $kolliName ) {
		$kolliSource = getKolliFromSources $kolliName $sources
	} else {
		$kolliName = $kolliSource.KolliName
	}
	if( -not $targetDir ) {
		$targetDir = join-path ( gi $PWD | % FullName ) $kolliName
	}

	if( -not $kolliSource.Json ) {
		return logError ( "Kolli '{0}' could not be found." -f $kolliName )
	} else {
		$kolli = $kolliSource.Json
		$missingDependencies = $false
		if( $kolli.dependencies ) {
			$kolli.dependencies | gm -membertype NoteProperty | % {
				$dependencyName = "{0}-{1}" -f $_.Name, ( $kolli.dependencies | % $_.Name )
				logSuccess ("Detected dependency {0}" -f $dependencyName)
				$dependency = getKolliFromSources $dependencyName $sources
				if( $dependency.Json ) {
					kolliInstall -kolliSource $dependency -sources $sources -targetDir $targetDir -verifyOnly:$verifyOnly
				} else {
					$missingDependencies = $true
					logError "Dependency '$dependencyName' could not be found."
				}
			}
		}
		if( $missingDependencies ) {
			return logError ( "All dependencies for '{0}' could not be found from the sources specified." -f $kolliName )
		} 
	}

	if( $verifyOnly ) {
		logSuccess ( "Kolli '{0}' verified successfully." -f $kolliName )
	} else {
		expandZip $kolliSource.ZipPath -target $targetDir
		logSuccess ("Installed '{0}' into '{1}'" -f $kolliName, $targetDir)
	}
}

function kolliAddDependency {
	param(
		[string] $kolliName,
		[string[]] $sources
	)

	if( -not $kolliName ) {
		return logError "Kolli name is required"
	}
	if( -not $sources.Length ) {
		return logError "A source is required"
	}

	$kolliSource = getKolliFromSources $kolliName $sources
	if( -not $kolliSource.Json ) {
		logError ("Could not find kolli '{0}' at source '{1}'" -f $kolliName, $source)
		return
	}

	$localKolliPath = join-path $PWD $kolliJson
	if( !( Test-Path $localKolliPath ) ) {
		return logError "Could not find kolli.json. Call 'kolli init' to begin."
	}

	$kolli = readJson $localKolliPath | checkFiles
	$dependency = $kolliSource.Json

	if( $kolli.name -eq $dependency.name -or ( $dependency.dependencies -and $dependency.dependencies | gm $kolli.name ) ) {
		return logError ( "A circular dependency was detected: '{0}' => '{1}'" -f $dependency.name, $kolli.name )
	}

	if( -not $kolli.dependencies ) {
		$kolli.dependencies = new-object psobject
	}
	if( $kolli.dependencies | gm $dependency.name ) {
		$kolli.dependencies."$($dependency.name)" = $dependency.version
	} else {
		$kolli.dependencies | add-member -membertype NoteProperty -name $dependency.name -value $dependency.version
	}
	writeJson $localKolliPath $kolli
	logSuccess ("Added '{0}' => '{1}'" -f $dependency.name, $dependency.version)
}

function kolliServe {
	param(
		[string] $source,
		[string] $ipAddress,
		[int] $port 
	)
	$source = getLocalOrGlobalDir $source
	if( -not $ipAddress ) {
		$ipAddress = "+"
	}
	if( -not $port ) {
		$port = $defaultPort
	}
	if( -not (test-path $source -pathtype container) ) {
		throw "Source is not an existing directory: $source"
	} else {
		$source = Resolve-Path $source
	}
	$httpListener = New-Object Net.HttpListener
	$prefix = "http://{0}:{1}/" -f $ipAddress, $port
	$httpListener.Prefixes.Add( $prefix )
	try {
		$httpListener.Start()
		Write-Host "Server started listening to $prefix"
		Write-Host "Serving files from directory $source"
	} catch {
		Write-Error "Failed to start server: $_"
		return
	}

	$server = {
		param( $webRoot, $httpListener, $StdOut, $StdErr )

		While ($httpListener.IsListening) {
			$httpContext = $null
			try { 
				$httpContext = $httpListener.GetContext()
			} catch {
				if( $_ -notmatch "The I/O operation has been aborted" ) {
					$StdErr.WriteLine( "Error: $_" )
				}
				return
			}
			$req = $httpContext.Request
			$res = $httpContext.Response
			$localFilePath = Join-Path $webRoot $req.RawUrl

			$length = 0
			if( $req.HttpMethod -ne "GET" ) {
				$res.StatusCode = 405 # Method Not Allowed
			} elseif( test-path $localFilePath -pathtype leaf ) {
				if( $localFilePath.EndsWith( ".zip" ) ) {
					$res.Headers.Add("Content-Type","application/zip")
				} elseif( $localFilePath.EndsWith( ".json" ) ) {
					$res.Headers.Add("Content-Type","application/json; charset=UTF-8")
				} else {
					$res.StatusCode = 403 # Forbidden
				}
				if( $res.StatusCode -eq 200 ) {
					$fileBytes = [System.IO.File]::ReadAllBytes( $localFilePath )
					$length = $fileBytes.Length
					$res.ContentLength64 = $length
					$res.OutputStream.Write($fileBytes,0,$length)
					$res.OutputStream.Flush()
				}
			} else {
				$res.StatusCode = 404 # Not Found
			}
			$StdOut.WriteLine(("{0:yyyy-MM-dd} {0:HH:mm:ss} {1} {2} {3} {4}" -f (get-date), $req.HttpMethod, $req.RawUrl, $res.StatusCode, $length))
			$res.Close()
		}
		try {
			$httpListener.Stop()
		} finally {
			$StdOut.WriteLine( "Server was stopped" )
		}
	}

	$pool = [RunspaceFactory]::CreateRunspacePool(1, 1)
	$pool.ApartmentState = "STA"
	$pool.Open()
	$pipeline  = [System.Management.Automation.PowerShell]::create()
	$pipeline.RunspacePool = $pool
	$pipeline.AddScript($server).AddArgument($source).AddArgument($httpListener).AddArgument( [Console]::Out).AddArgument( [Console]::Error) | out-null

	$AsyncHandle = $pipeline.BeginInvoke()
	try {
		Do {
			Start-Sleep -Seconds 1
		} While ( -not $AsyncHandle.IsCompleted )
	} finally {
		Write-Host "Stopping..."
		try {
			$httpListener.Stop()
			$pipeline.EndInvoke($AsyncHandle)
		} catch {
			Write-Error "Error on stop: $_"
		}
	}
	$pipeline.Dispose()
	$pool.Close()

	Write-Host ""
}

function usage {
@"
Usage:

    kolli command args

Commands:

    init    Interactive initialization of kolli.json
    install Installs a package from a package source
    add     Adds a dependency to kolli.json
    build   Builds the package defined by kolli.json
    serve   Starts a development HTTP server that can be used as a package source
    set     Modifies a property in kolli.json
            name - changes the name
            version - changes the version
            files [pattern] - replaces the files array with the files matching the pattern
    verify  Verifies a package

"@ | out-host
}

$mainArgs = $args

function kolliMain {
	$kolliErrors.Clear()
	$stopwatch.Start()

	if( -not $mainArgs ) {
		$mainArgs = $args
	}

	function sourcesFromArgs {
		param( $startIndex )
		$sources = new-object System.Collections.ArrayList
		logInfo "List of sources"
		for( $i = $startIndex; $i -lt $mainArgs.Length; $i++) {
			$source = $mainArgs[$i]
			if( -not ($source.StartsWith("http") -or $source.StartsWith("\\")) -and (test-path $source)) {
				$source = Resolve-Path $source
			}
			$sourceIndex = $sources.Add($source)
			logInfo ( "[{0}] {1}" -f ( $sourceIndex + 1 ), $sources[$sourceIndex] )
		}

		if( -not $sources.Length ) {
			$sources.Add( $PWD.Path ) | out-null
			logInfo ( "[1] {0}" -f $sources[0] )
		}
		$sources
	}

	$command = $mainArgs[0]
	switch -wildcard ($command) {
		"ini*" { kolliInit }
		"b*" { kolliBuild -buildDir $mainArgs[1] }
		"ins*" { 
			$sources = sourcesFromArgs -startIndex 2
			kolliInstall -kolliName $mainArgs[1] -sources $sources 
		}
		"a*" { 
			$sources = sourcesFromArgs -startIndex 2
			kolliAddDependency -kolliName $mainArgs[1] -sources $sources 
		}
		"set" { kolliSet -property $mainArgs[1] -value $mainArgs[2] }
		"ser*" { kolliServe -source $mainArgs[1] -ipAddress $mainArgs[2] -port $mainArgs[3] }
		"veri*" { 
			$sources = sourcesFromArgs -startIndex 2
			kolliInstall -kolliName $mainArgs[1] -sources $sources -verifyOnly
		}
		default { 
			if( $command ) {
				logError "No such command '$command'"
			}
			usage
		}
	}

	cleanupTempFiles

	$stopwatch.Stop()

	if( $kolliErrors.Count ) {
		write-host -foregroundcolor red "Found $($kolliErrors.Count) errors"
	}
}

kolliMain
