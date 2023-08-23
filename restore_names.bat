@echo off
setlocal enabledelayedexpansion

for %%f in (*.txt) do (
  set "name=%%~nf"
  ren "%%f" "!name!"
)

endlocal