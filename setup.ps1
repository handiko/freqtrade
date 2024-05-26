Clear-Host

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Global:LogFilePath = Join-Path $env:TEMP "script_log_$Timestamp.txt"

$RequirementFiles = @("requirements.txt", "requirements-dev.txt", "requirements-hyperopt.txt", "requirements-freqai.txt", "requirements-freqai-rl.txt", "requirements-plot.txt")
$VenvName = ".venv"
$VenvDir = Join-Path $PSScriptRoot $VenvName

function Write-Log {
  param (
    [string]$Message,
    [string]$Level = 'INFO'
  )

  if (-not (Test-Path -Path $LogFilePath)) {
    New-Item -ItemType File -Path $LogFilePath -Force | Out-Null
  }
  
  switch ($Level) {
    'INFO' { Write-Host $Message -ForegroundColor Green }
    'WARNING' { Write-Host $Message -ForegroundColor Yellow }
    'ERROR' { Write-Host $Message -ForegroundColor Red }
    'PROMPT' { Write-Host $Message -ForegroundColor Cyan }
  }

  "${Level}: $Message" | Out-File $LogFilePath -Append
}

function Get-UserSelection {
  param (
    [string]$Prompt,
    [string[]]$Options,
    [string]$DefaultChoice = 'A',
    [bool]$AllowMultipleSelections = $true
  )
  
  Write-Log "$Prompt`n" -Level 'PROMPT'
  for ($I = 0; $I -lt $Options.Length; $I++) {
    Write-Log "$([char](65 + $I)). $($Options[$I])" -Level 'PROMPT'
  }
  
  if ($AllowMultipleSelections) {
    Write-Log "`nSelect one or more options by typing the corresponding letters, separated by commas." -Level 'PROMPT'
  }
  else {
    Write-Log "`nSelect an option by typing the corresponding letter." -Level 'PROMPT'
  }
  
  [string]$UserInput = Read-Host
  if ([string]::IsNullOrEmpty($UserInput)) {
    $UserInput = $DefaultChoice
  }
  
  if ($AllowMultipleSelections) {
    $Selections = $UserInput.Split(',') | ForEach-Object {
      $_.Trim().ToUpper()
    }
    
    $ErrorMessage = "Invalid input: $Selection. Please enter letters within the valid range of options."

    # Convert each Selection from letter to Index and validate
    $SelectedIndices = @()
    foreach ($Selection in $Selections) {
      if ($Selection -match '^[A-Z]$') {
        $Index = [int][char]$Selection - [int][char]'A'
        if ($Index -ge 0 -and $Index -lt $Options.Length) {
          $SelectedIndices += $Index
        }
        else {
          Write-Log $ErrorMessage -Level 'ERROR'
          return -1
        }
      }
      else {
        Write-Log $ErrorMessage -Level 'ERROR'
        return -1
      }
    }
    
    return $SelectedIndices
  }
  else {
    # Convert the Selection from letter to Index and validate
    if ($UserInput -match '^[A-Z]$') {
      $SelectedIndex = [int][char]$UserInput - [int][char]'A'
      if ($SelectedIndex -ge 0 -and $SelectedIndex -lt $Options.Length) {
        return $SelectedIndex
      }
      else {
        Write-Log "Invalid input: $UserInput. Please enter a letter within the valid range of options." -Level 'ERROR'
        return -1
      }
    }
    else {
      Write-Log "Invalid input: $UserInput. Please enter a letter between A and Z." -Level 'ERROR'
      return -1
    }
  }
}

function Exit-Script {
  param (
    [int]$ExitCode,
    [bool]$WaitForKeypress = $true
  )

  # Disable virtual environment
  deactivate

  if ($ExitCode -ne 0) {
    Write-Log "Script failed. Would you like to open the log file? (Y/N)" -Level 'PROMPT'
    $openLog = Read-Host
    if ($openLog -eq 'Y' -or $openLog -eq 'y') {
      Start-Process notepad.exe -ArgumentList $LogFilePath
    }
  }
  elseif ($WaitForKeypress) {
    Write-Log "Press any key to exit..."
    $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null
  }

  return $ExitCode
}

function Test-PythonExecutable {
  param(
    [string]$PythonExecutable
  )

  $PythonCmd = Get-Command $PythonExecutable -ErrorAction SilentlyContinue
  if ($PythonCmd) {
    $Command = "$($PythonCmd.Source) --version 2>&1"
    $VersionOutput = Invoke-Expression $Command
    if ($LASTEXITCODE -eq 0) {
      $Version = $VersionOutput | Select-String -Pattern "Python (\d+\.\d+\.\d+)" | ForEach-Object { $_.Matches.Groups[1].Value }
      Write-Log "Python version $Version found using executable '$PythonExecutable'."
      return $true
    }
    else {
      Write-Log "Python executable '$PythonExecutable' not working correctly." -Level 'ERROR'
      return $false
    }
  }
  else {
    Write-Log "Python executable '$PythonExecutable' not found." -Level 'ERROR'
    return $false
  }
}

function Find-PythonExecutable {
  $PythonExecutables = @("python", "python3.12", "python3.11", "python3.10", "python3.9", "python3", "C:\Users\$env:USERNAME\AppData\Local\Programs\Python\Python312\python.exe", "C:\Users\$env:USERNAME\AppData\Local\Programs\Python\Python311\python.exe", "C:\Users\$env:USERNAME\AppData\Local\Programs\Python\Python310\python.exe", "C:\Users\$env:USERNAME\AppData\Local\Programs\Python\Python39\python.exe", "C:\Python311\python.exe", "C:\Python310\python.exe", "C:\Python39\python.exe")

  
  foreach ($Executable in $PythonExecutables) {
    if (Test-PythonExecutable -PythonExecutable $Executable) {
      return $Executable
    }
  }

  return $null
}
function Main {
  "Starting the operations..." | Out-File $LogFilePath -Append
  "Current directory: $(Get-Location)" | Out-File $LogFilePath -Append

  # Exit on lower versions than Python 3.9 or when Python executable not found
  $PythonExecutable = Find-PythonExecutable
  if ($null -eq $PythonExecutable) {
    Write-Host "Error: No suitable Python executable found. Please ensure that Python 3.9 or higher is installed and available in the system PATH."
    Exit 1
  }

  # Define the path to the Python executable in the virtual environment
  $VenvPython = "$VenvDir\Scripts\Activate.ps1"

  # Check if the virtual environment exists, if not, create it
  if (-Not (Test-Path $VenvPython)) {
    Write-Log "Virtual environment not found. Creating virtual environment..." -Level 'ERROR'
    & $PythonExecutable -m venv $VenvName
    if (-Not (Test-Path $VenvPython)) {
      Write-Log "Failed to create virtual environment." -Level 'ERROR'
      Exit-Script -exitCode 1
    }
    Write-Log "Virtual environment created successfully."
  }

  # Pull latest updates only if the repository state is not dirty
  Write-Log "Checking if the repository is clean..."
  $status = & "C:\Program Files\Git\cmd\git.exe" status --porcelain
  if ($status) {
    Write-Log "Repository is dirty. Skipping pull."
  }
  else {
    Write-Log "Pulling latest updates..."
    & "C:\Program Files\Git\cmd\git.exe" pull | Out-File $LogFilePath -Append 2>&1
    if ($LASTEXITCODE -ne 0) {
      Write-Log "Failed to pull updates from Git." -Level 'ERROR'
      Exit-Script -exitCode 1
    }
  }


  if (-not (Test-Path "$VenvDir\Lib\site-packages\talib")) {
    # Install TA-Lib using the virtual environment's pip
    Write-Log "Installing TA-Lib using virtual environment's pip..."
    python -m pip install --find-links=build_helpers\ --prefer-binary TA-Lib | Out-File $LogFilePath -Append 2>&1
  }

  # Present options for requirement files
  $SelectedIndices = Get-UserSelection -prompt "Select which requirement files to install:" -options $RequirementFiles -defaultChoice 'A'

  # Cache the selected requirement files
  $SelectedRequirementFiles = @()
  $PipInstallArguments = ""
  foreach ($Index in $SelectedIndices) {
    $FilePath = Join-Path $PSScriptRoot $RequirementFiles[$Index]
    if (Test-Path $FilePath) {
      $SelectedRequirementFiles += $FilePath
      $PipInstallArguments += " -r $FilePath"
    }
    else {
      Write-Log "Requirement file not found: $FilePath" -Level 'ERROR'
      Exit-Script -exitCode 1
    }
  }
  if ($PipInstallArguments -ne "") {
    python -m pip install $PipInstallArguments
  }

  # Install freqtrade from setup using the virtual environment's Python
  Write-Log "Installing freqtrade from setup..."
  python -m pip install -e . | Out-File $LogFilePath -Append 2>&1
  if ($LASTEXITCODE -ne 0) {
    Write-Log "Failed to install freqtrade." -Level 'ERROR'
    Exit-Script -exitCode 1
  }

  $UiOptions = @("Yes", "No")
  $InstallUi = Get-UserSelection -prompt "Do you want to install the freqtrade UI?" -options $UiOptions -defaultChoice 'B' -allowMultipleSelections $false

  if ($InstallUi -eq 0) {
    # User selected "Yes"
    # Install freqtrade UI using the virtual environment's install-ui command
    Write-Log "Installing freqtrade UI..."
    python 'freqtrade', 'install-ui' | Out-File $LogFilePath -Append 2>&1
    if ($LASTEXITCODE -ne 0) {
      Write-Log "Failed to install freqtrade UI." -Level 'ERROR'
      Exit-Script -exitCode 1
    }
  }
  elseif ($InstallUi -eq 1) {
    # User selected "No"
    # Skip installing freqtrade UI
    Write-Log "Skipping freqtrade UI installation."
  }
  else {
    # Invalid Selection
    # Handle the error case
    Write-Log "Invalid Selection for freqtrade UI installation." -Level 'ERROR'
    Exit-Script -exitCode 1
  }
  
  Write-Log "Update complete!"
  Exit-Script -exitCode 0
}

# Call the Main function
Main