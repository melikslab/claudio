#!/bin/zsh
# Crea el instalador DMG (ventana con Claudio, una flecha y la carpeta Aplicaciones).
#   scripts/make-dmg.sh            build/Claudio.app       → build/Claudio-AppleSilicon.dmg
#   scripts/make-dmg.sh --intel    build/intel/Claudio.app → build/Claudio-Intel.dmg
# Antes hay que compilar con ./build-app.sh (o ./build-app.sh --intel).
set -e
cd "$(dirname "$0")/.."

if [[ "$1" == "--intel" ]]; then
    APP=build/intel/Claudio.app
    DMG=build/Claudio-Intel.dmg
else
    APP=build/Claudio.app
    DMG=build/Claudio-AppleSilicon.dmg
fi
[[ -d "$APP" ]] || { echo "No existe $APP: compila primero con ./build-app.sh $1"; exit 1; }

# dmgbuild coloca iconos y fondo sin abrir el Finder, así que también funciona en el CI.
VENV=.build/dmg-venv
[[ -x "$VENV/bin/dmgbuild" ]] || { python3 -m venv "$VENV" && "$VENV/bin/pip" install -q dmgbuild; }

rm -f "$DMG"
"$VENV/bin/dmgbuild" -s scripts/dmg-settings.py \
    -D app="$APP" -D background=Resources/dmg-background.png \
    Claudio "$DMG"
echo "Listo: $(pwd)/$DMG"
