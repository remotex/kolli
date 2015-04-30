# kolli package manager
![collie is not kolli](https://dl.dropboxusercontent.com/u/126999/kolli.png)
## What

A minimalistic approach to put applications on servers (deployment) decent amount of borrowed features from NPM, bower, nuget and maybe Chocolatey as well. Think multi-part zip archives.

## Why?

Because our needs are not fulfilled using any of the others. Kolli is very opinionated, just like all the others, and created to solve a specific problem. The word "kolli" is Swedish for parcel or package and is used here to represent the word *parcelle* from Old French meaning *"a small piece or part."*

### A business scenario
* A 500 mb zip archive representing the "vanilla" version of a product
* A 2 mb zip archive representing a specific tenant/customer's configuration/customization
* Circa 15-20 concurrent versions in production - tenants/customers needs to get new version in rolling/staged upgrades
* Managing one large (502 mb in this example) zip archive for every customer is inefficient

### A typical deployment scenario:
* Put zip archive with new version of the product on server
* Extract into a given folder
* Copy some tenant/customer specific files into the folder
* Register/update alias/vdir in apache/IIS pointing to the public sub-folder of the given folder
* Register/update cronjob/scheduled task calling bin/application residing in the given folder
* Add tenant user account for SFTP access and FTP home folder
* Remove old version of the app for the tenant/customer

### The wish list
* Packages that are more like multi-part zip archives, unlike the dependency models used by NPM, Bower, nuGet...
* A list of package caches (persistent or transient) to look in/update during install
* Source packages to caches from local/network paths and/or HTTP urls
* Explicit declaration of files that are to be "installed", like the "main" concept of bower.json
* A "git push heroku" deployment model per tenant/customer compared to doing a "puppet run" per server
* Declarative "post install" tasks like Puppet/Chef/Powershell DSC resources, compared to NPM scripts 
* Opt-in automatic or manual cleanup of old version of application, sort of equiv. to ```bower cache clean```

## Kolli features and opinions

* Uses published release bits from a package source and extracts its contents
* The kolli.json package manifest tells what to be extracted
* The kolli.json package manifest must be published side-by-side for each package, i.e. *tenant-1.2.3.4.zip* and *tenant-1.2.3.4.json*
* The manifest file also dictates the dependencies, that is, other kolli packages to install
* Packages are installed into ```package-version``` and ```kolli prune``` only keeps the directory with the greatest version number
* Services like FTP/HTTP servers must use the path to the current deployed version in their configuration. That means a web server should map an alias/vdir for URL */tenant* to *..../web-tenant-1.2.3.4/*, considering the kolli package name to be *web-tenant-1.2.3.4*

### Example

#### vanilla/kolli.json

    {
        "name": "vanilla",
        "version": "1.2.3.4",
        "files": [
           "iscream.exe",
           "iscream.exe.config",
           "vanilla.config"
        ]
    }
    
#### topping/kolli.json

    {
        "name": "topping",
        "version": "4.5.6.7",
        "files": [
            "topping.config"
        ]
        "dependencies": [
            { "vanilla": "1.2.3.4" }
        }
    }
    
#### Package cache contents

* vanilla-1.2.3.4.json
* vanilla-1.2.3.4.zip
* topping-4.5.6.7.json
* topping-4.5.6.7.zip

#### Installation command

Pre-condition: Empty directory<br/>
Usage: ```kolli install topping```<br/>
Expected result:
* Directory ```./topping-4.5.6.7``` gets created
* The  ```./topping-4.5.6.7``` directory contains the files ```iscream.exe iscream.exe.config vanilla.config topping.config```

#### Prune command

Pre-condition: Directory containing sub-directory ```topping-1.0.0.0``` and package cache with ```topping-2.0.0.0```<br/>
Usage: ```kolli install topping && kolli prune topping```<br/>
Expected result:
* Directory ```./topping-2.0.0.0``` is created (by ```kolli install``` command)
* Directory ```./topping-1.0.0.0``` is removed (by ```kolli prune``` command)

#### "Post-install scripts"

##### Resources, not commands

More thought of something like the [cron](https://docs.puppetlabs.com/references/latest/type.html#cron) resource or the [IIS module resources](https://github.com/puppet-community/puppet-iis) for Puppet, rather than [NPM scripts](https://docs.npmjs.com/misc/scripts).

## Ambitions

The ```kolli.json``` manifest file is not tied to any kind of operating system nor platform such as Ruby, Node, .Net etc. However, each implementation of Kolli is from our perspective should/could be targeted for use with a specific platform. That very specific scenario for our case is deploying pre-packaged .net applications (asp.net/iis app, console app, windows services) sourced from a build artifact repository requiring only a PowerShell session (possibly a WinRM session).





