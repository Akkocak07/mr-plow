# Mr. Plow – First-Person-Version

Diese Version verwendet ausschließlich Godot-Grundformen. Es werden keine
externen Modelle oder Plugins benötigt.

## Enthaltene Funktionen

- Ego-Perspektive mit Maussteuerung
- sichtbares Werkzeug vor der Kamera
- Werkzeugbewegung beim Schneeräumen
- vier unterschiedliche Werkzeugmodelle:
  1. einfache Schneeschaufel
  2. breite Schneeschaufel
  3. elektrische Schneefräse
  4. kompakter Schneepflug
- 225 räumbare Schneefelder
- Geld- und Upgrade-System
- Grundstück mit Haus, Fenstern, Bäumen und Zaun
- Fadenkreuz und HUD

## Steuerung

- `W`, `A`, `S`, `D`: laufen
- Maus: umsehen
- linke Maustaste oder Leertaste: Schnee räumen
- `U`: nächstes Upgrade kaufen
- `R`: neuen Schnee erzeugen
- `Esc`: Mauszeiger freigeben oder wieder einfangen

## Installation über das Terminal

Godot vorher schließen. Passe den Pfad nur an, falls dein Projekt woanders liegt:

```bash
unzip -o ~/Downloads/mr-plow-first-person.zip \
  -d ~/Dokumente/Projekte/mr-plow
```

Danach `project.godot` erneut mit Godot öffnen und `F5` drücken.

Die ZIP überschreibt nur:

- `project.godot`
- `scenes/main.tscn`
- `scripts/main.gd`
- `scripts/player.gd`

Sie enthält weder `.git` noch `.gitignore`, `LICENSE` oder dein normales
`README.md`.

## Nach erfolgreichem Test sichern

```bash
git add .
git commit -m "Add first-person tools and upgrades"
git push
```
