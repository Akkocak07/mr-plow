# Mr. Plow – spielbarer Godot-Prototyp

Dieser Prototyp benötigt **Godot 4.x** und keine externen Grafiken oder Plugins.

## Installation in dein vorhandenes Repository

1. Beende Godot.
2. Sichere deinen bisherigen Stand am besten zuerst mit Git.
3. Entpacke den Inhalt der ZIP-Datei direkt in deinen Ordner `mr-plow`.
4. Erlaube das Überschreiben von `project.godot` und `scenes/main.tscn`.
5. Öffne danach `project.godot` mit Godot und drücke **F6** oder **F5**.

Deine vorhandenen Dateien `README.md`, `LICENSE`, `.gitignore` und der versteckte
Ordner `.git` werden durch dieses Paket nicht ersetzt.

## Steuerung

- **WASD:** laufen
- **Leertaste oder linke Maustaste halten:** Schnee räumen
- **U:** nächstes Upgrade kaufen
- **R:** neuen Schnee erzeugen

## Enthalten

- 3D-Grundstück mit Haus, Bäumen und Zaun
- steuerbarer Spieler
- folgende Kamera
- 169 einzeln räumbare Schneefelder
- Geldsystem
- drei Werkzeug-Upgrades
- vollständig programmatisch erstellte Modelle, daher keine externen Assets

## Dateien

- `project.godot`
- `scenes/main.tscn`
- `scripts/main.gd`
- `scripts/player.gd`
