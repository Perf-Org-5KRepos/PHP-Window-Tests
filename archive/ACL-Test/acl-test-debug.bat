@echo OFF
echo Generating debug build...
cscript /nologo %~dp0\tools\generate-debug.js %~dp0\acl-test.js
echo Executing debug build...
cscript /nologo %~dp0\acl-test.debug.js %*