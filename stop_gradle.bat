@echo off
set JAVA_HOME=C:\Users\honey\jdk-17.0.13+11
set PATH=%JAVA_HOME%\bin;%PATH%
cd android
gradlew.bat --stop
cd..
