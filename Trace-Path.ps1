
function red { param($string, $suffix = '', [parameter(ValueFromPipeline)]$prefix) "$prefix`e[31m$string`e[0m$suffix" }
function green  { param($string, $suffix = '', [parameter(ValueFromPipeline)]$prefix) "$prefix`e[32m$string`e[0m$suffix" }

function ends_with_spaces($path) {
    $IsWindows -and $path.TrimEnd(' ') -ne $path
}

function Trace-Path {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline=$true)]
        [AllowNull()]
        [string]
        $Path,

        [Switch]
        $LineNumbers
    )
    begin {
        # my attempt at "overriding" the default parameter value for InformationAction
        # Warning: this does not work
        if ($null -eq $PSCmdlet.MyInvocation.BoundParameters["InformationAction"]) {
            $InformationPreference = 'Continue'
        }

        $line = 0
    }
    process {
        $line++

        if ([string]::IsNullOrEmpty($Path)) {
            Write-Information  (red "Supplied path was null or empty")
            return $false
        }

        if (![System.IO.Path]::IsPathRooted($Path)) {
            $Path = [System.IO.Path]::Join([string]$pwd, $Path)
        }

        # optimal case
        if ([System.IO.File]::Exists($Path) -or [System.IO.Directory]::Exists($Path)) {
            #Write-Information ((green "Exists:`t") + "$Path")
            return $true
        }

        Write-Information (red $Path " does not exist")

        # split path segments
        if ($IsWindows) {
            $delimitter = "/|\\"
        }
        else {
            $delimitter = "/"
        }

        $fragments = $Path -split $delimitter

        if ($fragments.Count -eq 0) {
            $last_part = $Path
        }

        if ($IsWindows) {
            $built_up_path = ""
            $system_delimitter = "\"
        }
        else {
            $built_up_path = "/"
            $system_delimitter = "/"
        }

        $space_at_end = $false

        for ($i = 0; $i -lt $fragments.Count; $i++) {
            Write-Debug ("Fragment $i`: ``" + $fragments[$i] + '``')
            $this_delimitter = if ($i -eq 0) { "" } else  {$system_delimitter }
            $test_path = $built_up_path + $this_delimitter + $fragments[$i]

            if ([System.IO.File]::Exists($test_path) -or [System.IO.Directory]::Exists($test_path)) {
                # the .NET framework normalizes paths with trailing spaces by stripping
                # the trailing spaces. It only does it in some cases though, which
                # means if there is a directory with a trailing space, and another 
                # fragment after it, the path will not resolve, which is one use case
                # for Trace-path
                if (ends_with_spaces $test_path) {
                    $last_part = $fragments[$i]
                    $space_at_end = $true
                    break;
                }
                else {
                    $built_up_path = $test_path
                }
            }
            else {
                $last_part = $fragments[$i]
                break;
            }
        }

        $final_test_path = $built_up_path
        if ($space_at_end) {
            $space_at_end = $true
            $trimmed = $last_part.TrimEnd(' ')
            
            $final_test_path = $built_up_path + $system_delimitter + $trimmed
            Write-Debug ("Fragment space in path, final_path: '$final_test_path'")
        }
        else {
            # reverse search here - i've found often the mistake is closer to the end of the file name
            # and if it is, there are way fewer matching files that could be returned with the wild card
            for($l = $last_part.Length; $l -gt 0; $l--) {
                $last_fragment = $last_part.Substring(0, $l)

                Write-Debug ("Last Fragment $l`: ``" + $last_fragment + '`')
                $has_results = [System.IO.Directory]::EnumerateFileSystemEntries($built_up_path, "$last_fragment*").GetEnumerator().MoveNext()
                if ($has_results) {
                    $final_test_path = $built_up_path + $system_delimitter + $last_fragment
                    break;
                }
                else {
                    # continue
                }
            }

            # nothing in the fragment matched anything in the directory
            # but we wan't to suggest results inside the directory, so add the
            # directory delimitter
            if ($l -eq 0) {
                $final_test_path = $built_up_path + $system_delimitter
            }
        }

        Write-Debug "Final test path: ``$final_test_path``"

        $rest = $Path.Substring($final_test_path.Length)
        $good_index = $final_test_path.Length - 1
        $error_index = $final_test_path.Length - 1 + 1
        $good_col = $good_index + 1
        $error_col = $error_index + 1
        $message = ""
        $suffix = ""
        if ($LineNumbers) {
            $line_part = ", line $line"
        }
        if ($rest.Length -eq 0)  {
            $message = "Input path exists wholly until its end (column ${good_col}${line_part}). Is the path complete?"
            $suffix = "(too short)"
        }
        elseif ($space_at_end) {
            $message = "Input path has one or more spaces in a parent folder, starting at (column ${error_col}${line_part}):"
            $suffix = "(remove trailing spaces)"
        }
        else {
            $next_char = $Path[$error_index]
            if ([Char]::IsControl($next_char) -or [Char]::IsWhiteSpace($next_char)) {
                $alt = ''
                if ($next_char = ' ') {
                    $alt = '<space>'
                }
                else {
                    $alt = "0x" + ([uint][char]$next_char).ToString("X")
                }
                $next_char = "'$next_char' ($alt)"
            }
            $message = "Input path differs from real path with character " | red $next_char ", at column ${error_col}${line_part}:"
        }

        # minus one to make room for '>' indicator
        $indicator = "`t" + (' ' * ($good_index)) | green '>' | red '<' $suffix

        if ($space_at_end) {
            # TODO check if we can correct whole path
        }

        $alternatives = (
            Get-ChildItem ($final_test_path + "*") `
            | Select-Object -First 10 `
            | ForEach-Object { "`t" | green $_.FullName } 
        ) -join "`n"

        Write-Information $message
        Write-Information $indicator
        Write-Information "`t$(green $final_test_path)$(red "$Rest")"
        Write-Information "Here are some alternatives:`n$alternatives"

        return $false
    }
}

Export-ModuleMember -Function Trace-Path