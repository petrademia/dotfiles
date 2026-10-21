param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Paths)
# Parse-only: builds the syntax tree and reports errors. Nothing in the files is executed.
$bad = 0
foreach ($p in $Paths) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$tokens, [ref]$errors)
    $label = $p.Replace($HOME, '~')
    if ($errors.Count -eq 0) {
        $fns = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true).Count
        "{0,-52} OK    ({1} functions)" -f $label, $fns
    } else {
        $bad++
        "{0,-52} FAIL  ({1} error(s))" -f $label, $errors.Count
        $errors | Select-Object -First 6 | ForEach-Object { "    line $($_.Extent.StartLineNumber): $($_.Message)" }
    }
}
exit $bad
