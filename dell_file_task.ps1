# Функция для проверки прав администратора
function Test-IsAdmin {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Проверяем, запущен ли скрипт с правами администратора
if (-not (Test-IsAdmin)) {
    Write-Host "Скрипт не запущен с правами администратора. Перезапускаем с повышенными правами..."
    
    # Получаем полный путь к текущему скрипту
    $scriptPath = $MyInvocation.MyCommand.Definition
    
    # Запускаем скрипт с повышенными правами
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
    exit
}

# Настройки путей
$tasksFile = "\\nas\Distrib\script\dell_task\tasks.txt"
$logFolder = "\\nas\Distrib\script\dell_task\pc_log"
$allPcLog = "\\nas\Distrib\script\dell_task\all_pc_check.log"
$errorLog = "\\nas\Distrib\script\dell_task\err.log"
$noConnectLog = "\\nas\Distrib\script\dell_task\no_connect.log"
$targetFolders = @("Windows\System32\Tasks", "Windows\Tasks")

# Создаем папку для логов, если не существует
if (-not (Test-Path $logFolder)) {
    New-Item -ItemType Directory -Path $logFolder | Out-Null
}

# Получаем список задач из файла
$tasksToRemove = Get-Content -Path $tasksFile | Where-Object { $_ -match '\S' }

# Получаем список всех компьютеров в домене
try {
    Import-Module ActiveDirectory
    $computers = Get-ADComputer -Filter * -Property Name | Select-Object -ExpandProperty Name
} catch {
    Write-Error "Не удалось получить список компьютеров из AD. Убедитесь, что модуль ActiveDirectory установлен и у вас есть права."
    exit
}

foreach ($computer in $computers) {
    $deletedTasks = @()
    $computerLog = Join-Path $logFolder "$computer.log"
    
    # Проверяем доступность компьютера
    if (-not (Test-Connection -ComputerName $computer -Count 1 -Quiet)) {
        Add-Content -Path $noConnectLog "$computer" -ErrorAction SilentlyContinue
        continue
    }

    foreach ($folder in $targetFolders) {
        $remotePath = "\\$computer\c$\$folder"
        
        # Проверяем доступность папки
        if (-not (Test-Path $remotePath)) {
            continue
        }

        foreach ($task in $tasksToRemove) {
            $taskPath = Join-Path $remotePath $task
            
            try {
                if (Test-Path $taskPath) {
                    Remove-Item -Path $taskPath -Force -ErrorAction Stop
                    $deletedTasks += $task
                }
            } catch {
                $errMsg = "[$(Get-Date)] Ошибка при удалении задачи '$task' на компьютере '$computer': $_"
                Write-Warning $errMsg
                Add-Content -Path $errorLog $errMsg -ErrorAction SilentlyContinue
            }
        }
    }

    # Логируем удаленные задачи
    if ($deletedTasks.Count -gt 0) {
        $deletedTasks | ForEach-Object { Add-Content -Path $computerLog $_ }
        Add-Content -Path $allPcLog $computer
    }
}