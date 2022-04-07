@rem  Builds JetBrainsRuntime JDK11 for Windows, optionally creating distribution artifacts for it.
@rem  Usage:
@rem   build-jetbrainsruntime-win.cmd [-q] [-d <dist_dir>] [-o <out_dir>] -b <build_number>
@rem The JDK is built in <out_dir> (or "out" if unset).
@rem If <dist_dir> is set, the following artifacts are created there:
@rem   jdk.zip
@rem   jdk-runtime.zip
@rem   jdk-debuginfo.zip
@rem   configure.log
@rem  build.log
@rem Specify -q to suppress most of the output noise

@echo "In build-jetbrainsruntime-win.cmd"
@echo "Environment variables:"
@echo "==================================================="
set
@echo "==================================================="

@setlocal enabledelayedexpansion

set SCRIPT_DIR=%~dp0
set CYGWIN_DIR=c:\tools\cygwin
set OUT_DIR=%TMPDIR%\out_jbr_win_%BUILD_NUMBER%

@rem mkdir %OUT_DIR%
@rem mklink /J %OUT_DIR%\vs "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools"

%CYGWIN_DIR%\bin\bash -l %SCRIPT_DIR%build-jetbrainsruntime-win.sh -d %DIST_DIR% -b %BUILD_NUMBER% -o %OUT_DIR%