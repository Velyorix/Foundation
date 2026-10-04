# Prérequis

## Serveur

| Prérequis | Valeur |
| --- | --- |
| Serveur nanos world | 1.156 ou plus récent |
| Système d'exploitation | Toute plateforme prise en charge par le serveur nanos world. Testé sous Windows ; Linux n'est pas encore testé |
| Options du serveur | Aucune. Foundation n'a pas besoin de `--enable_unsafe_libs` |
| Modules natifs | Aucun. Foundation est entièrement écrit en Lua |

Foundation fonctionne avec n'importe quel game-mode. C'est un package `script` : il ne
remplace pas le `game_mode` défini dans `Config.toml`.

## Joueurs

Les joueurs n'ont besoin que du client nanos world. Comme pour tout package, les fichiers du
dossier `Shared/` de Foundation sont téléchargés par les clients à la connexion ; ils ne
contiennent ni données serveur ni identifiants.

## Développeurs de packages

- Un serveur nanos world 1.156 ou plus récent pour les tests.
- Les packages qui utilisent Foundation le déclarent comme dépendance afin qu'il soit toujours
  chargé en premier :

```toml
# Package.toml de votre package
[script]
    packages_requirements = [
        "foundation",
    ]
```

Voir [Compatibilité](compatibility.md) pour les versions testées.
