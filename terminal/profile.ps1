# >>> Graphite styling >>>
if (Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue) {
    Set-PSReadLineOption -Colors @{
        Command          = '#EEEEEE'
        Parameter        = '#EEEEEE'
        String           = '#EEEEEE'
        Number           = '#EEEEEE'
        Operator         = '#EEEEEE'
        Variable         = '#EEEEEE'
        Type             = '#EEEEEE'
        Keyword          = '#EEEEEE'
        Comment          = '#929292'
        Error            = '#CF8585'
        InlinePrediction = '#858585'
        Selection        = "`e[48;2;56;56;56m"
    }
}

$graphiteStarship = Get-Command starship -CommandType Application -ErrorAction SilentlyContinue
$graphiteStarshipPath = if ($graphiteStarship) {
    $graphiteStarship.Source
} else {
    Join-Path $env:USERPROFILE 'scoop/apps/starship/current/starship.exe'
}
if ($env:TERM -ne 'dumb' -and (Test-Path -LiteralPath $graphiteStarshipPath)) {
    Invoke-Expression (& $graphiteStarshipPath init powershell)
}
Remove-Variable graphiteStarship, graphiteStarshipPath -ErrorAction SilentlyContinue
# <<< Graphite styling <<<
