#!/bin/bash
cd "$(dirname "$0")"

echo "========================================================"
echo "  🚀 SUBIENDO ACTUALIZACIONES A GITHUB (SG MONTAJES)    "
echo "========================================================"
echo ""

git status

echo ""
echo ">> Subiendo cambios a la rama principal (main)..."
git push origin main

if [ $? -eq 0 ]; then
    echo ""
    echo "========================================================"
    echo "  ✅ Actualizaciones subidas con éxito a GitHub y Render"
    echo "========================================================"
else
    echo ""
    echo "⚠️ Hubo un detalle al subir. Revisa tus credenciales de GitHub."
fi

echo ""
read -p "Presiona Enter para cerrar esta ventana..."
