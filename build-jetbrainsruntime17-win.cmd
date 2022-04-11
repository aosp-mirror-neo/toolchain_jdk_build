@rem  Builds JetBrainsRuntime JDK17 for Windows, optionally creating distribution artifacts for it.
@rem  Usage:
@rem   build-jetbrainsruntime17-win.cmd [-q] [-d <dist_dir>] [-o <out_dir>] -b <build_number>
@rem The JDK is built in <out_dir> (or "out" if unset).
@rem If <dist_dir> is set, the following artifacts are created there:
@rem   jdk.zip
@rem   jdk-runtime.zip
@rem   jdk-debuginfo.zip
@rem   configure.log
@rem  build.log
@rem Specify -q to suppress most of the output noise

@echo "In build-jetbrainsruntime17-win.cmd"

@setlocal enabledelayedexpansion

set SCRIPT_DIR=%~dp0
set CYGWIN_DIR=c:\tools\cygwin

@rem TODO update openjdk.gcl and replace hardcoded args with %CYGWIN_DIR%\bin\bash -l %SCRIPT_DIR%build-jetbrainsruntime17-win.sh %*
%CYGWIN_DIR%\bin\bash -l %SCRIPT_DIR%build-jetbrainsruntime17-win.sh -d %DIST_DIR% -b %BUILD_NUMBER% -o %TMPDIR%\out