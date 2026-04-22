$regPath = "HKCU:\Return of Reckoning\Return of Reckoning"
$regDefault = try { (Get-ItemProperty -Path $regPath -ErrorAction Stop)."(default)" } catch { $null }
$default = if ($regDefault) { $regDefault } else { "C:\Games\Return of Reckoning" }

$input = Read-Host "Game install folder [$default]"
$gameDir = if ($input.Trim() -eq "") { $default } else { $input.Trim() }
$dest = Join-Path $gameDir "Interface\AddOns\CustomUI"

Write-Host "Deploying CustomUI to: $dest"

New-Item $dest -ItemType Directory -Force | Out-Null

Copy-Item "CustomUI.mod" $dest -Force
Copy-Item "Source" $dest -Recurse -Force

Write-Host "Done."
