@echo off
setlocal

set GODOT=C:\Users\minhv\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64.exe
set PROJECT=%~dp0..
set FAIL=0

echo === TimeCalculator ===
%GODOT% --headless --path "%PROJECT%" -s tests/test_time_calculator.gd
if errorlevel 1 set FAIL=1

echo.
echo === Pathing ===
%GODOT% --headless --path "%PROJECT%" -s tests/test_pathing.gd
if errorlevel 1 set FAIL=1

echo.
echo === Actions ===
%GODOT% --headless --path "%PROJECT%" -s tests/test_actions.gd
if errorlevel 1 set FAIL=1

echo.
if %FAIL%==0 (
    echo ALL TESTS PASSED
    exit /b 0
) else (
    echo SOME TESTS FAILED
    exit /b 1
)
