function Repair-ModuleManifest
{
    param(
    # The Rule that flagged the problem
    [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
    [ValidateScript({
        if ($_ -isnot [Management.Automation.CommandInfo] -and
            $_ -isnot [Management.Automation.PSModuleInfo]
        ) {
            throw 'Must be a CommandInfo or a PSModuleInfo'            
        } 
        return $true
    })]
    [Object]$Rule,
    
    # The Problem
    [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
    [Management.Automation.ErrorRecord]
    $Problem,
    
    # The Item with the Problem
    [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
    [ValidateScript({
        if ($_ -isnot [Management.Automation.CommandInfo] -and
            $_ -isnot [Management.Automation.PSModuleInfo]
        ) {
            throw 'Must be a CommandInfo or a PSModuleInfo'            
        } 
        return $true
    })]
    [Object]$ItemWithProblem,
    
    [Switch]$NotInteractive
    )
    
    begin {                
function Write-PowerShellHashtable {
    <#
    .Synopsis
        Takes an existing Hashtable and creates the script you would need to embed to recreate the hashtable
    .Description
        Allows you to take a hashtable and create a hashtable you would embed into a script.
        Handles nested hashtables and automatically indents hashtables based off of how many times New-PowerShellHashtable is called
    .Parameter inputObject
        The hashtable to turn into a script
    .Parameter scriptBlock
        Determines if a string or a scriptblock is returned
    .Example
        # Corrects the presentation of a PowerShell hashtable
        @{Foo='Bar';Baz='Bing';Boo=@{Bam='Blang'}} | New-PowerShellHashtable
    .ReturnValue
        [string]
    .ReturnValue
        [ScriptBlock]   
    .Link
        about_hash_tables
    #>    
    param(
    [Parameter(Position=0,ValueFromPipelineByPropertyName=$true)]
    [PSObject]
    $InputObject,

    # Returns the content as a script block, rather than a string
    [switch]$scriptBlock
    )

    process {
        $callstack = @(Get-PSCallStack | 
            Where-Object { $_.Command -eq "Write-PowerShellHashtable"})
        $depth = $callStack.Count
        if ($inputObject -is [Hashtable]) {
            $scriptString = ""
            $indent = $depth * 4        
            $scriptString+= "@{
"
            foreach ($kv in $inputObject.GetEnumerator()) {
                $indent = ($depth + 1) * 4
                for($i=0;$i -lt $indent; $i++) {
                    $scriptString+=" "
                }
                $keyString = $kv.Key
                if ($keyString -notlike "*.*" -and $keyString -notlike "*-*") {
                    $scriptString+="$($kv.Key)="
                } else {
                    $scriptString+="'$($kv.Key)'="
                }
                
                $value = $kv.Value
                Write-Verbose "$value"
                if ($value -is [string]) {
                    $value = "'$value'"
                } elseif ($value -is [ScriptBlock]) {
                    $value = "{$value}"
                } elseif ($value -is [Object[]]) {
                    $oldOfs = $ofs 
                    $ofs = "',
$(' ' * ($indent + 4))'"
                    $value = "'$value'"
                    $ofs = $oldOfs
                } elseif ($value -is [Hashtable]) {
                    $value = "$(Write-PowerShellHashtable $value)"
                } else {
                    $value = "'$value'"
                }                                
               $scriptString+="$value
"
            }
            $indent = $depth * 4
            for($i=0;$i -lt $indent; $i++) {
                $scriptString+=" "
            }          
            $scriptString+= "}"     
            if ($scriptBlock) {
                [ScriptBlock]::Create($scriptString)
            } else {
                $scriptString
            }
        }           
   }
}       
    }
    
    process {    
        if ($Problem.FullyQualifiedErrorId -notlike "TestModuleManifestQuality.*") {
            return
        }
        
        
        $ModuleRoot = $ItemWithProblem | 
                Split-Path 
                
        $modulePath = $ItemWithProblem | 
                Split-Path -Leaf                
        
        $manifestPath = Join-Path $moduleRoot "$($ItemWithProblem.Name).psd1"
        
        if (Test-Path $ManifestPath) {
            $manifestContent = ([PowerShell]::Create().AddScript("
                `$executionContext.SessionState.LanguageMode = 'RestrictedLanguage'
                $([IO.File]::ReadAllText($ManifestPath))        
            ").Invoke())[0]
        
            $manifestMetaData = @{} + $manifestContent
        }

        $module = $ItemWithProblem

                
        if ($Problem.FullyQualifiedErrorId -like 'TestModuleManifestQuality.NoManifest*') {
            # Generate a Module Manifest with version 0.1, pointing to the path of the module                                    
            
            
            
            $newManifest = @"
    @{
        ModuleVersion='0.1'
        Guid='$([GUID]::NewGuid())'
        ModuleToProcess='$modulePath'
    }
"@
            [IO.File]::WriteAllText($ManifestPath, $newManifest)
            return TriedToFixProblem 'TestModuleManifestQuality.NoManifest'                        
        }     
        
        
        if (-not $manifestMetaData) { return }
                        
        if ($Problem.FullyQualifiedErrorId -like 'TestModuleManifestQuality.MissingFileList*') {
            # Take what's in the manifest, and add a file list
            
            if (-not $manifestMetaData) { 
                return CouldNotFixProblem 'TestModuleManifestQuality.MissingFileList'            
            } else {
                $manifestMetaData.FileList = $ModuleRoot | 
                    Get-ChildItem -Recurse |
                    Where-Object { -not $_.PSIsContainer } |
                    Select-Object -ExpandProperty FullName | 
                    ForEach-Object { $_.Replace("$ModuleRoot\", "") } 
                                
                Write-PowerShellHashtable -InputObject $manifestMetaData |
                    Set-Content $ManifestPath
                            
                return TriedToFixProblem 'TestModuleManifestQuality.MissingFileList' -FixRequiresRescan
            }
        }
        
        if ($Problem.FullyQualifiedErrorId -like 'TestModuleManifestQuality.MissingGuid*') {
            # Take what's in the manifest, and add a GUID
            
            $manifestMetaData.GUID = [GUID]::NewGuid()
                                
            Write-PowerShellHashtable -InputObject $manifestMetaData |
                Set-Content $ManifestPath
                        
            return TriedToFixProblem 'TestModuleManifestQuality.MissingGuid' -FixRequiresRescan               
        }
        
        if ($Problem.FullyQualifiedErrorId -like 'TestModuleManifestQuality.MissingCopyrightNotice*') {
            # Take what's in the manifest, and add a GUID
            
            $manifestMetaData.Copyright = "Copyright $((Get-Date).Year)"
                                
            Write-PowerShellHashtable -InputObject $manifestMetaData |
                Set-Content $ManifestPath
                        
            return TriedToFixProblem 'TestModuleManifestQuality.MissingCopyrightNotice' -FixRequiresRescan                 
        }
        
        if ($problem.FullyQualifiedErrorId -like 'TestModuleManifestQuality.MissingDescription*') {
            if ($NonInteractive) {
                # Could Fix, but can't because I can't ask
                return CouldNotFixProblem 'TestModuleManifestQuality.MissingDescription'                      
            } else {
                $description = Read-Host -Prompt "What Does the Module $($ItemWithProblem) do?"
                $manifestMetaData.Description = $description                     
                    
                Write-PowerShellHashtable -InputObject $manifestMetaData |
                    Set-Content $ManifestPath

                                                                       
                return TriedToFixProblem 'TestModuleManifestQuality.MissingDescription' -FixRequiresRescan
            }
            
        }
        
        if ($problem.FullyQualifiedErrorId -like 'TestModuleManifestQuality.MissingAuthor*') {
            if ($NonInteractive) {
                # Assume current user
                $manifestMetaData.Author = $env:UserName
            } else {
                $author = Read-Host -Prompt "Who wrote the module $module ?"
                $manifestMetaData.Author = $author                                         
            }

            Write-PowerShellHashtable -InputObject $manifestMetaData |
                Set-Content $ManifestPath

                                                                   
            return TriedToFixProblem 'TestModuleManifestQuality.MissingAuthor' -FixRequiresRescan
            
        }
    }
} 

# SIG # Begin signature block
# MIINGAYJKoZIhvcNAQcCoIINCTCCDQUCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUCziw9g4AXy3PinSZQHASceKK
# nMmgggpaMIIFIjCCBAqgAwIBAgIQAupQIxjzGlMFoE+9rHncOTANBgkqhkiG9w0B
# AQsFADByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYD
# VQQLExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFz
# c3VyZWQgSUQgQ29kZSBTaWduaW5nIENBMB4XDTE0MDcxNzAwMDAwMFoXDTE1MDcy
# MjEyMDAwMFowaTELMAkGA1UEBhMCQ0ExCzAJBgNVBAgTAk9OMREwDwYDVQQHEwhI
# YW1pbHRvbjEcMBoGA1UEChMTRGF2aWQgV2F5bmUgSm9obnNvbjEcMBoGA1UEAxMT
# RGF2aWQgV2F5bmUgSm9obnNvbjCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoC
# ggEBAM3+T+61MoGxUHnoK0b2GgO17e0sW8ugwAH966Z1JIzQvXFa707SZvTJgmra
# ZsCn9fU+i9KhC0nUpA4hAv/b1MCeqGq1O0f3ffiwsxhTG3Z4J8mEl5eSdcRgeb+1
# jaKI3oHkbX+zxqOLSaRSQPn3XygMAfrcD/QI4vsx8o2lTUsPJEy2c0z57e1VzWlq
# KHqo18lVxDq/YF+fKCAJL57zjXSBPPmb/sNj8VgoxXS6EUAC5c3tb+CJfNP2U9vV
# oy5YeUP9bNwq2aXkW0+xZIipbJonZwN+bIsbgCC5eb2aqapBgJrgds8cw8WKiZvy
# Zx2qT7hy9HT+LUOI0l0K0w31dF8CAwEAAaOCAbswggG3MB8GA1UdIwQYMBaAFFrE
# uXsqCqOl6nEDwGD5LfZldQ5YMB0GA1UdDgQWBBTnMIKoGnZIswBx8nuJckJGsFDU
# lDAOBgNVHQ8BAf8EBAMCB4AwEwYDVR0lBAwwCgYIKwYBBQUHAwMwdwYDVR0fBHAw
# bjA1oDOgMYYvaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL3NoYTItYXNzdXJlZC1j
# cy1nMS5jcmwwNaAzoDGGL2h0dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9zaGEyLWFz
# c3VyZWQtY3MtZzEuY3JsMEIGA1UdIAQ7MDkwNwYJYIZIAYb9bAMBMCowKAYIKwYB
# BQUHAgEWHGh0dHBzOi8vd3d3LmRpZ2ljZXJ0LmNvbS9DUFMwgYQGCCsGAQUFBwEB
# BHgwdjAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tME4GCCsG
# AQUFBzAChkJodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRTSEEy
# QXNzdXJlZElEQ29kZVNpZ25pbmdDQS5jcnQwDAYDVR0TAQH/BAIwADANBgkqhkiG
# 9w0BAQsFAAOCAQEAVlkBmOEKRw2O66aloy9tNoQNIWz3AduGBfnf9gvyRFvSuKm0
# Zq3A6lRej8FPxC5Kbwswxtl2L/pjyrlYzUs+XuYe9Ua9YMIdhbyjUol4Z46jhOrO
# TDl18txaoNpGE9JXo8SLZHibwz97H3+paRm16aygM5R3uQ0xSQ1NFqDJ53YRvOqT
# 60/tF9E8zNx4hOH1lw1CDPu0K3nL2PusLUVzCpwNunQzGoZfVtlnV2x4EgXyZ9G1
# x4odcYZwKpkWPKA4bWAG+Img5+dgGEOqoUHh4jm2IKijm1jz7BRcJUMAwa2Qcbc2
# ttQbSj/7xZXL470VG3WjLWNWkRaRQAkzOajhpTCCBTAwggQYoAMCAQICEAQJGBtf
# 1btmdVNDtW+VUAgwDQYJKoZIhvcNAQELBQAwZTELMAkGA1UEBhMCVVMxFTATBgNV
# BAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEkMCIG
# A1UEAxMbRGlnaUNlcnQgQXNzdXJlZCBJRCBSb290IENBMB4XDTEzMTAyMjEyMDAw
# MFoXDTI4MTAyMjEyMDAwMFowcjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lD
# ZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGln
# aUNlcnQgU0hBMiBBc3N1cmVkIElEIENvZGUgU2lnbmluZyBDQTCCASIwDQYJKoZI
# hvcNAQEBBQADggEPADCCAQoCggEBAPjTsxx/DhGvZ3cH0wsxSRnP0PtFmbE620T1
# f+Wondsy13Hqdp0FLreP+pJDwKX5idQ3Gde2qvCchqXYJawOeSg6funRZ9PG+ykn
# x9N7I5TkkSOWkHeC+aGEI2YSVDNQdLEoJrskacLCUvIUZ4qJRdQtoaPpiCwgla4c
# SocI3wz14k1gGL6qxLKucDFmM3E+rHCiq85/6XzLkqHlOzEcz+ryCuRXu0q16XTm
# K/5sy350OTYNkO/ktU6kqepqCquE86xnTrXE94zRICUj6whkPlKWwfIPEvTFjg/B
# ougsUfdzvL2FsWKDc0GCB+Q4i2pzINAPZHM8np+mM6n9Gd8lk9ECAwEAAaOCAc0w
# ggHJMBIGA1UdEwEB/wQIMAYBAf8CAQAwDgYDVR0PAQH/BAQDAgGGMBMGA1UdJQQM
# MAoGCCsGAQUFBwMDMHkGCCsGAQUFBwEBBG0wazAkBggrBgEFBQcwAYYYaHR0cDov
# L29jc3AuZGlnaWNlcnQuY29tMEMGCCsGAQUFBzAChjdodHRwOi8vY2FjZXJ0cy5k
# aWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3J0MIGBBgNVHR8E
# ejB4MDqgOKA2hjRodHRwOi8vY3JsNC5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1
# cmVkSURSb290Q0EuY3JsMDqgOKA2hjRodHRwOi8vY3JsMy5kaWdpY2VydC5jb20v
# RGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3JsME8GA1UdIARIMEYwOAYKYIZIAYb9
# bAACBDAqMCgGCCsGAQUFBwIBFhxodHRwczovL3d3dy5kaWdpY2VydC5jb20vQ1BT
# MAoGCGCGSAGG/WwDMB0GA1UdDgQWBBRaxLl7KgqjpepxA8Bg+S32ZXUOWDAfBgNV
# HSMEGDAWgBRF66Kv9JLLgjEtUYunpyGd823IDzANBgkqhkiG9w0BAQsFAAOCAQEA
# PuwNWiSz8yLRFcgsfCUpdqgdXRwtOhrE7zBh134LYP3DPQ/Er4v97yrfIFU3sOH2
# 0ZJ1D1G0bqWOWuJeJIFOEKTuP3GOYw4TS63XX0R58zYUBor3nEZOXP+QsRsHDpEV
# +7qvtVHCjSSuJMbHJyqhKSgaOnEoAjwukaPAJRHinBRHoXpoaK+bp1wgXNlxsQyP
# u6j4xRJon89Ay0BEpRPw5mQMJQhCMrI2iiQC/i9yfhzXSUWW6Fkd6fp0ZGuy62ZD
# 2rOwjNXpDd32ASDOmTFjPQgaGLOBm0/GkxAG/AeB+ova+YJJ92JuoVP6EpQYhS6S
# kepobEQysmah5xikmmRR7zGCAigwggIkAgEBMIGGMHIxCzAJBgNVBAYTAlVTMRUw
# EwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20x
# MTAvBgNVBAMTKERpZ2lDZXJ0IFNIQTIgQXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcg
# Q0ECEALqUCMY8xpTBaBPvax53DkwCQYFKw4DAhoFAKB4MBgGCisGAQQBgjcCAQwx
# CjAIoAKAAKECgAAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGC
# NwIBCzEOMAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFMUt9qHsBfMC1ptn
# v61Anc4qbpKsMA0GCSqGSIb3DQEBAQUABIIBAGyt6vrO9q3bUk6Nt+hK8/wMb14q
# eR/Ymept/Xqa2CBsaUDzks6wa9Bzkm46oR1+v7abShY1t7ezQBVxQI8c4wcmlPzW
# HVf2QFHK0ORucIcU99kroG9lO5H6KCMLaEVPQwENWrGhXF9CqZ1Viz65nzT3RZKB
# 6NDKLdjr/Gacvk1AeRbbfpDS5NNw0LRfsIYoUPCv5Kt/NZMZpqJPTRsykZGC0fRU
# Pbb6yHhlXyAWxa2sDyojl8yUywlulMbYp1NRdrttRzzFU7QHzIwYWPdyii9wsMdE
# 83Aew7mypye+bnWGMsg/wa4bNAk2GQYUdsJMwWr1lC8DgqdfMW1CFNDiwgA=
# SIG # End signature block
