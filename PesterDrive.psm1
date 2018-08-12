using namespace Microsoft.PowerShell.SHiPS


[SHiPSProvider(UseCache = $false)]
class PesterRoot : SHiPSDirectory
{    
    static [string] $Script

    # Default constructor
    PesterRoot([string]$Name):base($Name)
    {        #$this.Script  = Write-Host -Prompt "TestScript"

    }

    [object[]] GetChildItem()
    {        
        $Count = 1
        $AST    = Get-CommandAst -Script ([string][PesterRoot]::Script) #$this.Script
        $Group  = $AST | ForEach-Object -Process { ([array]$_.CommandElements.Value)[0] } | Group-Object
        $Output =  $Group | Where-Object -FilterScript { $_.Name -match "Describe|It|Context|Should" } | ForEach-Object -Process {
                       [PesterFunction]::New($_.Name,$_.Count,$this.Script,$AST)
                   }
        
        return $Output
    }
}

[SHiPSProvider(UseCache = $False)]
Class PesterFunction : SHiPSDirectory
{    
    hidden [string] $Script
    [int] $CurrentFunctionCount
    [string] $RealName
    [int] $UsageCount
    hidden [object] $CurrentFunctionAst
    [String] $Contents
    

    PesterFunction([string]$Name,[int]$Count,[string]$Script,[object]$Ast):base($Name)
    {
        $this.Script               = $Script
        $this.CurrentFunctionAst   = $Ast
        $this.RealName             = $Name
        $this.UsageCount           = $Count
        $this.Contents             = ($Ast.CommandElements | ForEach-Object -Process {$_.Parent.Extent.Text.split('{')[0]})[0]
    }

    [object[]] GetChildItem()
    {
        $Count = 1
        
        $Output  = $this.CurrentFunctionAst | Where-Object -FilterScript { $_.CommandElements.Value[0] -eq $this.RealName } | ForEach-Object -Process {
                    [Describe]::New($_.CommandElements.Value[0],$Count,$_)
                    $Count++
        }

        return $Output
    }
}


[SHiPSProvider(UseCache = $False)]
Class Describe : SHiPSDirectory
{
    [string] $RealName
    [String] $Contents
    hidden [object] $CurrentFunctionAst

    Describe([string]$Name,[int]$Count,[object]$Ast):base($Name)
    {
        $this.Name               = "$Name-$Count"
        $this.CurrentFunctionAst = $Ast
        $this.RealName           = $Name
        $this.Contents           = ($Ast.CommandElements | ForEach-Object -Process {$_.Parent.Extent.Text.split('{')[0]})[0]
    }

    [object[]] GetChildItem()
    {
        $Count = 1

        $Output  = $this.CurrentFunctionAst | ForEach-Object -Process {
                        $ContextAst = Get-CommandAst -ScriptText $_.Extent.Text -Command 'Context'
                        if( $Null -ne $ContextAst ){
                                $ContextAst | ForEach-Object -Process {
                                [Context]::New($_.CommandElements.Value[0],$_,$Count)
                                $Count++
                            }
                        }
                        else{
                            $ItAst = Get-CommandAst -ScriptText $_.Extent.Text -Command 'It'
                            $ItAst | ForEach-Object -Process {
                                [It]::New($_.CommandElements.Value[0],$_,$Count)
                                $Count++                
                            }
                        }
                    }

        return $Output
    }
}

[SHiPSProvider(UseCache = $False)]
Class Context: SHiPSDirectory
{
    [string] $RealName
    [int] $TestCaseCount
    [String] $Contents
    hidden [object] $CurrentFunctionAst

    Context([string]$Name,[object]$Ast,[int]$Count):base($Name)
    {
        $this.Name                 = "$Name-$Count"
        $this.RealName             = $Name
        $this.CurrentFunctionAst   = $Ast
        $this.Contents             = ($Ast.CommandElements | ForEach-Object -Process {$_.Parent.Extent.Text.split('{')[0]})[0]
    }

    [object[]] GetChildItem()
    {
        $Count   = 1
        $Output  = $this.CurrentFunctionAst | ForEach-Object -Process {
                        Get-CommandAst -ScriptText $_.Extent.Text -Command 'it' | ForEach-Object -Process {
                            [it]::New($_.CommandElements.Value[0],$_,$Count)
                            $Count++                
                        }
                   }
        $this.TestCaseCount = $Output.Count
        return $Output
    }
}

[SHiPSProvider(UseCache = $False)]
Class It : SHiPSDirectory
{
    [string] $RealName
    [int] $AssertionCount
    [String] $Contents
    hidden [object] $CurrentFunctionAst

    It([string]$Name,[object]$Ast,[int]$Count):base($Name)
    {
        $this.Name                 = "$Name-$Count"
        $this.CurrentFunctionAst   = $Ast
        $this.RealName             = $Name
        $this.Contents             = ($Ast.CommandElements | ForEach-Object -Process {$_.Parent.Extent.Text.split('{')[0]})[0]
    }

    [object[]] GetChildItem()
    {
        $Count = 1
        $Output  = $this.CurrentFunctionAst | ForEach-Object -Process {
                        Get-CommandAst -ScriptText $_.Extent.Text -Command 'Should' | ForEach-Object -Process {
                            [Assertion]::New($_.CommandElements.Value[0],$_,$Count)
                            $Count++                
                        }
                   }
        $this.AssertionCount = $Output.Count
        return $Output
    }
}

[SHiPSProvider(UseCache = $False)]
Class Assertion : SHiPSLeaf
{
    [string] $RealName
    [object] $Contents

    Assertion([string]$Name,[object]$Ast,[int]$Count):base($Name)
    {
        $this.Name     = "$Name-$Count"
        $this.RealName = $Name
        $this.Contents = $Ast.Parent.Extent.Text

    }    
}

Function Get-CommandAst {
    Param(
        [Parameter(Mandatory, ParameterSetName='Path')]
        [string]$Script,

        [Parameter(Mandatory, ParameterSetName='Content')]
        [string]$ScriptText,

        [string]$Command
    )

    if($PSBoundParameters.ContainsKey('Script')){
        $AST    = [System.Management.Automation.Language.Parser]::ParseFile($Script,[ref]$Null,[ref]$Null)
    }
    else{
        $AST    = [System.Management.Automation.Language.Parser]::ParseInput($ScriptText,[ref]$Null,[ref]$Null)
    }

    $Output = $CommandAst = $AST.FindAll({$args[0] -is [System.Management.Automation.Language.CommandAst]},$True)
    
    if(-not [string]::IsNullOrEmpty($Command)){
        $Output = $CommandAst | Where-Object -FilterScript { $_.CommandElements.Value -eq $Command }
    }

    return $Output    
}

Function Set-TestScript {
    Param(
        [Parameter(Mandatory)]
        $Script
    )
    if(Test-Path -Path $Script){
        [PesterRoot]::Script = $Script
    }
    else{
        Throw "$Script is not available" 
    }
}