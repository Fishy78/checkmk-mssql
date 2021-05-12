Import-Module SQLPS -WarningAction SilentlyContinue
$ErrorActionPreference= 'silentlycontinue'
$path = Get-Location

function Get-IniFile {  
    param(  
        [parameter(Mandatory = $true)] [string] $filePath  
    )  
    
    $anonymous = "NoSection"
  
    $ini = @{}  
    switch -regex -file $filePath  
    {  
        "^\[(.+)\]$" # Section  
        {  
            $section = $matches[1]  
            $ini[$section] = @{}  
            $CommentCount = 0  
        }  

        "^(;.*)$" # Comment  
        {  
            if (!($section))  
            {  
                $section = $anonymous  
                $ini[$section] = @{}  
            }  
            $value = $matches[1]  
            $CommentCount = $CommentCount + 1  
            $name = "Comment" + $CommentCount  
            $ini[$section][$name] = $value  
        }   

        "(.+?)\s*=\s*(.*)" # Key  
        {  
            if (!($section))  
            {  
                $section = $anonymous  
                $ini[$section] = @{}  
            }  
            $name,$value = $matches[1..2]  
            $ini[$section][$name] = $value  
        }  
    }  

    return $ini  
} 

function Get-UserConfig {
    param(
        [parameter(Mandatory = $false)] [string] $instance
    )
    $ini = ""
    $mkconf=Get-Item -Path $ENV:MK_CONFDIR
    if($instance.Length -gt 0)
    {
        $conf="$($mkconf.FullName)mssql_$instance.ini"
        if(Get-Item -Path "$conf")
        {
            $ini = Get-IniFile -filePath "$conf"
        }
    }
    else
    {
        $conf="$($mkconf.FullName)mssql.ini"
        if(Get-Item -Path "$conf")
        {
            $ini = Get-IniFile -filePath "$conf"
        }
    }
    return $ini
}

function Invoke-SqlcmdWithConfig{
    param(
        $instance,
        $sql
    )
    $iniGlobal=Get-UserConfig
    cd $instance.PSPath
    $ini = Get-UserConfig -instance $instance.PSChildName
    if($ini -like "")
    {
        $ini=$iniGlobal
    }
    $data=""
    if($ini -like "")
    {
        $data = Invoke-Sqlcmd -Query "$sql" -WarningAction SilentlyContinue
    }
    else
    {
        $data = Invoke-Sqlcmd -Query "$sql" -Username $ini.auth.name -Password $ini.auth.password -WarningAction SilentlyContinue
    }
    return $data
}

cd SQLSERVER:\SQL

foreach($machine in Get-ChildItem){
    cd $machine.PSPath
    foreach($instance in Get-ChildItem)
    {
        $data = Invoke-SqlcmdWithConfig -instance $instance -sql "EXEC msdb.dbo.sp_help_jobactivity"
        "<<<mssql_job_activity>>>"
        if($data -ne "")
        {
            foreach($dataset in $data)
            {
                if($dataset.next_scheduled_run_date.toString().trim() -notlike "")
                {
                    "$($dataset.job_name.Trim().Replace(" ", "_")) $($dataset.next_scheduled_run_date.ToShortDateString().Trim()) $($dataset.next_scheduled_run_date.ToLongTimeString().Trim()) $($dataset.run_status)$($dataset.run_status.Trim()) $($dataset.message.Trim().Replace(" ", "_").Replace(".__", " "))" 
                }
            }
        }
    }
}
cd $path