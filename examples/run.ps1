push-location $PSScriptRoot

try {
    set-alias kolli (resolve-path ..\kolli.ps1)

    Write-Host -foregroundcolor green "Cleaning old build and install dir"
    ls | ?{ @( "build", "install" ) -contains $_.Name } | rm -recurse 

    function describeBlock {
        param( [scriptblock] $block )
        Write-host -foregroundcolor yellow "Executing:`r`n$block"
        & $block
    }

    Write-Host -foregroundcolor green "Building kolli aoeu"

    describeBlock { `
        push-location aoeu
        kolli b ..\build
        pop-location
    }

    Write-Host -foregroundcolor green "Adding aoeu kolli as dependency and building kolli htns"

    describeBlock { `
        push-location htns
        kolli add aoeu-1.0.0 ..\build
        kolli b ..\build
        pop-location
    }

    Write-Host -foregroundcolor green "Creating directory .\install and installing kolli 'htns' with dependency 'aoeu'"

    describeBlock { `
        mkdir .\install | push-location
        kolli install htns-1.0.0 ..\build
        pop-location
    }

    Write-Host -foregroundcolor green "Adding files and building htns package with new version"

    describeBlock { `
        push-location htns
        kolli set files test.txt, conf, bin
        kolli set postinstall ".\bin\create-testfile.ps1 -fileName 'postinstall.txt' -value `$env:SystemDrive\test", ".\bin\create-testfile.ps1 -setjob -name ""remotex-connecttotrello"" -cron ""H/5 * * * *"" -command ""ConnectToTrello.exe"""
        kolli set version "2.0.0"
        kolli b ..\build
        pop-location
    }

    Write-Host -foregroundcolor green "Installing package htns of new version (2.0.0)"

    if( test-path install\htns-2.0.0 ) {
        rm -recurse install\htns-2.0.0
    }

    describeBlock { `
        push-location install
        kolli install htns-2.0.0 ..\build
        pop-location
    }

    $installDir = join-path $PWD "install\htns-2.0.0"
    $files = ls -recurse $installDir | % FullName
    $expectedFiles = "conf\application.config", "foo.bar", "test.txt", "postinstall.log", "postinstall.txt" | %{ join-path $installDir $_ }

    $expectedFiles | % { 
        if( $files -notcontains $_ ) {
            Write-Host -foregroundcolor red "File $_ was not found when installing htns-2.0.0"
        }
    }

    $actualValue = gc (join-path $installDir "postinstall.txt" )
    $expectedValue = "$env:SystemDrive\test"
    if( $actualValue -ne $expectedValue ) {
        Write-Host -foregroundcolor red "File postinstall.txt did not contain the expected value.`r`nExpected: $expectedValue`r`nActual: $actualValue"
    }
} finally {
    pop-location
    git checkout htns\kolli.json
}