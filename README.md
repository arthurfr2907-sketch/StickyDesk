# StickyDesk

Des post-it pour le bureau du Mac : posés directement sur le bureau, sans barre de titre, avec une vraie mise en forme de texte.

## Fonctionnalités

- **Post-it sans bordure** posés sur le bureau (derrière les fenêtres) ou épinglés au premier plan, visibles sur tous les Spaces
- **Barre d'outils au survol**, qui s'adapte à la largeur du post-it :
  gras, italique, souligné · police · taille · couleur du texte · surligneur ·
  alignement · puces · liste numérotée · flèches · couleur du post-it
- **To-do lists** avec cases à cocher et compteur
- **Visible quand le Mac est verrouillé** (le rond ○/● de la barre) : le post-it est incrusté dans le fond d'écran
- Icône dans le **Dock** et dans la **barre de menus** : nouveau post-it, liste de tous les post-it, tout afficher / ranger
- Sauvegarde automatique (`~/Library/Application Support/StickyDesk/notes.json`)

## Installer

Prérequis : macOS 13 ou plus récent, Xcode (ou les Command Line Tools).

```bash
git clone <url-du-repo>
cd StickyDesk
./build-app.sh
```

Le script compile l'app, l'installe dans `/Applications` (ou `~/Applications`) et la lance.

## Raccourcis

| Raccourci | Action |
|---|---|
| ⌘N | Nouveau post-it |
| ⌘T | Nouvelle to-do list |
| ⌘W | Ranger le post-it |
| ⌘B / ⌘I / ⌘U | Gras / italique / souligné |
| ⌘+ / ⌘− | Taille du texte |

## Structure du code

| Fichier | Rôle |
|---|---|
| `main.swift` | Point d'entrée |
| `AppDelegate.swift` | Menus, icône du Dock et de la barre de menus |
| `NoteWindows.swift` | Fenêtres sans bordure, mise en forme du texte, listes |
| `NoteView.swift` | Interface d'un post-it et to-do lists |
| `NoteToolbar.swift` | Barre d'outils adaptative |
| `NoteTextEditor.swift` | Éditeur de texte enrichi |
| `LockScreen.swift` | Affichage sur l'écran verrouillé |
| `Models.swift` | Modèle de données, couleurs, polices |
| `NoteStore.swift` | Sauvegarde JSON |
