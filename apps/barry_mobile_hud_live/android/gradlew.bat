@ECHO OFF
WHERE gradle >NUL 2>&1
IF %ERRORLEVEL% EQU 0 (
  gradle %*
  EXIT /B %ERRORLEVEL%
)

echo Gradle is required but was not found in PATH.
echo Install Gradle or regenerate wrapper files with: gradle wrapper
EXIT /B 1
