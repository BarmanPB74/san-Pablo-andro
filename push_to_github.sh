#!/usr/bin/env bash
set -e
echo "Inicializando repositorio para https://github.com/BarmanPB74/san-Pablo-andro..."
git init
git branch -M main
git remote remove origin 2>/dev/null || true
git remote add origin https://github.com/BarmanPB74/san-Pablo-andro.git
git add .
git commit -m "feat(phase1): San Pablo Medellin AI Tactics open-world prototype & Capacitor Android setup"
git push -u origin main
echo "Push completado exitosamente."
