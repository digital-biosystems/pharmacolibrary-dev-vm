@echo off
rem Starts setup.ps1 with the execution policy bypassed for this one process only, so it runs on
rem a Windows whose policy is Restricted (the default) without changing any setting. Options are
rem passed on:  windows\setup.cmd -WithCorpus
rem A policy set by Group Policy (Get-ExecutionPolicy -List: MachinePolicy/UserPolicy) still wins.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*
exit /b %ERRORLEVEL%
