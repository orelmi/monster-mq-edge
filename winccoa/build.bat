@echo off
REM build.bat - Build the WinCC OA API manager WCCOAmmq.exe for Windows x64,
REM with the broker embedded as monstermq.dll. Run it from an
REM "x64 Native Tools Command Prompt for VS 2022".
REM
REM Usage:
REM   winccoa\build.bat                       Build monstermq.dll and WCCOAmmq.exe
REM   winccoa\build.bat --test                Also run the C ABI harness against the DLL
REM   winccoa\build.bat --clean               Rebuild the manager from an empty CMake build directory
REM   winccoa\build.bat --install PROJECT     Copy WCCOAmmq.exe and monstermq.dll to PROJECT\bin
REM   winccoa\build.bat --skip-dll            Use build\embed-windows as it is (make embed-dll in MSYS2)
REM   winccoa\build.bat --msys2               Build the DLL with the MSYS2 UCRT64 gcc
REM   winccoa\build.bat --cc GCC              Build the DLL with this mingw-w64 gcc
REM
REM cgo cannot use MSVC, so the DLL needs a mingw-w64 gcc: --cc, --msys2, gcc
REM on PATH, or the MSYS2 UCRT64 gcc, in this order. The manager is built by
REM MSVC and links the DLL through an import library.
REM Environment: API_ROOT (default C:\Siemens\Automation\WinCC_OA\3.21\api),
REM MSYS2_ROOT (default C:\msys64).

setlocal enabledelayedexpansion

cd /d "%~dp0.."
set "REPO_DIR=%CD%"
set "OUT=%REPO_DIR%\build\embed-windows"
set "MANAGER_DIR=%REPO_DIR%\winccoa\manager"
set "BUILD_DIR=%MANAGER_DIR%\build"
if not defined API_ROOT set "API_ROOT=C:\Siemens\Automation\WinCC_OA\3.21\api"
if not defined MSYS2_ROOT set "MSYS2_ROOT=C:\msys64"

set "RUN_TEST=false"
set "CLEAN=false"
set "SKIP_DLL=false"
set "USE_MSYS2=false"
set "MMQ_CC="
set "INSTALL_PROJECT="

:parse_args
if "%~1"=="" goto :done_parse
if /i "%~1"=="--test"     (set "RUN_TEST=true"  & shift & goto :parse_args)
if /i "%~1"=="--clean"    (set "CLEAN=true"     & shift & goto :parse_args)
if /i "%~1"=="--skip-dll" (set "SKIP_DLL=true"  & shift & goto :parse_args)
if /i "%~1"=="--msys2"    (set "USE_MSYS2=true" & shift & goto :parse_args)
if /i "%~1"=="--cc" (
    if "%~2"=="" (echo --cc needs the path of a mingw-w64 gcc 1>&2 & exit /b 1)
    set "MMQ_CC=%~2"
    shift
    shift
    goto :parse_args
)
if /i "%~1"=="--install" (
    if "%~2"=="" (echo --install needs a project directory 1>&2 & exit /b 1)
    set "INSTALL_PROJECT=%~2"
    shift
    shift
    goto :parse_args
)
if /i "%~1"=="-h" goto :show_help
if /i "%~1"=="--help" goto :show_help
echo Unknown option: %~1 1>&2
call :usage
exit /b 1

:done_parse
call :check_tools
if errorlevel 1 exit /b 1
set /p VERSION=<"%REPO_DIR%\version.txt"
echo === WCCOAmmq Windows build (v%VERSION%, API_ROOT=%API_ROOT%) ===

if "%SKIP_DLL%"=="true" goto :dll_ready
call :build_dll
if errorlevel 1 exit /b 1
:dll_ready
call :check_dll
if errorlevel 1 exit /b 1
if "%RUN_TEST%"=="false" goto :tested
call :run_test
if errorlevel 1 exit /b 1
:tested
call :build_manager
if errorlevel 1 exit /b 1
if not defined INSTALL_PROJECT goto :installed
call :install
if errorlevel 1 exit /b 1
:installed
echo === Build Complete ===
exit /b 0

REM ---------------------------------------------------------------------------

:check_tools
for %%T in (cl lib cmake) do (
    where %%T >nul 2>&1
    if errorlevel 1 (
        echo %%T.exe not found: run this script from an "x64 Native Tools Command Prompt for VS 2022". 1>&2
        exit /b 1
    )
)
if defined VSCMD_ARG_TGT_ARCH if /i not "!VSCMD_ARG_TGT_ARCH!"=="x64" (
    echo The Visual Studio prompt targets !VSCMD_ARG_TGT_ARCH!: use the x64 Native Tools Command Prompt. 1>&2
    exit /b 1
)
if not exist "%API_ROOT%\CMakeDefines.txt" (
    echo Error: WinCC OA API not found at !API_ROOT! - set API_ROOT. 1>&2
    exit /b 1
)
exit /b 0

REM The compiler's directory and the Go variables stay local to this step, so
REM MSYS2 tools on PATH do not shadow the Visual Studio ones later.
:build_dll
setlocal
echo [1/3] Building monstermq.dll...
where go >nul 2>&1
if errorlevel 1 (
    echo go was not found on PATH. 1>&2
    exit /b 1
)
if "%USE_MSYS2%"=="true" set "MMQ_CC=%MSYS2_ROOT%\ucrt64\bin\gcc.exe"
if not defined MMQ_CC (
    where gcc >nul 2>&1
    if not errorlevel 1 set "MMQ_CC=gcc"
)
if not defined MMQ_CC if exist "%MSYS2_ROOT%\ucrt64\bin\gcc.exe" set "MMQ_CC=%MSYS2_ROOT%\ucrt64\bin\gcc.exe"
if not defined MMQ_CC (
    echo No mingw-w64 gcc found for cgo. Install MSYS2 and its UCRT64 gcc 1>&2
    echo ^(pacman -S mingw-w64-ucrt-x86_64-gcc^), put a mingw-w64 gcc on PATH, or pass --cc. 1>&2
    exit /b 1
)
if exist "%MMQ_CC%" for %%I in ("%MMQ_CC%") do set "PATH=%%~dpI;%PATH%"
echo C compiler: %MMQ_CC%
"%MMQ_CC%" -dumpmachine
if errorlevel 1 (
    echo Cannot run the C compiler !MMQ_CC!. 1>&2
    exit /b 1
)
call :sync_dashboard
if not exist "%OUT%" mkdir "%OUT%"
set "GOOS=windows"
set "GOARCH=amd64"
set "CGO_ENABLED=1"
set "CC=%MMQ_CC%"
go build -trimpath -tags winccoa_embed -buildmode=c-shared -ldflags="-X monstermq.io/edge/internal/version.Version=%VERSION%" -o "%OUT%\monstermq.dll" .\embed\cabi
if errorlevel 1 (
    echo Building monstermq.dll failed. 1>&2
    exit /b 1
)
REM go build writes its own monstermq.h next to the DLL; the published header replaces it.
for %%F in (monstermq.h monstermq_types.h monstermq.def) do copy /Y "embed\cabi\%%F" "%OUT%\" >nul
echo DLL built at: %OUT%\monstermq.dll
exit /b 0

REM Same sources as make prepare-dashboard, without building the dashboard:
REM without a dist folder the broker serves its placeholder page.
:sync_dashboard
set "DASH="
if exist "%REPO_DIR%\dashboard\dist\" set "DASH=%REPO_DIR%\dashboard\dist"
if not defined DASH if exist "%REPO_DIR%\..\dashboard\dist\" set "DASH=%REPO_DIR%\..\dashboard\dist"
if not defined DASH (
    echo Dashboard not found ^(dashboard\dist or ..\dashboard\dist^): the broker serves a placeholder page.
    exit /b 0
)
echo Syncing dashboard from %DASH%...
xcopy /E /I /Y /Q "%DASH%\*" "%REPO_DIR%\internal\dashboard\dist\" >nul
exit /b 0

:check_dll
for %%F in (monstermq.dll monstermq.def monstermq.h monstermq_types.h) do (
    if not exist "!OUT!\%%F" (
        echo Error: !OUT!\%%F not found. Build the DLL first ^(without --skip-dll, or make embed-dll in MSYS2^). 1>&2
        exit /b 1
    )
)
exit /b 0

:run_test
echo [2/3] Running the C ABI harness...
lib /nologo /machine:x64 /def:"%OUT%\monstermq.def" /out:"%OUT%\monstermq.lib"
if errorlevel 1 exit /b 1
cl /nologo /std:c11 /experimental:c11atomics /W3 /I"%OUT%" /Fo"%OUT%\abi_harness.obj" /Fe"%OUT%\abi_harness.exe" embed\harness\abi_harness.c "%OUT%\monstermq.lib" ws2_32.lib
if errorlevel 1 (
    echo Building the C ABI harness failed. 1>&2
    exit /b 1
)
pushd embed\harness
"%OUT%\abi_harness.exe"
set "RC=%errorlevel%"
popd
if not "%RC%"=="0" (
    echo C ABI harness failed. 1>&2
    exit /b 1
)
exit /b 0

:build_manager
echo [3/3] Building WCCOAmmq.exe...
if "%CLEAN%"=="true" if exist "%BUILD_DIR%" rmdir /S /Q "%BUILD_DIR%"
cmake -S "%MANAGER_DIR%" -B "%BUILD_DIR%" -G "Visual Studio 17 2022" -A x64
if errorlevel 1 exit /b 1
cmake --build "%BUILD_DIR%" --config Release
if errorlevel 1 exit /b 1
set "EXE="
if exist "%BUILD_DIR%\Release\WCCOAmmq.exe" set "EXE=%BUILD_DIR%\Release\WCCOAmmq.exe"
if not defined EXE for /f "delims=" %%F in ('dir /s /b "%BUILD_DIR%\WCCOAmmq.exe" 2^>nul') do set "EXE=%%F"
if not defined EXE (
    echo WCCOAmmq.exe not found below !BUILD_DIR!. 1>&2
    exit /b 1
)
echo Manager built at: %EXE%
exit /b 0

:install
if not exist "%INSTALL_PROJECT%\bin\" (
    echo Error: !INSTALL_PROJECT!\bin not found. 1>&2
    exit /b 1
)
for %%I in ("%EXE%") do set "EXE_DIR=%%~dpI"
for %%F in (WCCOAmmq.exe monstermq.dll) do (
    copy /Y "!EXE_DIR!%%F" "!INSTALL_PROJECT!\bin\" >nul
    if errorlevel 1 (
        echo Cannot copy %%F to !INSTALL_PROJECT!\bin: stop the manager first. 1>&2
        exit /b 1
    )
)
echo Installed to: %INSTALL_PROJECT%\bin
exit /b 0

:show_help
call :usage
exit /b 0

:usage
echo Usage: winccoa\build.bat [options]
echo.
echo Run from an "x64 Native Tools Command Prompt for VS 2022".
echo.
echo Options:
echo   --test               Run the C ABI harness against monstermq.dll
echo   --clean              Remove the CMake build directory first
echo   --install ^<project^>  Copy WCCOAmmq.exe and monstermq.dll to ^<project^>\bin
echo   --skip-dll           Use build\embed-windows as it is ^(make embed-dll in MSYS2^)
echo   --msys2              Build the DLL with %%MSYS2_ROOT%%\ucrt64\bin\gcc.exe
echo   --cc ^<gcc.exe^>       Build the DLL with this mingw-w64 gcc
echo   -h, --help           Show this help message
echo.
echo Environment: API_ROOT ^(default C:\Siemens\Automation\WinCC_OA\3.21\api^),
echo MSYS2_ROOT ^(default C:\msys64^)
goto :eof
