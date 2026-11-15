#!/bin/sh
# Ejecutar en un Mac desde la carpeta del proyecto:  sh setup-mac.sh
# Instala XcodeGen si falta, genera QuestMapIRL.xcodeproj y lo abre en Xcode.
set -e

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew no está instalado. Instálalo desde https://brew.sh y vuelve a ejecutar este script."
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Instalando XcodeGen…"
  brew install xcodegen
fi

echo "Generando QuestMapIRL.xcodeproj…"
xcodegen generate

echo "Abriendo en Xcode…"
open QuestMapIRL.xcodeproj

echo
echo "Listo. En Xcode: elige un simulador de iPhone y pulsa ⌘R."
echo "Para probar en tu iPhone, pon tu Team ID en project.yml (DEVELOPMENT_TEAM) y vuelve a ejecutar este script."
