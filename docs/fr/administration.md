# Commandes d'administration

Foundation ajoute une commande `foundation`, tapée dans la console du serveur ou, avec la
permission correspondante, dans le chat (`/foundation ...`). La console peut utiliser toutes
les sous-commandes ; les joueurs ont besoin de la permission indiquée dans
[Qui peut les utiliser](#qui-peut-les-utiliser).

| Commande | Effet |
| --- | --- |
| `foundation version` | Affiche la version de Foundation et la version de l'API |
| `foundation help` | Liste toutes les commandes avec leur usage et leur description |
| `foundation help <commande>` | Décrit une commande : usage, alias, sous-commandes |
| `foundation packages` | Liste les packages qui utilisent Foundation, avec leur version et leur état |
| `foundation services` | Liste les services, leurs fournisseurs, les packages qui en ont besoin, et les capacités |
| `foundation reload-config` | Recharge tous les fichiers de configuration sans redémarrer |
| `foundation op add <compte> [nom]` | Rend un compte opérateur |
| `foundation op remove <compte>` | Retire un opérateur |
| `foundation op list` | Liste les opérateurs |
| `foundation permissions check <compte> <permission>` | Indique si un compte a une permission, et pourquoi |
| `foundation permissions list [package]` | Liste les permissions déclarées |

Taper `foundation` seul liste les sous-commandes.

## Exemples

```
> foundation help buy
buy <item> [amount] - Buy an item

> foundation packages
Packages (2):
shop 1.0.0 - ready
loyalty 1.0.0 - failed: a ready hook of 'loyalty' failed
```

Les lignes d'usage indiquent les arguments obligatoires sous la forme `<nom>`, les facultatifs
sous la forme `[nom]`, et ceux qui prennent la fin de la ligne sous la forme `<nom...>`.

Les états des packages sont `initializing`, `ready`, `failed` (avec la raison) et `disabled`.
Voir [Cycle de vie](lifecycle.md).

Les réponses sont écrites dans la langue du serveur (réglage `language`) ; les exemples
ci-dessus sont en anglais.

## Services

`foundation services` indique quel package fournit chaque service et quels packages en ont
besoin. `MISSING` signale un besoin qu'aucun fournisseur ne satisfait, raison habituelle de
l'échec au démarrage d'un package :

```
> foundation services
Services (2):
chat:format
  no provider
  used if present by: shop (any version, MISSING)
economy:bank
  provided by: coins 1.2 (priority 10), gems 1.0 (priority 0)
  required by: shop (1.1), auction (2, MISSING)
Capabilities (1):
  chat:emotes: chat-plus 2.1
```

Les fournisseurs sont listés dans l'ordre où ils sont choisis. Pour corriger un service
manquant, installez un package qui le fournit dans une version compatible, ou retirez le
package qui l'exige. Voir [Services et capacités](services.md).

## Recharger la configuration

`foundation reload-config` relit `foundation/config.toml` et tous les fichiers de réglages des
packages, et répond une ligne par fichier :

```
> foundation reload-config
foundation/config.toml: no change
foundation/config/shop.toml: 1 setting changed
foundation/config/shop.toml: restart the server to apply port
```

- Les réglages qu'un package déclare rechargeables s'appliquent tout de suite, et le package en
  est informé. Les autres gardent leur valeur jusqu'au prochain redémarrage ; la réponse les
  liste.
- Un fichier contenant une erreur est refusé en entier : les réglages actuels restent en
  vigueur, et les problèmes sont dans le journal (voir
  [Configuration](configuration.md#modifier-un-fichier-sans-risque)).
- Chaque rechargement est enregistré dans le journal d'audit,
  `foundation/audit/audit-<date>.log`.

Les réglages de Foundation (`language`, `[log]`, `[commands]`) s'appliquent tous tout de suite.

## Qui peut les utiliser

| Permission | Défaut | Commandes |
| --- | --- | --- |
| `foundation.command.version` | tout le monde | `foundation version` |
| `foundation.command.help` | tout le monde | `foundation help` |
| `foundation.command.packages` | opérateurs | `foundation packages` |
| `foundation.command.services` | opérateurs | `foundation services` |
| `foundation.command.reload-config` | opérateurs | `foundation reload-config` |
| `foundation.command.op` | opérateurs | `foundation op ...` |
| `foundation.command.permissions` | opérateurs | `foundation permissions ...` |

Un package de permissions peut accorder ces permissions à d'autres comptes. Voir
[Permissions](permissions.md).

## Opérateurs

Les opérateurs ont toutes les permissions dont la valeur par défaut est `operators`, y compris
celles ci-dessus. Ils sont identifiés par leur identifiant de compte : la liste s'applique donc
aussi aux joueurs hors ligne.

```
> foundation op add 76561198000000001 Alex
76561198000000001 is now an operator
> foundation op list
Operators (1):
  76561198000000001 Alex (added by console)
> foundation op remove 76561198000000001
76561198000000001 is no longer an operator
```

Le nom facultatif n'est qu'un aide-mémoire pour les administrateurs. Chaque changement est
enregistré dans le journal d'audit avec le compte qui l'a fait.

La liste est conservée dans `foundation/operators.json` ; sauvegardez-la avec le reste du
dossier `foundation/`. Modifiez-la avec `foundation op` plutôt qu'à la main. Si le fichier ne
peut pas être lu, Foundation journalise pourquoi, personne n'est opérateur, et `foundation op`
refuse les modifications jusqu'à ce que le fichier soit corrigé ou supprimé ; le fichier
lui-même n'est jamais réécrit.

## Vérifier les permissions

`foundation permissions check` affiche la décision et son origine :

```
> foundation permissions check 76561198000000009 arena.manage
arena.manage for 76561198000000009: allowed (attachment from arena)
  declared by arena, default: operators
  Start matches and appoint referees
```

L'origine est `console`, `attachment from <package>` (une autorisation ou un refus temporaire
posé par un package), `provider <package>` (un package de permissions) ou `declared default`
(la valeur par défaut déclarée).
