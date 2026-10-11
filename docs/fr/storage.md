# Stockage

Foundation donne à chaque package des **espaces de stockage** : des emplacements où il garde
des valeurs sous des clés textuelles, enregistrées sur le disque et conservées après un
redémarrage ou un rechargement du package. Les valeurs sont toutes les données Lua qui
s'écrivent en JSON : nombres, chaînes, booléens et tables. Chaque opération est asynchrone et
renvoie une [future](scheduling.md#futures).

Pour des valeurs liées à un joueur ou à un autre sujet, avec un schéma et une valeur par
défaut, utilisez les [données persistantes](persistent-data.md), construites sur les espaces de
stockage.

## Le fichier de données

Tout est conservé dans un seul fichier SQLite, `foundation/data/foundation.db`, à côté de
l'exécutable du serveur. Foundation le crée au premier démarrage et journalise :

```
[foundation] INFO  foundation/storage: storage opened at foundation/data/foundation.db
```

- **Sauvegardes** : copiez le fichier pendant que le serveur est arrêté.
- **Rien n'est supprimé** quand un package s'arrête, est rechargé ou est retiré du serveur :
  ses données attendent dans le fichier jusqu'à ce que le package soit réinstallé. Seul le
  package lui-même supprime ses clés.
- À l'arrêt du serveur, Foundation écrit toutes les opérations encore en attente, y compris
  celles faites par les packages pendant leur arrêt, avant de fermer le fichier.
- Si le fichier ne peut pas être ouvert (droits manquants, fichier endommagé), l'erreur est
  journalisée et chaque espace refuse ses opérations avec `storage_unavailable` ; Foundation ne
  se replie jamais sur une conservation en mémoire, où les données seraient perdues.

La taille de chaque espace est limitée, voir [Quotas](#quotas).

## Exemple

<!-- example: tests/integration/packages/foundation-example-warps/Server/Index.lua -->
```lua
local context = Foundation.Register(Package, {
    api = "0.1",
    name = "Warps",
})

-- Version 1 stored { x, y, z }; version 2 adds the map name.
local warps = context:Store("warps", {
    version = 2,
    migrations = {
        [1] = function(entries)
            for name, position in pairs(entries) do
                entries[name] = { map = "default", position = position }
            end
            return entries
        end,
    },
})

context:RegisterCommand({
    name = "warp",
    subcommands = {
        {
            name = "set",
            arguments = {
                { name = "name", min = 1, max = 32 },
                { name = "x", type = "number" },
                { name = "y", type = "number" },
                { name = "z", type = "number" },
            },
            run = function(sender, args)
                warps
                    :Set(args.name, { map = "default", position = { args.x, args.y, args.z } })
                    :Then(function()
                        sender:Reply("warp " .. args.name .. " saved")
                    end)
                    :Catch(function(err)
                        sender:Reply("warp not saved: " .. err.message)
                    end)
            end,
        },
        {
            name = "show",
            arguments = { { name = "name" } },
            run = function(sender, args)
                warps:Get(args.name):Then(function(warp)
                    if warp == nil then
                        sender:Reply("no warp named " .. args.name)
                        return
                    end
                    local x, y, z = table.unpack(warp.position)
                    sender:Reply(string.format("%s: %g %g %g on %s", args.name, x, y, z, warp.map))
                end)
            end,
        },
        {
            name = "list",
            run = function(sender)
                warps:Keys():Then(function(names)
                    sender:Reply(#names .. " warp(s): " .. table.concat(names, ", "))
                end)
            end,
        },
        {
            name = "delete",
            arguments = { { name = "name" } },
            run = function(sender, args)
                warps:Delete(args.name):Then(function(existed)
                    sender:Reply(existed and ("warp " .. args.name .. " deleted") or ("no warp named " .. args.name))
                end)
            end,
        },
    },
})
```

Dans la console du serveur :

```
warp set arena 1200.5 -40 100
[foundation] warp arena saved
warp show arena
[foundation] arena: 1200.5 -40 100 on default
warp list
[foundation] 1 warp(s): arena
```

Les warps sont toujours là après un redémarrage.

## Ouvrir un espace

`context:Store(name, options)` renvoie un espace de stockage de votre package.

- Sans `name`, vous obtenez l'espace principal du package. Avec un nom (lettres minuscules,
  chiffres, `_` et `-`), vous obtenez un espace séparé, par exemple un par type de données.
- Un nouvel appel avec le même nom renvoie le même espace.
- `options` déclare une [version et des migrations](#versions-et-migrations) ; omettez-le pour
  un espace sans version.

L'espace est utilisable tout de suite : les opérations faites pendant qu'il lit ses clés sur le
disque attendent, puis s'exécutent dans l'ordre.

## Lire et écrire

| Méthode | Résolue avec |
| --- | --- |
| `store:Get(key)` | La valeur, ou `nil` quand la clé n'existe pas |
| `store:Set(key, value)` | `true` une fois la valeur écrite |
| `store:Delete(key)` | `true` si la clé existait, `false` sinon |
| `store:Keys(prefix, limit)` | Les clés qui commencent par `prefix` (toutes sans lui), triées, au plus `limit` (10000 au maximum) |
| `store:Batch(operations)` | `true` une fois toutes les opérations écrites |

- Les clés sont des chaînes non vides de 256 caractères au plus, sans caractère de contrôle.
  Utilisez des préfixes pour les regrouper, comme `homes/76561198000000001/house`, puis listez
  un groupe avec `Keys`.
- `Set` refuse `nil` (utilisez `Delete`) et les valeurs qui ne s'écrivent pas en JSON :
  fonctions, userdata, nombres non finis, tables qui se contiennent elles-mêmes, tables qui
  mélangent une liste et des champs nommés, tables imbriquées sur plus de 32 niveaux, ou
  valeurs dont le JSON dépasse 1 Mo (1048576 octets). Ce sont des erreurs de programmation :
  l'appel lève une erreur à votre ligne.
- Les entiers restent des entiers et les nombres décimaux restent décimaux.
- `Get` renvoie une nouvelle table à chaque fois : la modifier ne change rien dans l'espace
  tant que vous n'appelez pas `Set`.
- Les opérations d'un package s'exécutent dans l'ordre où elles sont faites : un `Get` fait
  après un `Set` voit la nouvelle valeur, même avant que la future du `Set` soit résolue.
- Quand la future d'un `Set`, d'un `Delete` ou d'un `Batch` est résolue, le changement est sur
  le disque.

`store:Batch(operations)` applique plusieurs changements ensemble : soit ils sont tous écrits,
soit aucun.

```lua
store:Batch({
    { op = "set", key = "kits/starter", value = { "pistol", "bandage" } },
    { op = "delete", key = "kits/old" },
})
```

`store:Usage()` répond immédiatement avec `{ count, bytes, max_keys, max_bytes }`, et
`store:GetName()` avec le nom de l'espace (`<package>` ou `<package>/<name>`).

## Échecs

Les futures sont rejetées avec une [valeur d'erreur](reference/foundation.md#erreurs) :

| Code | Quand |
| --- | --- |
| `storage_quota` | L'écriture ferait dépasser son [quota](#quotas) à l'espace ; rien n'est écrit |
| `storage_failed` | Le disque a refusé l'opération ; l'espace reste tel qu'il était avant l'appel |
| `storage_unavailable` | Le fichier de données n'a pas pu être ouvert, ou l'espace n'a pas pu lire ses clés ni migrer ses données |
| `storage_corrupt` | Le texte enregistré pour cette clé n'est pas du JSON valide (le fichier a été modifié à la main) |

## Quand votre package s'arrête

Utiliser un espace après l'arrêt de votre package lève `invalid_state`. Les écritures faites
avant, y compris dans `context:OnDisable`, sont quand même écrites. Quand le package redémarre,
`context:Store` donne accès aux mêmes données.

## Versions et migrations

Quand la forme de vos valeurs change entre deux versions de votre package, déclarez une version
et les fonctions qui convertissent les anciennes données :

```lua
local warps = context:Store("warps", {
    version = 2,
    migrations = {
        [1] = function(entries)
            -- convert version 1 to version 2
            return entries
        end,
    },
})
```

- `version` est un entier, 1 ou plus. Un espace ouvert sans `options` n'a pas de version.
- `migrations[n]` convertit la version `n` en version `n + 1`. Chaque étape de 1 à
  `version - 1` doit être présente.
- Une migration reçoit toutes les entrées de l'espace sous forme de table `{ [key] = value }`
  et renvoie la table des entrées de la version suivante. Elle peut modifier, ajouter ou
  retirer des entrées.
- Foundation exécute les étapes manquantes à l'ouverture de l'espace, puis écrit les entrées
  modifiées et la nouvelle version en une seule transaction, et journalise
  `migrated 'foundation-example-warps/warps' from version 1 to 2 (3 change(s))`.
- Les données enregistrées avant l'ajout d'une version comptent comme version 1. Un espace
  neuf et vide enregistre simplement la version déclarée.

Si une migration lève une erreur ou renvoie quelque chose qui ne peut pas être enregistré, si
les données enregistrées sont plus récentes que la version déclarée (une ancienne version du
package a été installée par-dessus une plus récente), ou si le résultat ne peut pas être
écrit, **rien n'est modifié** dans le fichier : l'erreur est journalisée, l'espace refuse
toutes les opérations et votre package passe à l'état `failed` (voir
[Cycle de vie](lifecycle.md)). Corrigez le package, ou réinstallez la version plus récente, et
redémarrez-le.

## Quotas

Chaque espace a deux limites, fixées par l'administrateur du serveur dans
[`foundation/config.toml`](configuration.md#réglages-de-foundation) :

| Réglage | Défaut |
| --- | --- |
| `storage.max_bytes_per_package` | 50 Mo : somme des longueurs de chaque clé et de sa valeur JSON |
| `storage.max_keys_per_package` | 100000 clés |

Elles s'appliquent à chaque espace séparément : l'espace principal d'un package, chaque espace
nommé et ses [données persistantes](persistent-data.md) ont chacun leur propre compte. Une
écriture qui dépasserait une limite est rejetée avec `storage_quota` ; les écritures qui
réduisent l'espace sont toujours acceptées. Les changements de limites s'appliquent après
`foundation reload-config`.

Voir la [référence](reference/storage.md) pour toutes les méthodes et erreurs.
