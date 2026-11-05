#!/bin/bash
if [ -d "/Users/melanigrandi/ANTY/PRESUPUESTO" ]; then
    cd "/Users/melanigrandi/ANTY/PRESUPUESTO"
else
    cd "$(dirname "$0")"
fi

echo "========================================================"
echo "  🚀 SG MONTAJES SRL — INICIANDO SERVIDOR Y APLICACIÓN"
echo "========================================================"

# Cerrar cualquier instancia previa en el puerto 8000
echo "Liberando puerto 8000..."
PID_OLD=$(lsof -ti :8000)
if [ -n "$PID_OLD" ]; then
    kill -9 $PID_OLD 2>/dev/null
    echo "Proceso anterior finalizado."
fi

# Lanzar servidor Python
echo "Iniciando backend Python..."
python3 -u server.py &
SERVER_PID=$!

sleep 1.5

# Abrir el navegador en http://localhost:8000
echo "Abriendo aplicación en el navegador..."
open "http://localhost:8000"

echo "========================================================"
echo "  ✅ Servidor activo en http://localhost:8000"
echo "  (No cierres esta ventana mientras uses el sistema)"
echo "========================================================"

wait $SERVER_PID
