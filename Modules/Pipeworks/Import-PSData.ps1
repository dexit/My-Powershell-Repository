function Import-PSData
{
    <#
    .Synopsis
        Imports PSData sections
    .Description
        Imports files or strings containing PSData sections, and converts nested hashtables into nested PSObjects.
    .Example
        Get-Web -Url http://www.youtube.com/watch?v=xPRC3EDR_GU -AsMicrodata -ItemType http://schema.org/VideoObject | 
            Export-PSData .\PipeworksQuickstart.video.psd1
    .Example
        @{a="b";c=@{d="E"}} | 
            Import-PSData | 
            Select-Object -ExpandProperty c | 
            Select-Object -ExpandProperty D
    .Link
        Export-PSData
    #>
    
    [CmdletBinding(DefaultParameterSetName='FromFile')]  
    param(
    # A file containing PSData
    [Parameter(Mandatory=$true,
        Position=0,
        ParameterSetName='FromFile',
        ValueFromPipelineByPropertyName=$true)]
    [Alias('Fullname')]
    [string]$FilePath,
    
    # A string in data language mode.  
    [Parameter(Mandatory=$true,
        ParameterSetName='FromString',
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true)]
    [string]$DataString,

    # A compressed string
    [Parameter(Mandatory=$true,
        ParameterSetName='FromCompressedString',
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true)]
    [string]$CompressedString,
    
    # A hashtable
    [Parameter(Mandatory=$true,
        ParameterSetName='FromHashtable',
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true)]
    [Hashtable]$Hashtable,
    
    # Any commands allowed in the file, string, or compressedstring
    [Parameter(ParameterSetName='FromFile',
        ValueFromPipelineByPropertyName=$true)]
    [Parameter(ParameterSetName='FromCompressedString',
        ValueFromPipelineByPropertyName=$true)]
    [Parameter(ParameterSetName='FromHashtable',
        ValueFromPipelineByPropertyName=$true)]
    [string[]]$AllowCommand
    )
    
    process {
        if ($psCmdlet.ParameterSetName -eq 'FromFile') {
            foreach ($resolvedFile in $ExecutionContext.SessionState.Path.GetResolvedPSPathFromPSPath($FilePath)) {
                $DataString = [IO.File]::ReadAllText($resolvedFile)
            }
        } elseif ($psCmdlet.ParameterSetName -eq 'FromCompressedString') {
            try {
                $DataString = Expand-Data -CompressedData $CompressedString
            } catch {
            }
        }
        
        $supportedCommandSection = if ($allowCommand ){
            "-supportedCommand $($allowCommand -join ',')"  
        } else {
            ""
        }
        
        if ('FromFile', 'FromString' -contains $psCmdlet.ParameterSetName) {
        
        
            $dataScriptBlock = [ScriptBlock]::Create($DataString)
            $dataLanguageScriptBlock = [ScriptBlock]::Create("data $supportedCommandSection { $dataScriptBlock }")
            foreach ($result in (& $dataLanguageScriptBlock)) {
                if ($result -is [Hashtable]) {
                    Import-PSData -Hashtable $result 
                } else {
                    $result
                }     
            }
        }
        
        if ($psCmdlet.ParameterSetName -eq 'FromHashtable') {
            $Objectcopy = @{} + $Hashtable
            if ($Objectcopy.PSTypeName) {
                $ObjecttypeName = $Objectcopy.PSTypeName
                $Objectcopy.Remove('PSTypeName')
            }
            
            foreach ($kv in @($Objectcopy.GetEnumerator())) {
                if ($kv.Value -is [Hashtable]) {
                    $Objectcopy[$kv.Key] = Import-PSData -Hashtable $hashtable[$kv.Key]
                } elseif ($kv.Value -as [Hashtable[]]) {
                    $Objectcopy[$kv.Key] = foreach ($ht in $kv.Value) {
                        Import-PSData -Hashtable $ht
                    } 
                }
            }
            
            
            New-Object PSObject -Property $Objectcopy | 
                ForEach-Object {                
                    $_.pstypenames.clear()
                    foreach ($inTypeName in $ObjecttypeName) {
                        if (-not $inTypeName) {continue }
                        
                        $null = $_.pstypenames.add($inTypeName)
                    }
                    if (-not $_.pstypenames) {
                        $_.pstypenames.add('PropertyBag')
                    }
                    $_
                }
        }
        
        
        
    }
} 

# SIG # Begin signature block
# MIINGAYJKoZIhvcNAQcCoIINCTCCDQUCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUpPGJ2iJD77xPBW71vyCF7RUE
# UeOgggpaMIIFIjCCBAqgAwIBAgIQAupQIxjzGlMFoE+9rHncOTANBgkqhkiG9w0B
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
# NwIBCzEOMAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFEXKd54eYiFn7cWO
# r/dvlQ/SkffmMA0GCSqGSIb3DQEBAQUABIIBAAnDa78C9G+zHc5/IP6h0ctzXw9u
# 89bZ9BgQ9vbn/z/w+1KUN3waNnPAxKmXzo5Mh3Rt5M/ZHQonklDxe9qq3rNYa4mv
# rib7Ge6D8+j1f7kmA8kV7B77qsXXWmDq3TlHodZEsHOOpB/WZ2fvYERvKyPtut81
# ZaF4jMSS1OQ3TD9EgZ3wqVaxjb3sVfPfmJWFKS5MILbbWP5VNwm1o0xx1xws0nRy
# 5gtxjPMwaYs7aVwu/R9wf6LCAs+dBT+65ESttY4hBGnY3yLBTv/F01YXdOsRn5Ua
# Q+rBtGf2XsDaP7Rg7Ry207NwcGvO/ODU0jvyEZfCNgwigvfP4iVH418TgMs=
# SIG # End signature block
