function Add-Icicle
{
    <#
    .Synopsis
        Adds an Icicle to the ISE
    .Description
        Adds an icicle to the ISE.  Icicles are mini-apps for the PowerShell ISE.
    .Link
        Import-Icicle
    .Example
        Add-Icicle -Horizontal -Name Clock -Screen { 
            New-Border -Child {
                New-Label "$(Get-Date | Out-String)" -FontSize 24  -FontFamily 'Lucida Console'
            }
        } -DataUpdate { 
            Get-date 
        } -UiUpdate {
            $this.Content.Child.Content = $args | Out-String
        } -UpdateEvery "0:0:1" 
    .Example
        Add-Icicle -Command (Get-Command Get-Process)
    #>
    [CmdletBinding(DefaultParameterSetName='Site')]
    param(
    # The name of the icicle
    [Parameter(ParameterSetName='Command')]
    [Parameter(Mandatory=$true,ParameterSetName='Site',ValueFromPipelineByPropertyName=$true)]
    [Parameter(Mandatory=$true,ParameterSetName='Screen',ValueFromPipelineByPropertyName=$true)]
    [Parameter(Mandatory=$true,ParameterSetName='UpdatedScreen',ValueFromPipelineByPropertyName=$true)]
    [Parameter(Mandatory=$true,ParameterSetName='UpdatedSite',ValueFromPipelineByPropertyName=$true)]
    [string]
    $Name,    

    # The url to display in the icicle
    [Parameter(Mandatory=$true, ParameterSetName='Site',ValueFromPipelineByPropertyName=$true)]
    [Uri]
    $Site,

    # The screen for the icicle
    [Parameter(Mandatory=$true, ParameterSetName='Screen')]
    [Parameter(Mandatory=$true, ParameterSetName='UpdatedScreen')]
    [ScriptBlock]
    $Screen,

    # The command to use for the icicle.  
    # The icicle will collect input for this command and run that command in the main runspace.
    [Parameter(Mandatory=$true, ParameterSetName='Command',ValueFromPipelineByPropertyName=$true, ValueFromPipeline=$true)]
    [Management.Automation.CommandMetaData]
    $Command,

    # A list of parameters to hide when displaying the command within an Icicle
    [Parameter(ParameterSetName='Command',ValueFromPipelineByPropertyName=$true)]
    [string[]]
    $HideParameter,


    # The command to use for the icicle.  
    # The icicle will collect input for this command and run that command in the main runspace.
    [Parameter(Mandatory=$true, ParameterSetName='Module', ValueFromPipeline=$true)]
    [Management.Automation.PSModuleInfo]
    $Module,

    # The data update.  This script will be run in the runspace that launched the icicle every UpdateEvery
    [Parameter(Mandatory=$true, ParameterSetName='UpdatedScreen')]
    [ScriptBlock]    
    $DataUpdate,

    # The UI update.  This script will be run in the UI runspace, and can access the results from the dataupdate in $args
    [Parameter(Mandatory=$true, ParameterSetName='UpdatedScreen')]
    [ScriptBlock]
    $UiUpdate,
    
    # The frequency of the update.
    [Timespan]
    [Alias('UpdateFrequency')]
    [ValidateRange("00:00:01", "00:01:00")]
    $UpdateEvery,

    # If set, will not show the icicle when it is created.
    [Switch]
    $DoNotShow,

    # If set, the icicle  will be horizontal.
    [Switch]
    $Horizontal,

    # If set, will remove an existing icicle before adding this one.
    [Switch]$Force,

    # If set, will make a shortcut key for the icicle.  If the first key has a conflict, the next key will be used.
    [string[]]$ShortcutKey,

    # If set, will update the Icicle whenever the files change
    [switch]$UpdateOnFileChange,

    # If set, will update the Icicle whenever an add on is added or removed
    [switch]$UpdateOnAddOnChange
    )
            
    process { 

        #region Create Icicle
        $addonParams = @{
            DisplayName=$Name
            DoNotshow=$DoNotshow
            Force=$Force
        }
        if ($Horizontal) {
            $addonParams["AddHorizontally"] = $true
        } else {
            $addonParams["AddVertically"] = $true
        }
        if ($psCmdlet.ParameterSetName -like "*Screen*") {
            $addonParams.ScriptBlock= $screen
        } elseif ($pscmdlet.ParameterSetName -like "*Site*") {
        
            $addonParams.ScriptBlock = [ScriptBlock]::Create("
            New-WebBrowser  -On_Loaded {
                `$fiComWebBrowser = `$this.GetType().GetField('_axIWebBrowser2', 'Instance,NonPublic')
                if (-not `$fiComWebBrowser) { return } 
    
                `$objComWebBrowser = `$fiComWebBrowser.GetValue(`$this);
                if (-not `$objComWebBrowser) { return } 
        
                
                `$arr = new-Object Object[] 1
                `$arr[0] = `$true
                `$objComWebBrowser.GetType().InvokeMember('Silent', [Reflection.BindingFlags]'SetProperty', `$null, `$objComWebBrowser, `$arr)

            } -Source '$site'            
            ")
            if ($psCmdlet.ParameterSetName -like "*update*") {
                $uiUpdate = {
                    $this.Content.Source = $this.Content.Source
                } 
            }
        } elseif ($pscmdlet.ParameterSetName -eq 'Module') {
            $cmds = @($module.ExportedFunctions.Values) + @($module.ExportedCmdlets.Values)
            $moduleRoot = Split-Path $Module.Path
            if (Test-Path "$moduleRoot\$($module.Name).pipeworks.psd1") {
                # If there's a pipeworks manifest, create Icicles for all entries in WebCommand
                $pipeworksManifestContent = [IO.File]::ReadAllText("$moduleRoot\$($module.Name).pipeworks.psd1")
                $pipeworksManifest = "data { $([ScriptBlock]::Create($pipeworksManifestContent)) }" 
            } else {
                foreach ($cmd in $cmds) {
                    Add-Icicle -command $cmd -DoNotShow
                }
            }
            # Create a horizontal icicle to show each command

        } elseif ($psCmdlet.ParameterSetName -eq 'Command') {
            $psBoundParameters.DisplayName = $Command.Name
            $name = $command.Name    
            $safecommandName = $command.Name.Replace("-", "")
            $addonParams.DisplayName = $command.Name
            $addonParams.ScriptBlock = [ScriptBlock]::Create(@"
$input = . Get-WebInput -Control $this -CommandMetaData $cmds
New-Grid -Rows 1* -RoutedEvent @{
    [Windows.Controls.Button]::ClickEvent = {
        
        try {            
            if (`$_.Source.Name -ne '$($command.Name.Replace("-", "") + "_Invoke")') {
                return
            }
            `$value = Get-ChildControl -Control `$this -OutputNamedControl
            foreach (`$kv in @(`$value.GetEnumerator())) {
                if ((`$kv.Key -notlike "${SafeCommandName}_*")) {
                    `$value.Remove(`$kv.Key)
                }
            }

            foreach (`$kv in @(`$value.GetEnumerator())) {
                if (`$kv.Value.Text) {
                    `$value[`$kv.Key] = `$kv.Value.Text
                } elseif (`$kv.Value.SelectedItems) {
                    `$value[`$kv.Key] = `$kv.Value.SelectedItems
                } elseif (`$kv.Value -is [Windows.Controls.Checkbox] -and `$kv.Value.IsChecked) {
                    `$value[`$kv.Key] = `$kv.Value.IsChecked
                } else {
                    `$value.Remove(`$kv.Key)
                }
            }

            foreach (`$kv in @(`$value.GetEnumerator())) {
                `$newKey = `$kv.Key.Replace("${SafeCommandName}_", "")
                `$newValue = `$kv.Value
                `$value.Remove(`$kv.Key)
                `$value.`$newKey = `$newValue
            }

            `$mainRunspace = [Windows.Window]::getWindow(`$this).Resources.MainRunspace
            if (`$value) {                
                
                
                if (`$mainRunspace.RunspaceAvailability -ne 'Busy') {
                    `$mainRunspace.SessionStateProxy.SetVariable("IcicleCommandParameter", `$value) 
                }
            }
            
            if (`$mainRunspace.RunspaceAvailability -ne 'Busy') {
                `$this.Parent.HostObject.CurrentPowerShellTab.Invoke({
                    if (`$IcicleCommandParameter ) {
                        $($command.Name) @IcicleCommandParameter 
                    } else {
                        'Parameters Not Found'
                    }
                    #Remove-Variable IcicleCommandParameter 
                })
            }
        } catch {
            [Windows.MessageBox]::Show("`$(`$_ | Out-String)", "Error")
        }
    }
} -ControlName '$($Command.Name)' -Children {
    [Windows.Markup.XamlReader]::Parse(@'
$(Request-CommandInput -CommandMetaData $command -Platform WPF)
'@)
}
"@)
        }
        if ($Force -and (Get-Icicle $Name)) {
            Get-Icicle $Name | 
                Remove-Icicle -Confirm:$false
            
        }
        if ($shortcutKey) {
            $addonParams.shortcutKey  =$shortcutKey
        }
        ConvertTo-ISEAddOn @addonParams
        #endregion

        

        $processUiUpdate = {
    
        if ($horizontal) {
                $list = $psise.CurrentPowerShellTab.HorizontalAddOnTools   
        } else {
            $list = $psise.CurrentPowerShellTab.VerticalAddOnTools
        }

        $list | 
            Where-Object {
                $_.Name -eq $UpdateName
            } |
            ForEach-Object {
                 
                $_.Control.InvokeScript($uiUpdate, @($outputValue))
            }
     
        }
        if (("$DataUpdate" -or "$UiUpdate") -and 
            $updateEvery.totalMilliseconds) { 
            $timer = 
                New-Object Timers.Timer -Property @{
                    Interval = $UpdateEvery.TotalMilliseconds
                }


            $fullaction = [ScriptBlock]::Create("
`$outputValue = & {
`$global:ProgressPreference = 'SilentlyContinue'
$dataupdate
`$global:ProgressPreference = 'Continue'
}
`$UiUpdate = {$UiUpdate}
`$horizontal = $(if ($horizontal) {'$true' } else { '$false' })
`$updateName = '$Name'
" + $processUiUpdate )

            #region Update Actions


        if ($UpdateOnToggleScriptView) {
            $tabSwitchAction = [ScriptBlock]::Create("" + {
                if ($EventArgs.PropertyName -notlike "*expand*") {
                    return
                }
                
            } + $fullAction)

            $null = 
                Register-ObjectEvent -SourceIdentifier "${Name}IseScriptView" -InputObject $psise.CurrentPowerShellTab -EventName PropertyChanged -Action $tabSwitchAction  

        }


        if ($UpdateOnAddOnChange) {

            $null = 
                Register-ObjectEvent -SourceIdentifier "${Name}IseVerticalAddOnsChanged" -InputObject $psise.CurrentPowerShellTab.VerticalAddOnTools -EventName CollectionChanged -Action $fullAction

            $null = 
                Register-ObjectEvent -SourceIdentifier "${Name}IseHorizontalAddOnsChanged" -InputObject $psise.CurrentPowerShellTab.HorizontalAddOnTools -EventName CollectionChanged -Action $fullAction

        }

        $runSoon = New-Object Timers.Timer -Property @{
            AutoReset = $false 
            Interval = ([Timespan]"0:0:0.5").TotalMilliseconds
        }
        $null = 
            Register-ObjectEvent -SourceIdentifier "${Name}FirstUpdate" -InputObject $runSoon  -EventName Elapsed -Action $fullaction 
        $runsoon.Start()
        
        
        if ($fullAction -and $UpdateEvery.totalMilliseconds) { 
            

            # Old tricks from task scheduler: If everything has the exact same update interval, the program will seem to logjam
            # Therefore, randomly offset by 1/8th of a second to avoid some collisions
            $jitteredInterval = $UpdateEvery.TotalMilliseconds + (Get-Random -Maximum 250) - 125

            $timer = 
                New-Object Timers.Timer -Property @{
                    Interval = $jitteredInterval
                }


            
            #region Update Actions
            $null = 
                Register-ObjectEvent -SourceIdentifier "${Name}RegularUpdate" -InputObject $timer -EventName Elapsed -Action $fullaction 
            $timer.Start()

            # Run soon, so it "feels" right


            # Run when the users switches tabs
            #endregion

        }
    }
    $syncAction = [ScriptBlock]::Create(@"

`$outputValue = `$psise, ([Runspace]::DefaultRunspace)
`$horizontal = $(if ($horizontal) {'$true' } else { '$false' })
`$uiUpdate = {
    
    [Windows.Window]::getWindow(`$this).Resources.ISE = (`$args)[0]
    [Windows.Window]::getWindow(`$this).Resources.MainRunspace = (`$args)[1]
}
`$updateName = '$Name'
"@ + $processUiUpdate )

        
    $SyncIse= New-Object Timers.Timer -Property @{
        Interval = ([Timespan]"0:0:2.$(Get-Random -Max 20)").TotalMilliseconds
    }
    $null = 
        Register-ObjectEvent -SourceIdentifier "${Name}SyncIse" -InputObject $SyncIse -EventName Elapsed -Action $syncAction 
    $SyncIse.Start()

}
}
# SIG # Begin signature block
# MIINGAYJKoZIhvcNAQcCoIINCTCCDQUCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUXpSRlKzHywVGTYgL1I1WOpR1
# h22gggpaMIIFIjCCBAqgAwIBAgIQAupQIxjzGlMFoE+9rHncOTANBgkqhkiG9w0B
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
# NwIBCzEOMAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFJW4E5c0Iq8xkX1N
# t/U8ZtKb6oUoMA0GCSqGSIb3DQEBAQUABIIBABFqqmo7IvUYRuxRYOh1+Riu4rHL
# 5FuJlOzACEIhkcFg914PcUgwjBa4iT9eNAE5JApMQueDcByO6jQ+klkrOee8zPGL
# 2U9mv35SPyuW9Wv5rH9W81gwTx6zqjizQqULNmef+gMS2iOVsHJLMHAlpJbip2FK
# kre4aMbHGc3qfei9/EhvfVbAGjCO694Id4RvsLp4FxvESYWeXdAHWrcgv00GlEWR
# aQ/TlwJuTKbenYrtMDZd9lnIaJLkTI0SHLpXJc1UDzV3+aC1wjbk9u1e7BkYg32/
# BGPaFEJmFSen8Edz27u1xEimfeJ1JT20qmHI60luLfeLt3lSBhSJSBaQANA=
# SIG # End signature block
