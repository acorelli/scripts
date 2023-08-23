@echo off
setlocal enabledelayedexpansion

for %%F in (*) do (
  set "filename=%%~nF"
  set "extension=%%~xF"
  
  if not "!extension!"==".bat" (
    ren "%%F" "%%F.txt"
  )
)

endlocal

:: for %%f in (*) do ren "%%f" "%%f.txt"