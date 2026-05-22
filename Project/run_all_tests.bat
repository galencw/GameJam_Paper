@echo off
REM Run all smoke tests in sequence
REM Usage: F:\Aion\LegendaryTrader\Project\run_all_tests.bat
setlocal

set "PROJ=%~dp0"
if "%PROJ:~-1%"=="\" set "PROJ=%PROJ:~0,-1%"

call "%PROJ%\run_rule_test.bat"
set "RULE_RC=%ERRORLEVEL%"
call "%PROJ%\run_shop_test.bat"
set "SHOP_RC=%ERRORLEVEL%"

echo.
echo ==================================
echo    Rule  smoke: exit %RULE_RC%
echo    Shop  smoke: exit %SHOP_RC%
echo ==================================

if not "%RULE_RC%"=="0" exit /b %RULE_RC%
if not "%SHOP_RC%"=="0" exit /b %SHOP_RC%
echo ALL PASS
exit /b 0
