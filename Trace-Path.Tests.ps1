# Import-Module Pester -Force


Import-Module -Force .\PathDiagnostics.psd1

$real_paths = @(
    "TestDrive:/a.txt",
    "TestDrive:/bcde/f/g/h.txt",
    "TestDrive:/bc/123.txt",
    "TestDrive:/a/b a b/c/d/e/f/g/hijk/lmnop.qxyz"
)

$red = "`e[31m"
$green = "`e[32m"
$reset = "`e[0m"


Describe "Trace-Path" {
    $real_paths | ForEach-Object {  New-Item -Force  $_ }
    $all_files = Get-ChildItem -Recurse "$TestDrive" | ForEach-Object FullName
    $all_files_forward_slash = $all_files -replace '\\','/'
    
    Get-ChildItem -Recurse TestDrive: | Write-Debug

    $td = $TestDrive.FullName
    $tl = $TestDrive.FullName.Length
    $ts = ' ' * $tl

    Write-Debug $td
    Write-Debug $tl
    Write-Debug "'$ts'"


    function should_be_path_not_exist($string) {
        $input.MessageData | Should -BeExactly "${red}$string${reset} does not exist"
    }
    function should_be_input_path_differs($char, $index, $line = "") {
        if ("" -ne $line) {
            $line = ", line $line"
        }
        $input.MessageData | Should -BeExactly "Input path differs from real path with character ${red}$char${reset}, at column $($index + $tl)${line}:"
    }
    function should_be_trailing_spaces($index) {
        $input.MessageData | Should -BeExactly "Input path has one or more spaces in a parent folder, starting at (column $($index + $tl)):"
    }
    function should_be_too_short($index) {
        $input.MessageData | Should -BeExactly "Input path exists wholly until its end (column $($index + $tl)). Is the path complete?"
    }
    function should_be_indicator($index, $suffix = '') {
        $spaces = ' ' * ($index - 1)
        $input.MessageData | Should -BeExactly  "`t${ts}${spaces}${green}>${reset}${red}<${reset}$suffix"
    }
    function should_be_alternatives($alternatives) {
        $formatted_alternatives = "Here are some alternatives:`n" `
          + (($alternatives | ForEach-Object { "`t${green}$_${reset}"}) -join "`n")
        $input.MessageData | Should -BeExactly $formatted_alternatives
    }

    It "returns `False` for null or empty input" -TestCases @(
        @{ path = $null },
        @{ path = "" }
    ) {
        param($path)
        $result = Trace-Path $path -InformationVariable 'info'

        $result | Should -Be $False
        $info | Should -HaveCount 1
        $info[0].MessageData | Should -BeExactly "${red}Supplied path was null or empty${reset}"
    }

    It "returns `True` for paths that exist" -TestCases ($all_files | ForEach-Object { @{path=$_} }) {
        param($path)
        $result = Trace-Path $path -InformationVariable 'info'

        $result | Should -Be $true
        $info | Should -BeNullOrEmpty
    }

    It "returns `True` for paths that exist (with forward slashes)" -TestCases ($all_files_forward_slash | ForEach-Object { @{path=$_} }) {
        param($path)
        $result = Trace-Path $path -InformationVariable 'info'

        $result | Should -Be $true
        $info | Should -BeNullOrEmpty
    }

    It "can detect a misspelt folder" {
        $path =  "$td/bcze/f/g/h.txt"

        $result = Trace-Path $path -InformationVariable 'info'

        $result | Should -Be $false
        $info[0] | should_be_path_not_exist $path
        $info[1] | should_be_input_path_differs 'z' 4
        $info[2] | should_be_indicator 3
        $info[4] | should_be_alternatives ("$td\bc", "$td\bcde")

    }

    It "can suggest folders even for a compeletely wrong folder" {
        $path =  "$td/z/f/g/h.txt"

        $result = Trace-Path $path -InformationVariable 'info'

        $result | Should -Be $false
        $info[0] | should_be_path_not_exist $path
        $info[1] | should_be_input_path_differs 'z' 2
        $info[2] | should_be_indicator 1
        $info[4] | should_be_alternatives ("$td\a",  "$td\bc", "$td\bcde", "$td\a.txt")
    }

    It "deals with spaces in parent directories" {
        $path =  "$td/a/b a z/c/d/e/f/g/hijk/lmnop.qxyz"

        $result = Trace-Path $path -InformationVariable 'info'

        $result | Should -Be $false
        $info[0] | should_be_path_not_exist $path
        $info[1] | should_be_input_path_differs 'z' 8
        $info[2] | should_be_indicator 7
        $info[4] | should_be_alternatives ("$td\a\b a b")
    }

    It "deals with extra token in parent directories" {
        $path =  "$td/a/b a b z/c/d/e/f/g/hijk/lmnop.qxyz"

        $result = Trace-Path $path -InformationVariable 'info'

        $result | Should -Be $false
        $info[0] | should_be_path_not_exist $path
        $info[1] | should_be_input_path_differs "' ' (<space>)" 9
        $info[2] | should_be_indicator 8
        $info[4] | should_be_alternatives ("$td\a\b a b")
    }

    It "deals with trailing space in parent directories" {
        $path =  "$td/a/b a b /c/d/e/f/g/hijk/lmnop.qxyz"

        $result = Trace-Path $path -InformationVariable 'info'

        $result | Should -Be $false
        $info[0] | should_be_path_not_exist $path
        $info[1] | should_be_trailing_spaces 9
        $info[2] | should_be_indicator 8 -suffix '(remove trailing spaces)'
        $info[4] | should_be_alternatives ("$td\a\b a b")
    }

    It "deals with multiple trailing space in parent directories" {
        $path =  "$td/a/b a b  /c/d/e/f/g/hijk/lmnop.qxyz"

        $result = Trace-Path $path -InformationVariable 'info'

        $result | Should -Be $false
        $info[0] | should_be_path_not_exist $path
        $info[1] | should_be_trailing_spaces 9
        $info[2] | should_be_indicator 8 -suffix "(remove trailing spaces)"
        $info[4] | should_be_alternatives ("$td\a\b a b")
    }

    
    It "deals with missing end characters" -TestCases @(
        @{ path = "$td/a/b a b/c/d/e/f/g/hijk/lmnop.qxy" },
        @{ path = "$td/a/b a b/c/d/e/f/g/hijk/lmnop.qx" },
        @{ path = "$td/a/b a b/c/d/e/f/g/hijk/lmnop.q" },
        @{ path = "$td/a/b a b/c/d/e/f/g/hijk/lmnop." },
        @{ path = "$td/a/b a b/c/d/e/f/g/hijk/lmnop" },
        @{ path = "$td/a/b a b/c/d/e/f/g/hijk/lmno" },
        @{ path = "$td/a/b a b/c/d/e/f/g/hijk/lmn" },
        @{ path = "$td/a/b a b/c/d/e/f/g/hijk/lm" },
        @{ path = "$td/a/b a b/c/d/e/f/g/hijk/l" }
    ) {
        param ($path)
        $file_name = [System.IO.Path]::GetFileName($path)
        $result = Trace-Path $path -InformationVariable 'info'

        $result | Should -Be $false
        $info[0] | should_be_path_not_exist $path
        $info[1] | should_be_too_short (24 + $file_name.Length)
        $info[2] | should_be_indicator (24 + $file_name.Length) -suffix "(too short)" 
        $info[4] | should_be_alternatives ("$td\a\b a b\c\d\e\f\g\hijk\lmnop.qxyz")
    }

    It "Accepts pipeline input" {
        $expected = ((,$true) * ($all_files.Count) + (,$false))
        
        $test = $all_files + @(,"$td/IdontExist")

        $actual = $test | Trace-Path

        $actual | Should -BeExactly $expected
    }

    It "Will show line numbers" {
        $expected = ((,$true) * ($all_files.Count) + (,$false))
        
        $test = $all_files + @(,"$td/IdontExist")

        $actual = $test | Trace-Path -InformationVariable 'info' -LineNumbers

        $actual | Should -BeExactly $expected
        $info[1] | should_be_input_path_differs 'I' 2 -line ($all_files.Count + 1)

    }

    Context "Relative Paths" {
        $previous_working_directory = $null

        BeforeEach {
            $previous_working_directory = $pwd
            Set-Location "$td"
        }

        It "returns `True` for paths that exist"  {
            $path =  "bcde/f/g/h.txt"
            $result = Trace-Path $path -InformationVariable 'info'
    
            $result | Should -Be $true
            $info | Should -BeNullOrEmpty
        }

        It "can detect a misspelt folder" {
            $path =  "bcze/f/g/h.txt"
    
            $result = Trace-Path $path -InformationVariable 'info'
    
            $result | Should -Be $false
            $info[0] | should_be_path_not_exist "$td\$path"
            $info[1] | should_be_input_path_differs 'z' 4
            $info[2] | should_be_indicator 3
            $info[4] | should_be_alternatives ("$td\bc", "$td\bcde")
        }

        It "can suggest folders even for a compeletely wrong folder" {
            $path =  "z/f/g/h.txt"
    
            $result = Trace-Path $path -InformationVariable 'info'
    
            $result | Should -Be $false
            $info[0] | should_be_path_not_exist "$td\$path"
            $info[1] | should_be_input_path_differs 'z' 2
            $info[2] | should_be_indicator 1
            $info[4] | should_be_alternatives ("$td\a",  "$td\bc", "$td\bcde", "$td\a.txt")
        }

        It "deals with missing end characters" -TestCases @(
            @{ path = "a/b a b/c/d/e/f/g/hijk/lmnop.qxy" },
            @{ path = "a/b a b/c/d/e/f/g/hijk/lmnop.qx" },
            @{ path = "a/b a b/c/d/e/f/g/hijk/lmnop.q" },
            @{ path = "a/b a b/c/d/e/f/g/hijk/lmnop." },
            @{ path = "a/b a b/c/d/e/f/g/hijk/lmnop" },
            @{ path = "a/b a b/c/d/e/f/g/hijk/lmno" },
            @{ path = "a/b a b/c/d/e/f/g/hijk/lmn" },
            @{ path = "a/b a b/c/d/e/f/g/hijk/lm" },
            @{ path = "a/b a b/c/d/e/f/g/hijk/l" }
        ) {
            param ($path)
            $file_name = [System.IO.Path]::GetFileName($path)
            $result = Trace-Path $path -InformationVariable 'info'
    
            $result | Should -Be $false
            $info[0] | should_be_path_not_exist "$td\$path"
            $info[1] | should_be_too_short (24 + $file_name.Length)
            $info[2] | should_be_indicator (24 + $file_name.Length) -suffix "(too short)" 
            $info[4] | should_be_alternatives ("$td\a\b a b\c\d\e\f\g\hijk\lmnop.qxyz")
        }
    
        AfterEach {
            Set-Location $previous_working_directory
        }
    }

    It "Accepts FileInfo input" {
        $path =  [System.IO.FileInfo]"$td/z/f/g/h.txt"

        $result = Trace-Path $path -InformationVariable 'info'

        $result | Should -Be $false
        $info[0] | should_be_path_not_exist $path
        $info[1] | should_be_input_path_differs 'z' 2
        $info[2] | should_be_indicator 1
        $info[4] | should_be_alternatives ("$td\a",  "$td\bc", "$td\bcde", "$td\a.txt")
    }

    It "does not modify global information preference"  {
        $InformationPreference = 'SilentlyContinue'

        $result = Trace-Path "$td/a"

        $result | Should -Be $true
        $InformationPreference | Should -BeExactly "SilentlyContinue"
    }

    It "Will be quiet if told to be" -Pending {
        $module_path = (Resolve-Path .\PathDiagnostics.psd1).Path
        $ps = [powershell]::Create()
        $actual = $ps.AddScript(@"
`$InformationPreference = 'Ignore'
Import-Module -Force $module_path
'$td/IdontExist' | Trace-Path -InformationAction 'SilentlyContinue'
"@).Invoke()

        $info = $ps.Streams.Information

        $actual | Format-List -Force |        Out-Host
        "`n-------------------`n" | Out-Host
        $info | Format-List -Force |        Out-Host
        $actual[0] | Should -BeExactly $false
        $actual.Count | Should -Be 1

        $ps.Dispose()
    }
}


