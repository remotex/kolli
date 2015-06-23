param( $fileName = "postinstall.log")
Write-Host "This is postinstall command, my args $($args.Length) are"
$args | out-host

$testFilePath = join-path $PSScriptRoot "..\$fileName"
Write-Host "Creating test file $testFilePath"
sc -path $testFilePath -value "I was created by the postinstall script"