# Configuration

Foundation et les packages qui l'utilisent conservent leurs réglages dans des fichiers TOML
placés dans un dossier `foundation/`, à côté de l'exécutable du serveur :

```
NanosWorldServer.exe
Config.toml
foundation/
├── config.toml                 réglages de Foundation
└── config/
    └── my-package.toml         réglages du package my-package
```

Vous n'avez jamais à créer ces fichiers. Quand l'un d'eux manque, il est écrit avec les valeurs
par défaut et un commentaire au-dessus de chaque réglage.

## Réglages de Foundation

`foundation/config.toml`, tel qu'il est créé au premier démarrage :

<!-- example: tests/integration/packages/foundation-docs-examples-test/expected/config.toml -->
```toml
# Foundation configuration.
# Read when Foundation starts. Delete this file to recreate it with the default values.

# Format version of this file. Do not change it.
config_version = 1

# Language of Foundation's own messages, for example 'en' or 'fr'. Languages without a translation use English.
language = "en"

[log]
# Minimum level of Foundation's log lines: 'debug', 'info', 'warning' or 'error'.
level = "info"

# Parts of Foundation whose debug lines are written even when the level is above 'debug', for example ['config'].
debug_categories = []
```

| Réglage | Valeurs | Défaut | Effet |
| --- | --- | --- | --- |
| `language` | Code de langue : `en`, `fr`, ou un code régional comme `fr_CA` | `"en"` | Langue des messages de Foundation dans le journal et langue par défaut des traductions des packages (voir [Localisation](localization.md)). Foundation fournit l'anglais et le français ; les autres langues utilisent l'anglais. |
| `log.level` | `"debug"`, `"info"`, `"warning"`, `"error"` | `"info"` | Les lignes d'un niveau inférieur ne sont pas écrites. Voir [Journalisation](logging.md). |
| `log.debug_categories` | Liste de domaines, par exemple `["config"]` | `[]` | Domaines (la partie après `/` dans une ligne du journal) dont les lignes de débogage sont écrites quel que soit `log.level`. |

Ce fichier est toujours créé en anglais. Modifier `language` change la langue des messages, pas
les commentaires déjà présents dans le fichier.

## Réglages des packages

Un package qui déclare des réglages reçoit son propre fichier,
`foundation/config/<package>.toml`, où `<package>` est le nom du dossier du package. Les
commentaires du fichier décrivent chaque réglage ; la documentation du package vous en dit
plus. Les premières lignes sont écrites dans la langue du serveur, les commentaires de chaque
réglage sont fournis par le package. Par exemple :

<!-- example: tests/integration/packages/foundation-docs-examples-test/expected/foundation-example-rewards.toml -->
```toml
# Settings of Daily Rewards (foundation-example-rewards).
# Read when the package starts. Delete this file to recreate it with the default values.

# Format version of this file. Do not change it.
config_version = 1

# Give a reward on the first join of each day.
enabled = true

[reward]
# Amount of money given.
amount = 250

# Message shown with the reward.
message = "Here is your daily reward!"
```

## Quand les modifications s'appliquent

- `foundation/config.toml` est lu au démarrage de Foundation.
- Le fichier d'un package est lu au démarrage de ce package.

Redémarrez le serveur après avoir modifié un fichier. Pour appliquer le fichier d'un package
sans redémarrer, rechargez ce package avec la commande console `package reload <package>`. Ne
rechargez pas `foundation` seul : tous les packages qui l'utilisent cesseraient de fonctionner
jusqu'à ce qu'ils soient rechargés à leur tour.

## Modifier un fichier sans risque

- Un réglage retiré du fichier prend sa valeur par défaut. Les réglages inconnus sont refusés.
- Les valeurs sont vérifiées à la lecture du fichier. Si quoi que ce soit est incorrect
  (syntaxe TOML, mauvais type, valeur hors limites, réglage inconnu), **le fichier entier est
  ignoré** et les valeurs par défaut sont utilisées. Chaque problème est journalisé avec le
  réglage concerné :

  ```
  [foundation] ERROR my-package/config: foundation/config/my-package.toml is invalid (1 problem(s))
  [foundation] ERROR my-package/config: foundation/config/my-package.toml: $.motd: must have at most 32 characters
  [foundation] ERROR my-package/config: foundation/config/my-package.toml is not used; Foundation runs with the default settings until the file is fixed
  ```

  Foundation ne réécrit jamais un fichier existant : vos commentaires et votre mise en forme
  sont conservés. Corrigez le fichier puis redémarrez.
- Supprimez un fichier pour en obtenir une copie neuve avec les valeurs par défaut au
  prochain démarrage.
- Les valeurs des réglages qu'un package marque comme secrets (mots de passe, jetons) sont
  remplacées par `***` dans les lignes de journal de Foundation.

## Versions de format

`config_version` identifie la structure du fichier. Quand une mise à jour de Foundation ou d'un
package change cette structure, l'ancien fichier continue de fonctionner : il est converti en
mémoire à la lecture, et Foundation journalise :

```
[foundation] WARN  my-package/config: foundation/config/my-package.toml uses config_version 1; it was converted to version 2 in memory. Update the file to stop this message
```

Pour mettre le fichier à jour, supprimez-le pour qu'il soit recréé, puis recopiez vos valeurs.
Un fichier dont le `config_version` est plus récent que ce que la version installée prend en
charge est ignoré, et les valeurs par défaut sont utilisées.
