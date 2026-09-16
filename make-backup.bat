@echo off
setlocal disabledelayedexpansion

::
::  make-backup.bat
::
::  Creates a .7z archive of the current project folder.
::
::  Output     : ..\{FolderName}-backup-DD-MM-YYYY.7z
::  Exclusions : read from .gitignore (if present)
::

:: ── 1. Auto-detect project name from current folder ───────────────────────
for %%I in ("%CD%") do set "project=%%~nxI"

:: ── 2. Date stamp DD-MM-YYYY ──────────────────────────────────────────────
for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format dd-MM-yyyy"') do set "stamp=%%I"

:: ── 3. Output file ────────────────────────────────────────────────────────
set "outfile=..\%project%-backup-%stamp%.7z"

:: ── 4. Locate 7-Zip ───────────────────────────────────────────────────────
set "sz=7z"
where 7z >nul 2>&1
if errorlevel 1 (
    if exist "C:\Program Files\7-Zip\7z.exe" (
        set "sz=C:\Program Files\7-Zip\7z.exe"
    ) else (
        echo.
        echo  [ERROR] 7-Zip not found. Checked:
        echo            - PATH
        echo            - C:\Program Files\7-Zip\7z.exe
        echo.
        echo          Install from: https://www.7-zip.org/
        echo.
        exit /b 1
    )
)

:: ── 5. Parse .gitignore into a 7-Zip response file ────────────────────────
::
::  gitignore rule         7-Zip flag              notes
::  ──────────────────     ──────────────────────  ──────────────────────────
::  /anchored/path/   →   -x!anchored\path        root-relative, no recursion
::  anywhere/         →   -xr!anywhere            recursive, any depth
::
::  Skipped: blank lines, # comments, ! negation rules
::  Limitation: [abc] character classes (e.g. *.py[cod]) are not supported
::              by 7-Zip wildcards and will simply not match anything.
::
set "rsp=%TEMP%\make-backup-%project%.rsp"
del /F /Q "%rsp%" 2>nul

if exist ".gitignore" (
    powershell -NoProfile -Command "$out=@();foreach($l in (Get-Content '.gitignore')){$l=$l.Trim();if($l-eq''){ continue };if($l[0]-eq'#'){ continue };if($l[0]-eq'!'){ continue };$a=$l.StartsWith('/');$p=$l.TrimStart('/').TrimEnd('/').Replace('/','\');if($p-eq''){ continue };if($a){$out+='-x!'+$p}else{$out+='-xr!'+$p}};$out|Set-Content -Encoding ASCII '%rsp%'"
)

:: ── 6. Run 7-Zip ──────────────────────────────────────────────────────────
echo.
echo  Project : %project%
echo  Archive : %outfile%
if exist "%rsp%" (echo  Exclude : .gitignore patterns) else (echo  Exclude : none ^(no .gitignore found^))
echo.

if exist "%rsp%" (
    "%sz%" a -t7z -mx=5 -r "%outfile%" * "@%rsp%"
) else (
    "%sz%" a -t7z -mx=5 -r "%outfile%" *
)

:: ── 7. Cleanup and report ─────────────────────────────────────────────────
set "_ec=%errorlevel%"
del /F /Q "%rsp%" 2>nul

echo.
if %_ec% neq 0 (
    echo  [ERROR] 7-Zip exited with code %_ec%.
    exit /b %_ec%
)
echo  Done! Backup saved to: %outfile%
echo.
endlocal