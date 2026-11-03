# N.O.M.A.D. read-only Windows hardware collector.
$ErrorActionPreference = "Continue"
$Out = Join-Path $PWD ("NOMAD-WINDOWS-REPORT-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
New-Item -ItemType Directory -Path $Out -Force | Out-Null

$cs = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor
$bios = Get-CimInstance Win32_BIOS
$video = Get-CimInstance Win32_VideoController
$disks = Get-CimInstance Win32_DiskDrive
$nic = Get-CimInstance Win32_NetworkAdapter | Where-Object { $_.PhysicalAdapter -eq $true }
$os = Get-CimInstance Win32_OperatingSystem

$data = [ordered]@{
  Generated = (Get-Date).ToString("o")
  Manufacturer = $cs.Manufacturer
  Model = $cs.Model
  TotalPhysicalMemoryBytes = $cs.TotalPhysicalMemory
  CPU = @($cpu | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed, AddressWidth)
  BIOS = $bios | Select-Object Manufacturer, SMBIOSBIOSVersion, ReleaseDate, SerialNumber
  Graphics = @($video | Select-Object Name, DriverVersion, AdapterRAM, VideoModeDescription)
  Disks = @($disks | Select-Object Model, Size, InterfaceType, MediaType, SerialNumber, PNPDeviceID)
  NetworkAdapters = @($nic | Select-Object Name, NetConnectionID, Manufacturer, MACAddress, NetEnabled, PNPDeviceID)
  OS = $os | Select-Object Caption, Version, BuildNumber, OSArchitecture
  ReadOnly = $true
}
$data | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 (Join-Path $Out "hardware-report.json")
Write-Host "N.O.M.A.D. report created: $Out" -ForegroundColor Green
Write-Host "Read-only: no disks or Windows settings were changed."
