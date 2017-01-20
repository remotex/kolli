push-location $PSScriptRoot

try {
    set-alias kolli (resolve-path ..\kolli.ps1)

    function tell {
      param( $message )
      Write-Host -foregroundcolor green $message
    }
    function err {
      param( $message )
      Write-Host -foregroundcolor red $message
    }

    tell "Cleaning old build and install dir"
    ls | ?{ @( "build", "install" ) -contains $_.Name } | rm -recurse

    function describeBlock {
        param( [scriptblock] $block )
        Write-host -foregroundcolor yellow "Executing:`r`n$block"
        & $block
    }
    function expectFile {
      param( $path, $expectedValue, $message )
      $actualValue = gc $path
      if( $actualValue -ne $expectedValue ) {
          err "$message`r`nFile $path did not contain the expected value.`r`nExpected: $expectedValue`r`nActual: $actualValue"
      }
    }
    function removeDir {
      param( $path )
      if( test-path $path ) {
          rm -recurse $path
      }
    }

    tell "Building kolli aoeu"

    describeBlock { `
        push-location aoeu
        kolli b ..\build
        pop-location
    }

    tell "Adding aoeu kolli as dependency and building kolli htns"

    describeBlock { `
        push-location htns
        kolli add aoeu-1.0.0 ..\build
        kolli b ..\build
        pop-location
    }

    tell "Creating directory .\install and installing kolli 'htns' with dependency 'aoeu'"

    describeBlock { `
        mkdir .\install | push-location
        kolli install htns-1.0.0 ..\build
        pop-location
    }

    tell "Adding files and building htns package with new version"

    describeBlock { `
        push-location htns
        kolli set files test.txt, conf, bin
        kolli set preinstall ".\bin\create-testfile.ps1 -fileName 'preinstall.txt' -value `$PWD"
        kolli set postinstall ".\bin\create-testfile.ps1 -fileName 'postinstall.txt' -value `$PWD", ".\bin\create-testfile.ps1 -setjob -name ""remotex-connecttotrello"" -cron ""H/5 * * * *"" -command ""ConnectToTrello.exe"""
        kolli set version "2.0.0"
        kolli b ..\build
        pop-location
    }

    tell "Installing package htns of new version (2.0.0)"

    removeDir install\htns-2.0.0

    describeBlock { `
        push-location install
        kolli install htns-2.0.0 ..\build
        pop-location
    }

    $installDir = join-path $PWD "install\htns-2.0.0"
    $files = ls -recurse $installDir | % FullName
    $expectedFiles = "conf\application.config", "foo.bar", "test.txt", "preinstall.txt", "script.log", "postinstall.txt" | %{ join-path $installDir $_ }

    tell "Checking output for files listed by kolli"

    $expectedFiles | % {
        if( $files -notcontains $_ ) {
            err "File $_ was not found when installing htns-2.0.0"
        }
    }

    tell "Checking results of pre- and postinstall scripts"

    $tempInstallPath = join-path $PSScriptRoot "install\htns-2.0.0__kollitmp\bin"
    expectFile (join-path $installDir "preinstall.txt" ) $tempInstallPath "Expected preinstall.txt to contain path of temporary install directory"

    $finalInstallPath = join-path $PSScriptRoot "install\htns-2.0.0\bin"
    expectFile (join-path $installDir "postinstall.txt" ) $finalInstallPath "Expected postinstall.txt to contain path of final install directory"


    tell "Testing behavior of preinstall script with non-zero exit code"

    describeBlock { `
        push-location htns
        kolli set preinstall ".\bin\exit-one.ps1"
        kolli set version "2.0.1"
        kolli b ..\build
        pop-location
    }

    tell "Installing package htns of new version (2.0.1)"

    $installDir = join-path $PWD "install\htns-2.0.1"
    removeDir $installDir

    describeBlock { `
        push-location install
        kolli install htns-2.0.1 ..\build
        pop-location
    }

    if( test-path $installDir ) {
      err "Installation directory exists. Installation was completed even though preinstall script returned non-zero exit code"
    } else {
      tell "Successfully trapped preinstall script error"
    }

    $tempInstallPath = join-path $PSScriptRoot "install\htns-2.0.1__kollitmp\bin"
    if( test-path $tempInstallPath ) {
      err "Temporary installation directory exists. Directory was not cleaned up after preinstall script error"
    } else {
      tell "Temporary installation directory was successfully removed by kolli upon preinstall script error"
    }

} finally {
    pop-location
    git checkout htns\kolli.json
}
