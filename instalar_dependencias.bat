@echo off
title Instalador de Dependencias Python - Hemacias Analyzer v1.2
chcp 65001 >nul
echo ======================================================================
echo          HEMACIAS ANALYZER v1.2 - INSTALACAO DE DEPENDENCIAS
echo                             Maurinsoft
echo ======================================================================
echo.
echo Verificando instalacao do Python no sistema...

set "PYTHON_CMD="

where python >nul 2>&1
if %errorlevel% equ 0 (
    set "PYTHON_CMD=python"
) else (
    where py >nul 2>&1
    if %errorlevel% equ 0 (
        set "PYTHON_CMD=py -3"
    )
)

if "%PYTHON_CMD%"=="" (
    echo [ERRO] Python nao foi encontrado no PATH do sistema!
    echo.
    echo O Hemacias Analyzer necessita do Python 3 (versao 3.10 ou superior)
    echo para a deteccao de cameras via OpenCV e processamento de IA (YOLO).
    echo.
    echo Por favor, instale o Python marcando a opcao:
    echo    "[X] Add python.exe to PATH"
    echo.
    echo Pressione qualquer tecla para abrir a pagina oficial de download do Python...
    pause >nul
    start https://www.python.org/downloads/
    exit /b 1
)

echo [OK] Python detectado com sucesso:
%PYTHON_CMD% --version
echo.

echo Atualizando pip...
%PYTHON_CMD% -m pip install --upgrade pip

echo.
echo Instalando dependencias essenciais de Visao Computacional e IA:
echo  1. OpenCV (Captura e comunicacao com camera de microscopio)
echo  2. NumPy (Processamento matricial de alta performance)
echo  3. Pillow (Suporte a imagens)
echo  4. Ultralytics (Motor de inferencia YOLOv8/YOLO11)
echo.

echo Instalando PyTorch otimizado para CPU...
%PYTHON_CMD% -m pip install --extra-index-url https://download.pytorch.org/whl/cpu torch torchvision

echo.
echo Instalando Ultralytics, OpenCV, NumPy e Pillow...
%PYTHON_CMD% -m pip install opencv-python numpy Pillow ultralytics

if %errorlevel% neq 0 (
    echo.
    echo [AVISO] Tentando instalar a partir do arquivo de requisitos...
    if exist "%~dp0requirements-ml.txt" (
        %PYTHON_CMD% -m pip install -r "%~dp0requirements-ml.txt"
    ) else if exist "%~dp0requirements.txt" (
        %PYTHON_CMD% -m pip install -r "%~dp0requirements.txt" ultralytics
    )
)

echo.
echo ======================================================================
echo             INSTALACAO DE DEPENDENCIAS CONCLUIDA!
echo   O Hemacias Analyzer v1.2 esta pronto para analise de laminas e IA.
echo ======================================================================
echo.
pause
