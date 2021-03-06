#%powershell1.0%
#
# File: web-utils.ps1
# Description: Utility functions for parsing and downloading from windows.php.net/downloads/snaps
#
## From http://powershelljson.codeplex.com/
#
Function ConvertFrom-JSON {
    param(
        $json,
        [switch]$raw  
    )

    Begin
    {
    	$script:startStringState = $false
    	$script:valueState = $false
    	$script:arrayState = $false	
    	$script:saveArrayState = $false

    	function scan-characters ($c) {
    		switch -regex ($c)
    		{
    			"{" { 
    				"(New-Object PSObject "
    				$script:saveArrayState=$script:arrayState
    				$script:valueState=$script:startStringState=$script:arrayState=$false				
    			    }
    			"}" { ")"; $script:arrayState=$script:saveArrayState }

    			'"' {
    				if($script:startStringState -eq $false -and $script:valueState -eq $false -and $script:arrayState -eq $false) {
    					'| Add-Member -Passthru NoteProperty "'
    				}
    				else { '"' }
    				$script:startStringState = $true
    			}

    			"[a-z0-9A-Z@. ]" { $c }

    			":" {" " ;$script:valueState = $true}
    			"," {
    				if($script:arrayState) { "," }
    				else { $script:valueState = $false; $script:startStringState = $false }
    			}	
    			"\[" { "@("; $script:arrayState = $true }
    			"\]" { ")"; $script:arrayState = $false }
    			"[\t\r\n]" {}
    		}
    	}
    	
    	function parse($target)
    	{
    		$result = ""
    		ForEach($c in $target.ToCharArray()) {	
    			$result += scan-characters $c
    		}
    		$result 	
    	}
    }

    Process { 
        if($_) { $result = parse $_ } 
    }

    End { 
        If($json) { $result = parse $json }

        If(-Not $raw) {
            $result | Invoke-Expression
        } else {
            $result 
        }
    }
}

#
## Description: Parse and download json from windows.php.net/downloads/snaps
#
Function find-latest-build ( $ver="" )  {

	$baseurl = "http://windows.php.net/downloads/snaps"
	if ( $ver -eq "5.3" )  {
		$json = "$baseurl/php-5.3/php-5.3.json"
	}
	elseif ( $ver -eq "5.4" )  {
		$json = "$baseurl/php-5.4/php-5.4.json"
	}
	elseif ( $ver -eq "5.5" )  {
		$json = "$baseurl/php-5.5/php-5.5.json"
	}
	elseif ( $ver -eq "master" )  {
		$json = "$baseurl/master/master.json"
	}
	else  {
		return $false
	}

	## Example JSON: {"revision_last":318914,"revision_previous":318888,"revision_last_exported":318914,"builds":["nts-windows-vc9-x86","ts-windows-vc9-x86"]}
	$json = (new-object net.webclient).DownloadString("$json")
	$json = $json | ConvertFrom-JSON

	# Build must include nts-windows-vc9-x86 and ts-windows-vc9-x86
	$jsonfiles = @()
	if ( (($json.builds) -match "ntswindowsvc9x86") -and (($json.builds) -match "tswindowsvc9x86") )  {
		$jsonfiles = @("nts-windows-vc9-x86.json", "ts-windows-vc9-x86.json")
	}
	elseif ( (($json.builds) -match "ntswindowsvc11x86") -and (($json.builds) -match "tswindowsvc11x86") )  {
		$jsonfiles = @("nts-windows-vc11-x86.json", "ts-windows-vc11-x86.json")
	}
	elseif ( (($json.builds) -match "ntswindowsvc11x64") -and (($json.builds) -match "tswindowsvc11x64") )  {
		$jsonfiles = @("nts-windows-vc11-x64.json", "ts-windows-vc11-x64.json")
	}
	else  {
		return $false
	}

	## Check build info in JSON
	foreach ( $rev in @($json.revisionlast,$json.revisionprevious) )  {
		$error = $false
		$rev = $rev.substring(0,7) # git
		$builddir = "$baseurl/php-$ver/r"+$rev
		$script:REVISION = "r"+$rev
		Foreach ( $statfile in $jsonfiles )  {
			$buildstat = (new-object net.webclient).DownloadString("$builddir/$statfile")
			if ( $buildstat -eq "" )  {
				$error = $true
				break
			}
			$buildstat = $buildstat | ConvertFrom-JSON
			if ( ($buildstat.hasphppkg -ne 'true') -or ($buildstat.stats.error -ne "0") )  {
				$error = $true
				break
			}
		}
		if ( $error -eq $false )  {
			return $builddir
		}
	}
}	

#
## Description: Download .zip from windows.php.net, return physical path to .zip or $false
#
Function download-build ( $url="" )  {
	if ( $url -eq "" )  {
		return $false
	}

	$basedir = $script:BaseBuildDir
	$location = @()
	switch( $url )  {
		{ ($_ -match 'r[a-z0-9]{7}\/?$') -and ($_ -notmatch 'r[a-z0-9]{7}\.zip$') } {  ## 5.3/5.4/5.5 Snapshot build
			if ( $_ -match "php\-5\.\d" )  {
				$ver = $matches[0] -replace 'php-', ''
			}
			else  {
				$ver = 'master'
			}

			logger "download-build(): Downloading PHP, $_/php-$ver-ts-windows-vc9-x86-$REVISION.zip"
			(new-object net.webclient).DownloadFile("$_/php-$ver-ts-windows-vc9-x86-$REVISION.zip", "$basedir/php-$ver-ts-windows-vc9-x86-$REVISION.zip")
			if ( (test-path "$basedir/php-$ver-ts-windows-vc9-x86-$REVISION.zip") -eq $false )  {
				return $false
			}

			logger "download-build(): Downloading PHP, $_/php-$ver-nts-windows-vc9-x86-$REVISION.zip"
			(new-object net.webclient).DownloadFile("$_/php-$ver-nts-windows-vc9-x86-$REVISION.zip", "$basedir/php-$ver-nts-windows-vc9-x86-$REVISION.zip")
			if ( (test-path "$basedir/php-$ver-nts-windows-vc9-x86-$REVISION.zip") -eq $false )  {
				return $false
			}

			$location += "$basedir/php-$ver-ts-windows-vc9-x86-$REVISION.zip"
			$location += "$basedir/php-$ver-nts-windows-vc9-x86-$REVISION.zip"
			return $location
		} 

		{ $_ -match "http:\/\/" } {  ## Explicit URL to .zip file
			$filename = ( $_ -match "\/[\w\.\-]+$" )
			$filename = $matches[0]

			logger "download-build(): Downloading PHP, $_"
			(new-object net.webclient).DownloadFile("$_", "$basedir/$filename")
			if ( (test-path "$basedir/$filename") -eq $false )  {
				return $false
			}
			$location = $basedir+$filename
			return $location
		}

		default  {  return $false  }
	}
}

#
## Description: Return URL to the PHP .zip files
## $phpurl should be one of "5.3" or "5.4," etc.
#
Function php-getsnapbuilds ( $phpurl="" )  {
	if ( $phpurl -eq "" )  {  return $false }

	## Find revision number
	$phpurl = find-latest-build("$phpurl")
	if ( $phpurl -ne $false )  {
		logger "php-getsnapbuilds(): Found snapshot build: $phpurl"
		$phpurl = download-build("$phpurl")
		if ( $phpurl -eq $false )  {
			return $false
		}
		return $phpurl
	}
	else  {
		return $false
	}
}
