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

Les messages sont actuellement écrits en anglais.

## Secrets

Les valeurs des champs dont le nom contient `password`, `passwd`, `secret`, `token`,
`credential`, `authorization`, `connection_string`, `api_key` ou `apikey` sont remplacées par
`***`.

## Messages répétés

Quand une même ligne d'avertissement ou d'erreur est écrite plusieurs fois en moins de
10 secondes, seule la première est affichée. La fois suivante où elle apparaît après ce délai,
Foundation affiche d'abord `previous message repeated N more time(s)`. Les lignes
d'information ne sont jamais supprimées.
