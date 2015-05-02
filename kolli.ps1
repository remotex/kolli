<#

Usage (dot-source):
  
  PS> . ./kolli.ps1
  PS> kolli

Usage (alias):

  PS> set-alias kolli ./kolli.ps1
  PS> kolli

#>

$kolliErrors = new-object System.Collections.ArrayList
$showLogInfo = $env:DEBUG -match "kolli:(info|\*)"
$stopwatch = new-object System.Diagnostics.Stopwatch
$kolliJson = "kolli.json"
$buildDirName = "build"

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
	write-host -foregroundcolor $color "[$text] " -nonewline
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
	logHeader gray "info"
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
	$files = $kolliObject.files | % { """{0}""" -f $_ }
	$dependencies = $kolliObject.dependencies | gm -membertype NoteProperty | % { """{0}"": ""{1}""" -f $_.Name, ( $kolliObject.dependencies | % $_.Name ) }
	$json = @"
{
  "name": "$($kolliObject.name)",
  "version": "$($kolliObject.version)",
  "files": [
    $( [string]::Join( ",`r`n    ", $files ) )
  ],
  "dependencies": {
    $( [string]::Join( ",`r`n    ", $dependencies ) )
  }
}
"@

	set-content -path $path -value $json -Encoding UTF8
}

function kolliInit {
	$path = join-path $PWD $kolliJson
	if( Test-Path $path ) {
		return logError "A $kolliJson file does already exist in $PWD"
	}

	writeJson $path (new-object psobject -property @{ `
		"name" = (readInput 'Package name' -mandatory);
		"version" == (readInput 'Version' -default '1.0.0')
	})

	logSuccess "Wrote $kolliJson"
	readJson $path | out-host
	write-host ""
}

function kolliBuild {
	param(
		$buildDir = $buildDirName
	)

	if( -not [System.IO.Path]::IsPathRooted( $buildDir ) ) {
		$buildDir = join-path $PWD $buildDir
	}

	$path = join-path $PWD $kolliJson
	$kolli = readJson $path | checkFiles

	if(!(Test-Path $buildDir)) {
		mkdir $buildDir | out-null
		logInfo "Created $buildDir"
	}

	$kolliFilename = "{0}-{1}" -f $kolli.name, $kolli.version
	$outputZip = join-path $buildDir ( $kolliFilename + ".zip" )
	$outputJson = join-path $buildDir ( $kolliFilename + ".json" )

	cp $path $outputJson
	logSuccess "Created $outputJson"

	$kolli.GetAbsoluteFilePaths() | Get-Item | newZip -target $outputZip | out-null
	logSuccess "Created $outputZip"

}

function kolliInstall {
	param(
		[string] $kolliName,
		[string] $source,
		[string] $target
	)

	if( -not $kolliName ) {
		return logError "Kolli name is required"
	}
	if( -not $source ) {
		return logError "A source is required"
	}
	if( -not $target ) {
		$target = join-path ( gi $PWD | % FullName ) $kolliName
	}

	$jsonPath = join-path $source "${kolliName}.json"
	if(!(Test-Path $jsonPath)) {
		return logError "Could not find kolli '$kolliName' at source '$source'"
	}
	$zipPath = $jsonPath -replace "\.json$", ".zip"
	if(!(Test-Path $zipPath)) {
		return logError "Could not find zip archive for kolli '$kolliName' at source '$source'"
	}

	$kolliJson = readJson $jsonPath
	if( $kolliJson.dependencies ) {
		$kolliJson.dependencies | gm -membertype NoteProperty | % {
			$dependencyName = "{0}-{1}" -f $_.Name, ( $kolliJson.dependencies | % $_.Name )
			kolliInstall -kolliName $dependencyName -source $source -target $target
		}
	}
	expandZip $zipPath -target $target
	logSuccess ("Installed '{0}' into '{1}'" -f $kolliName, $target)
}

function kolliAddDependency {
	param(
		[string] $kolliName,
		[string] $source
	)

	if( -not $kolliName ) {
		return logError "Kolli name is required"
	}
	if( -not $source ) {
		return logError "A source is required"
	}

	$jsonPath = join-path $source "${kolliName}.json"
	if(!(Test-Path $jsonPath)) {
		return logError "Could not find kolli '$kolliName' at source '$source'"
	}

	$localKolliPath = join-path $PWD $kolliJson
	if( !( Test-Path $localKolliPath ) ) {
		return logError "Could not find kolli.json. Call 'kolli init' to begin."
	}

	$kolli = readJson $localKolliPath | checkFiles
	$dependency = readJson $jsonPath

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

function usage {
@"
Usage:

    kolli command args

Commands:

    init    Interactive initialization of kolli.json
    install Installs a package from a package source
    add     Adds a dependency to kolli.json
    build   Builds the package defined by kolli.json

"@ | out-host
}

$mainArgs = $args

function kolliMain {
	$kolliErrors.Clear()
	$stopwatch.Start()

	if( -not $mainArgs ) {
		$mainArgs = $args
	}

	$command = $mainArgs[0]
	switch -wildcard ($command) {
		"ini*" { kolliInit }
		"b*" { kolliBuild -buildDir $mainArgs[1] }
		"ins*" { kolliInstall -kolliName $mainArgs[1] -source $mainArgs[2] }
		"a*" { kolliAddDependency -kolliName $mainArgs[1] -source $mainArgs[2] }
		default { 
			if( $command ) {
				logError "No such command '$command'"
			}
			usage
		}
	}

	$stopwatch.Stop()

	if( $kolliErrors.Count ) {
		write-host -foregroundcolor red "Found $($kolliErrors.Count) errors"
	}
}

if( $MyInvocation.CommandOrigin -eq "Runspace" ) {
	kolliMain
} else {
	# kolli.ps1 was dot-sourced, overwirte kolli alias
	Write-host "Type 'kolli' to begin"
	set-alias kolli kolliMain
}