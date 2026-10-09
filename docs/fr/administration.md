# Commandes d'administration

Foundation ajoute une commande `foundation` à la console du serveur. Dans cette version, elle
ne s'utilise que depuis la console, pas par les joueurs.

| Commande | Effet |
| --- | --- |
| `foundation version` | Affiche la version de Foundation et la version de l'API |
| `foundation help` | Liste toutes les commandes avec leur usage et leur description |
| `foundation help <commande>` | Décrit une commande : usage, alias, sous-commandes |
| `foundation packages` | Liste les packages qui utilisent Foundation, avec leur version et leur état |
| `foundation reload-config` | Recharge tous les fichiers de configuration sans redémarrer |

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
