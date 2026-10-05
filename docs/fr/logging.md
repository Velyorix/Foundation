# Journalisation

Foundation écrit dans la console du serveur et dans son fichier journal
(`.logs/NanosWorldCore.log`), avec une ligne par enregistrement :

```
[foundation] <LEVEL> <owner>/<domain>: <message> <champ>=<valeur> ...
```

- `LEVEL` vaut `DEBUG`, `INFO `, `WARN ` ou `ERROR`.
- `owner` est le package concerné (`foundation` pour Foundation lui-même), `domain` la partie
  de Foundation qui a écrit la ligne.
- Les champs sont triés par nom. Les valeurs contenant des espaces, des guillemets ou `=` sont
  entre guillemets.
- Une erreur provoquée par un callback d'un package est suivie de sa trace d'appels.

Les avertissements et les erreurs passent par les sorties d'avertissement et d'erreur du
serveur : celui-ci ajoute donc ses propres lignes de pile après eux et les marque `S_WARN` et
`S_ERR` dans le fichier journal.

## Lignes attendues

| Ligne | Quand |
| --- | --- |
| `Foundation 0.1.0 started (API 0.1, server)` | Foundation a terminé son démarrage |
| `registered my-package 1.0.0 (API 0.1)` | Un package a appelé `Foundation.Register` |
| `my-package is ready` | Son événement `Load` a eu lieu et ses hooks de démarrage ont réussi |
| `my-package failed: <raison>` | Un hook de démarrage a échoué ou une dépendance s'est arrêtée |
| `my-package disabled: <raison>` | Le package a été déchargé ou désactivé |
| `<kind> callback of my-package failed` | Une fonction fournie par le package a levé une erreur |
| `Foundation was unloaded while ...` | Foundation a été rechargé seul ; suivez la commande indiquée dans le message |
| `Foundation stopped` | Foundation a terminé son arrêt |
| `created foundation/config/my-package.toml with the default settings` | Un fichier de configuration manquait et vient d'être écrit |
| `loaded foundation/config/my-package.toml` | Un fichier de configuration a été lu et accepté |
| `foundation/config/my-package.toml is not used; ...` | Le fichier est invalide ; les lignes précédentes listent les problèmes (voir [Configuration](configuration.md#modifier-un-fichier-sans-risque)) |
| `missing translation for 'my-package:some.key'` | Un package a demandé un texte qu'aucun de ses catalogues ne contient (journalisé une fois par clé) |
| `repeating task of my-package stopped after 3 consecutive failures` | Une tâche répétée a échoué plusieurs fois de suite et a été arrêtée |

Ces lignes sont données en anglais, la langue par défaut. Avec `language = "fr"`, elles sont
écrites en français.

## Niveau et langue

La section `[log]` de `foundation/config.toml` fixe le niveau minimum (`info` par défaut) et
les domaines dont les lignes de débogage sont toujours écrites. Le réglage `language` choisit
la langue des messages : l'anglais (`en`) et le français (`fr`) sont disponibles, les autres
langues utilisent l'anglais. Les lignes écrites pendant la lecture de
`foundation/config.toml` lui-même sont en anglais. Voir [Configuration](configuration.md).

Ces réglages s'appliquent aux lignes écrites par Foundation, quel que soit le package
concerné. Ils ne modifient pas le `log_level` propre au serveur.

## Secrets

Les valeurs des champs dont le nom contient `password`, `passwd`, `secret`, `token`,
`credential`, `authorization`, `connection_string`, `api_key` ou `apikey` sont remplacées par
`***`.

## Messages répétés

Quand une même ligne d'avertissement ou d'erreur est écrite plusieurs fois en moins de
10 secondes, seule la première est affichée. La fois suivante où elle apparaît après ce délai,
Foundation affiche d'abord `previous message repeated N more times`. Les lignes
d'information ne sont jamais supprimées.
