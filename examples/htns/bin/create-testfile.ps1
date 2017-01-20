param( $fileName = "script.log", $value = "I was created by the script")
Write-Host "This script is run by kolli, my unbound args ($($args.Length) in length) are:"
$args | out-host

$testFilePath = join-path $PSScriptRoot "..\$fileName"
Write-Host "Creating test file $testFilePath"
sc -path $testFilePath -value $value
