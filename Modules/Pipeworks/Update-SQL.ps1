function Update-Sql
{
    <#
    .Synopsis
        Updates a SQL table
    .Description
        Inserts new content into a SQL table, or updates the existing contents of a SQL table
    #>
    param(
    # The name of the SQL table
    [Parameter(Mandatory=$true)]
    [string]$TableName,

    # The Input Object
    [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
    [PSObject]
    $InputObject,

    # A List of Properties to add to the database.  If omitted, all properties will be added (except those excluded with -ExcludeProperty)
    
    [string[]]
    $Property,

    # A List of Properties to exclude from the database.  If omitted, all properties (or the properties specified with the -Property parameter) will be added
    
    [string[]]
    $ExcludeProperty,
    
    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [string]
    $RowKey,
    
    [ValidateSet('Guid', 'Hex', 'SmallHex', 'Sequential', 'Named', 'Parameter')]
    [string]$KeyType  = 'Named',

    # A lookup table containing SQL data types
    [Hashtable[]]
    $ColumnType,


    # A lookup table containing the real SQL column names for an object
    [Hashtable[]]
    $ColumnAlias,

    # If set, will force the creation of a table.
    # If omitted, an error will be thrown if the table does not exist.
    [Switch]
    $Force,

    # The connection string or a setting containing the connection string.  
    [Parameter(Mandatory=$true)]
    [String]
    $ConnectionStringOrSetting
    )


    begin {
        
        $params = @{} + $psboundparameters
        if ($ConnectionStringOrSetting.Contains("=")) {
            $ConnectionString =  $ConnectionStringOrSetting    
        } else {
            $ConnectionString = Get-SecureSetting -Name $ConnectionStringOrSetting -ValueOnly        
    
        }
        if (-not $ConnectionString) {
            throw "No Connection String"
            return
        }
        $sqlConnection = New-Object Data.SqlClient.SqlConnection "$connectionString"
        $sqlConnection.Open()

        $lastKnownRowCount = 0
        
        $propertyMatches = @{}
        foreach ($p in $Property) {
            if ($p) {
                $propertyMatches.$p =  $p
            }
        }

        $excludeMatches = @{}
        foreach ($p in $excludeMatches) {
            if ($p) {
                $excludeMatches.$p =  $p
            }
        }

        #region Common Parameters & Procedures
        
        # This is a set of parameters used to get the column metadata
        $GetColumnMetaData = @{
            FromTable="INFORMATION_SCHEMA.COLUMNS"
            Where= "TABLE_NAME = '$tableName'" 
            Property="Column_Name", "Data_Type"            
            ConnectionStringOrSetting=$ConnectionString
        }
        
        $GetPropertyNamesAndTypes = {
            param($object)

            $propTypes = New-Object Collections.ArrayList
            $propValues = New-Object Collections.ArrayList
            
                foreach ($prop in $object.psobject.properties) {
                    if (-not $prop) { continue } 
                    if ($propertyMatches.Count -and -not $propertyMatches[$prop]) {
                        continue
                    } 

                    if ($ExcludeProperty.Count -and $ExcludeProperty -contains $prop.Name) {
                        continue
                    }
                    # $prop.Name
                    if ($prop.Name -eq 'RowError' -or $prop.Name -eq 'RowState' -or $prop.Name -eq 'Table' -or $prop.Name -eq 'ItemArray'-or $prop.Name -eq 'HasErrors') {
                        continue
                    }
                    
                    $sqlType = if ($columnType -and $columnType[$prop.Name]) {
                        $columnType[$prop.Name]
                    } elseif ($prop.Value) {
                        if ($prop.Value -is [String]) {
                            "varchar(max)"                            
                        } elseif ($prop.Value -as [Byte]) {
                            "tinyint"
                        } elseif ($prop.Value -as [Int16]) {
                            "smallint"
                        } elseif ($prop.Value -as [Int]) {
                            "int"
                        } elseif ($Prop.Value -as [Double]) {
                            "float"
                        } elseif ($prop.Value -as [Long]) {
                            "bigint"
                        } elseif ($prop.Value -as [DateTime]) {
                            "datetime"
                        } else {
                            "varchar(max)"
                        }

                    } else {
                        "varchar(max)"
                    }

                    $columnName = if ($ColumnAlias -and $ColumnAlias[$prop.Name]) {
                        $ColumnAlias[$prop.Name]
                    } else {
                        $prop.Name
                    }



                    
                    New-Object PSObject -Property @{
                        Name=$columnName 
                        Value = $prop.Value
                        SqlType = $sqlType
                    }
                }


            New-Object PSObject -Property @{
                Name="pstypename"
                Value = $object.pstypenames -join '|'
                SqlType = $sqlType
            }
        }

        #endregion Common Parameters & Procedures

        $columnsInfo = 
            Select-SQL @GetColumnMetaData
        
        if (-not $columnsInfo) {
            # Table Doesn't Exist Yet, mark it for creation 
            if (-not $Force) {
                Write-Error "$tableName does not exist"
            }    
                    
        }
        $Local:DoNotRetry = $false
    }

 
    process {                
        # If there are no columns, and -Force  is not set
        if (-not $columnsInfo -and -not $force) {
            
            return
        }

        $objectSqlInfo = & $GetPropertyNamesAndTypes $inputObject 
        $byName = $objectSqlInfo | 
            Group-Object Name -AsHashTable

        if ($columnsInfo -and $force) {
            
        }

        # There are no columns, create the table
        if (-not $columnsInfo -and (-not $Local:DoNotRetry)) {
             
            Add-SqlTable -KeyType $keyType -TableName $TableName -Column (
                $objectSqlInfo | 
                    Where-Object { $_.Name -ne 'RowKey' } | 
                    Select-Object -ExpandProperty Name
            ) -DataType (
                $objectSqlInfo | 
                    Where-Object { $_.Name -ne 'RowKey' } | 
                    Select-Object -ExpandProperty SqlType
            ) -ConnectionStringOrSetting $ConnectionStringOrSetting
            

            $columnsInfo = 
                Select-SQL @GetColumnMetaData
        
        }

        # If there's still no columns info the table could not be created, and we should bounce
        if (-not $columnsInfo) {
            $Local:DoNotRetry = $true
            return

        }
        $updated = $false

        if ($psboundparameters.RowKey) {
            $updated = $false
            $sqlExists = "SELECT RowKey FROM $TableName WHERE RowKey='$RowKey'"
            $sqlAdapter= New-Object "Data.SqlClient.SqlDataAdapter" ($sqlExists, $sqlConnection)
            $sqlAdapter.SelectCommand.CommandTimeout = 0
            $dataSet = New-Object Data.DataSet
            $rowcount = try {
                    $sqlAdapter.Fill($dataSet)
                    $count = $lastKnownRowCount
            } catch {
                $ex = $_
            }

            if ($rowCount) {
                $updated = $true


                # Value Supplied, SQL UPDATE
                $sqlUpdate = 
                "UPDATE $TABLEName 
SET $(($objectSqlInfo | 
    Where-Object { $_.Name -ne 'RowKey'} | 
    Foreach-Object { '"' + $_.Name + '"=' + "'$($_.Value)'" }) -join ", ") WHERE RowKey='$RowKey'"
    
                Write-Verbose $SqlUpdate
                $sqlAdapter= New-Object "Data.SqlClient.SqlDataAdapter" ($sqlUpdate , $sqlConnection)
                $sqlAdapter.SelectCommand.CommandTimeout = 0
                $dataSet = New-Object Data.DataSet
                $rowCount = try {            
                    $sqlAdapter.Fill($dataSet)
                    $count = $lastKnownRowCount
                } catch {
                    Write-Error $_
                }
            }


        
        } 
        # Value Not supplied, generate a rowkey
        if (! $updated) {
            
            $row = 
                if ($psBoundParameters.RowKey -and -not $updated) {
                    $psBoundParameters.RowKey
                } elseif ($KeyType -eq 'GUID') {
                    {[GUID]::NewGuid()}
                } elseif ($KeyType -eq 'Hex') {
                    {"{0:x}" -f (Get-Random)}
                } elseif ($KeyType -eq 'SmallHex') {
                    {"{0:x}" -f ([int](Get-Random -Maximum 512kb))}
                } elseif ($KeyType -eq 'Sequential') {
                    if ($row -ne $null -and $row -as [Uint32]) {
                        $row + 1  
                    } else {                    
                        Select-SQL -FromTable $TableName -Property "COUNT(*)" -ConnectionStringOrSetting $ConnectionString | 
                            Select-Object -ExpandProperty Column1                    
                    }
                }
            $insertColumns = ($objectSqlInfo | 
                Where-Object { $_.Name -ne 'RowKey'} | 
                Select-Object -ExpandProperty Name) -join "`", `""
            $sqlInsert = 
                "INSERT INTO $TABLEName (`"RowKey`", `"$insertColumns`") VALUES ('$Row','$((
                    $objectSqlInfo | 
                    Where-Object { $_.Name -ne 'RowKey' } | 
                    Foreach-Object { "$($_.Value)".Replace("'", "''") }) -join "', '")')"
            Write-Verbose $sqlInsert

            $sqlAdapter= New-Object "Data.SqlClient.SqlDataAdapter" ($sqlInsert, $sqlConnection)
            $sqlAdapter.SelectCommand.CommandTimeout = 0
            $dataSet = New-Object Data.DataSet
            $rowCount = try {            
                $sqlAdapter.Fill($dataSet)
                $lastKnownRowCount = $row
            } catch {
                if ($_.Exception.InnerException.Message -like "*invalid column name*") {
                    $columnName  = ($_.Exception.InnerException.Message -split "'")[1]
                    $sqlAlter=  "ALTER TABLE $TableName ADD $ColumnName varchar(max)"
                    $sqlAdapter= New-Object "Data.SqlClient.SqlDataAdapter" ($sqlAlter, $sqlConnection)
                    $sqlAdapter.SelectCommand.CommandTimeout = 0
                    $dataSet = New-Object Data.DataSet
                    $n = $sqlAdapter.Fill($dataSet)
                    $sqlAdapter= New-Object "Data.SqlClient.SqlDataAdapter" ($sqlInsert, $sqlConnection)
                    $sqlAdapter.SelectCommand.CommandTimeout = 0
                    $dataSet = New-Object Data.DataSet
                    $n = $sqlAdapter.Fill($dataSet)
                } else {
                    Write-Error $_
                }
            }

        }

        
        

        
         

    }

    end {
         
        if ($sqlConnection) {
            $sqlConnection.Close()
            $sqlConnection.Dispose()
        }
        
    }
}
# SIG # Begin signature block
# MIINGAYJKoZIhvcNAQcCoIINCTCCDQUCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUhfb4McqbFbsxF5f0ctqt3cBV
# zfmgggpaMIIFIjCCBAqgAwIBAgIQAupQIxjzGlMFoE+9rHncOTANBgkqhkiG9w0B
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
# NwIBCzEOMAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFNPHYfPaR4jmreev
# nZuGG07uoeHNMA0GCSqGSIb3DQEBAQUABIIBALmb/LIx4mLmb+4VzHZiRcTnLvGN
# z1zBjm1gwVEJw0gLSNmYDJPmJBdygRPjDHP54zxESDqcEOzWId10Zu4xa2V7ehyR
# xnJ11m8XR3kaIzW1rd39ld32yWbCOfuE9YrtB/XYDHWX6WPjZK+lT0bu8aIOHOLV
# GQzM9gtHyGvoY4tu7UsK25ZTePbliqbukRsVXPx1uKa8rgEp7k/Hwr+bxwEdOiX1
# O7kGv0MY04vLLchSQBbshjzQkCR+yQPI5PCV11qG/mBde1CV4xmnK0eyOAeDxwOy
# VFif+q57lpBYeDVqQ9Yy9O5N2IuduKHM8qKQM6UT31pDOiT9iIgeMPksNCU=
# SIG # End signature block
