# Stop all Java processes
Get-Process | Where-Object {$_.ProcessName -eq "java"} | Stop-Process -Force

# Wait a moment
Start-Sleep -Seconds 2

# Remove Gradle caches
Remove-Item -Path "$env:USERPROFILE\.gradle\caches" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "android\.gradle" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "android\build" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "android\app\build" -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Gradle caches cleared successfully!"
