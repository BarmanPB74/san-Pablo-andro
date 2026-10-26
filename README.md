# San Pablo: Medellín AI Tactics (`san-Pablo-andro`)

Juego de mundo abierto estilo **GTA V** ambientado en la topografía y estratificación socioeconómica de **Medellín, Colombia** (Valle de Aburrá), con arquitectura **Multi-Agente**, mecánicas de tácticas militares, **Letreros Destructibles de Inteligencia Artificial**, **Retenes Policiales con retos de Ciencias de la Computación** y red de transporte **SITVA (Metro / Metrocable / Tranvía)**.

## Estructura por Fases
- **Fase 1 (Actual):** Diseño de arquitectura Multi-Agente con protección de tokens, motor físico de cápsula e inercia en pendientes, 5 niveles socioeconómicos de Medellín (Santo Domingo Savio/Popular, Zamora/Moravia, Barrio Triste/La Candelaria, Robledo y El Poblado), minijuegos de Ciencias de la Computación y prototipo jugable Web/Mobile.
- **Fase 2 (Compilación APK):** Empaquetado nativo a `.apk` mediante CapacitorJS y Gradle.

## Cómo subir a GitHub (`BarmanPB74/san-Pablo-andro`)
```bash
git init
git branch -M main
git remote add origin https://github.com/BarmanPB74/san-Pablo-andro.git
git add .
git commit -m "feat(phase1): Medellin GTA-style open world, multi-agent supervisor & CS checkpoints"
git push -u origin main
```

## Cómo generar el archivo `.apk` cuando lo indiques
```bash
npm install
npm run android:init
npm run android:sync
npm run android:apk
```
