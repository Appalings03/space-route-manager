# Space Route Manager
Mod Factorio 2.0 + Space Age

## Ce que fait ce mod

Ajoute un bouton **"🚀 Routes"** directement dans le panneau de votre space platform hub (à côté des boutons existants comme l'énergie). Ce bouton ouvre une fenêtre qui liste toutes les destinations programmées du vaisseau et permet d'en activer ou désactiver individuellement.

## Installation

1. Copie le dossier `space-route-manager` dans :
   - **Windows** : `%APPDATA%\Factorio\mods\`
   - **Linux** : `~/.factorio/mods/`
2. Lance Factorio → Mods → vérifie que **Space Route Manager** est activé
3. Lance une partie avec **Space Age** activé

## Utilisation

1. **Clique sur un Space Platform Hub** pour ouvrir son panneau
2. Le bouton **"🚀 Routes"** apparaît dans l'interface (ou dans le panneau gauche en fallback)
3. Clique dessus → une fenêtre liste toutes les destinations du vaisseau :
   - ✅ **Vert** = route active
   - ❌ **Rouge** = route désactivée
4. Clique sur une destination pour basculer son état
5. Clique **"Appliquer"** → le schedule du vaisseau est mis à jour (les destinations désactivées sont ignorées)

## Notes techniques

- Les routes complètes sont sauvegardées en mémoire : désactiver puis réactiver une route la restaure exactement
- Chaque vaisseau est géré indépendamment
- Compatible avec les saves existantes

## Structure du mod

```
space-route-manager/
├── info.json          # Métadonnées du mod
├── data.lua           # Styles GUI et sprites
├── control.lua        # Logique principale
├── graphics/
│   └── route-icon.png # Icône du bouton
└── README.md
```
