@echo off
setlocal enabledelayedexpansion
set CP=.
for /r "C:\Users\djbap\.gradle\caches\modules-2\files-2.1" %%f in (*.jar) do (
    set "CP=!CP!;%%f"
)
java -cp "!CP!" %*
