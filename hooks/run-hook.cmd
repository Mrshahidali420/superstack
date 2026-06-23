: << 'BATCH'
@echo off
REM SPDX-License-Identifier: MIT
REM SuperStack cross-platform hook launcher (polyglot: batch on Windows, bash on Unix).
REM Windows: cmd runs this batch, locates bash, and runs the named extensionless hook script.
REM Unix:    bash ignores the batch (it lives inside a ': <<' heredoc) and runs the tail below.
REM Extensionless script names avoid Claude Code's Windows ".sh -> bash" auto-prefixing.
REM Usage: run-hook.cmd <script-name> [args...]
if "%~1"=="" ( echo run-hook.cmd: missing script name>&2 & exit /b 1 )
set "HOOK_DIR=%~dp0"
if exist "C:\Program Files\Git\bin\bash.exe" (
    "C:\Program Files\Git\bin\bash.exe" "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)
if exist "C:\Program Files (x86)\Git\bin\bash.exe" (
    "C:\Program Files (x86)\Git\bin\bash.exe" "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)
where bash >nul 2>nul && (
    bash "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)
REM No bash available: no-op so the plugin still works without hook injection.
exit /b 0
BATCH

# Unix: run the named hook script that sits beside this launcher.
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
name="$1"; shift
exec bash "${HOOK_DIR}/${name}" "$@"
