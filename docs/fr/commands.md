# Commandes

Un package déclare ses commandes une fois ; Foundation lit ce que les joueurs tapent dans le
chat et ce que les administrateurs tapent dans la console du serveur, vérifie les arguments
et appelle la fonction du package avec les valeurs converties. La commande `buy` de
l'[exemple des événements](events.md#exemple) est un exemple complet.

## Déclarer une commande

```lua
context:RegisterCommand({
    name = "home",
    aliases = { "h" },
    description = "Teleport to one of your homes",
    arguments = { { name = "name", default = "home" } },
    run = function(sender, args)
        sender:Reply("Teleporting to " .. args.name)
    end,
    subcommands = {
        {
            name = "set",
            arguments = { { name = "name" }, { name = "note", type = "greedy", optional = true } },
            senders = { "player" },
            cooldown = 5000,
            run = set_home,
        },
    },
})
```

| Champ | Signification |
| --- | --- |
| `name` | La commande, `home` ci-dessus. Lettres minuscules, chiffres, `_` et `-`, commençant par une lettre, 32 caractères au plus |
| `aliases` | D'autres noms pour la même commande |
| `description` | Texte affiché par `foundation help`. Ou `description_key` : une clé de vos [catalogues](localization.md), traduite |
| `arguments` | Les valeurs attendues, voir [Arguments](#arguments) |
| `run` | `run(sender, args, info)`, appelée avec les arguments convertis, par nom |
| `subcommands` | Les commandes placées sous celle-ci (`home set`), déclarées avec les mêmes champs |
| `senders` | `{ "player" }` ou `{ "console" }` pour n'accepter qu'un type d'expéditeur ; les deux par défaut |
| `cooldown` | Millisecondes qu'un joueur doit attendre avant de réutiliser la commande |
| `audit` | `true` pour enregistrer chaque utilisation dans le [journal d'audit](#audit) |

Une commande a besoin de `run`, de `subcommands`, ou des deux. Un mot qui n'est pas une
sous-commande est transmis comme argument.

`RegisterCommand` renvoie un handle : `handle:Release()` retire la commande. Les commandes sont
retirées à l'arrêt de votre package.

## Noms et conflits

Les joueurs tapent `/home`, les administrateurs `home` dans la console. La commande reste
toujours accessible sous la forme `<package>:<nom>`, ici `/homes:home` pour un package nommé
`homes`.

Quand deux packages déclarent le même nom, le premier chargé le garde et le second reçoit un
avertissement :

```
[foundation] WARN  warps/commands: /spawn of warps is already used by homes; it is available as /warps:spawn
```

Le nom d'une commande passe avant l'alias d'un autre package. Un nom libéré par un package
arrêté revient au suivant. Le nom `foundation` est réservé aux
[commandes d'administration](administration.md) de Foundation.

## Arguments

Chaque argument a un `name` et un `type` :

| Type | Accepte | Options |
| --- | --- | --- |
| `string` (par défaut) | Un mot, ou plusieurs entre guillemets : `"golden apple"` | `min`, `max` (longueur) |
| `greedy` | La fin de la ligne, telle que tapée. Doit être le dernier argument | `min`, `max` (longueur) |
| `integer` | Des nombres entiers : `5`, `-3` | `min`, `max` |
| `number` | Des nombres décimaux : `2.5` | `min`, `max` |
| `boolean` | `true`/`false`, `yes`/`no`, `on`/`off` | |
| `enum` | Une des `values`, sans tenir compte de la casse | `values` (chaînes en minuscules) |

Un argument est facultatif quand il a un `default` ou `optional = true` (sa valeur vaut alors
`nil` s'il manque). Les arguments facultatifs viennent après les obligatoires. Entre
guillemets, `\"` est un guillemet et `\\` une barre oblique inverse.

Quand la saisie est incorrecte, l'expéditeur reçoit le problème et la ligne d'usage, et `run`
n'est pas appelée :

```
<item> must be one of apple, sword
Usage: buy <item> [amount]
```

### Vos propres types d'arguments

`context:RegisterArgumentType(name, definition)` crée un type que tous les packages peuvent
utiliser sous la forme `<package>:<nom>` :

```lua
context:RegisterArgumentType("colour", {
    parse = function(text)
        local colours = { red = "#f00", green = "#0f0" }
        local value = colours[text:lower()]
        if not value then
            return nil, "unknown colour '" .. text .. "'"
        end
        return value
    end,
    suggest = function(prefix)
        return { "red", "green" }
    end,
})
```

`parse` renvoie la valeur, ou `nil` et un message pour l'expéditeur. `suggest` renvoie les
complétions de ce que le joueur a commencé à taper. Si l'une de ces fonctions lève une erreur,
ou si le package qui a enregistré le type s'est arrêté, l'expéditeur reçoit
`<nom> could not be read` et l'erreur est journalisée.

## Expéditeurs

`run` reçoit l'expéditeur :

- `sender:Reply(text)` répond dans le chat (joueurs) ou dans la console ;
- `sender:GetKind()` renvoie `"player"` ou `"console"` ; `IsPlayer()`, `IsConsole()` ;
- `sender:GetName()`, `sender:GetId()` (identifiant de compte pour les joueurs) ;
- `sender:GetPlayer()` renvoie l'objet joueur, `nil` pour la console.

Les délais (`cooldown`) sont comptés par joueur et ne s'appliquent jamais à la console. Ils ne
démarrent que si `run` se termine sans erreur, et sont remis à zéro au redémarrage du serveur.

## Ce qui se passe quand une commande est tapée

1. La ligne est découpée et les arguments sont vérifiés.
2. Le type d'expéditeur (`senders`) est vérifié, puis le délai.
3. `foundation:command` est émis. Un écouteur peut l'annuler, par exemple pour bloquer les
   commandes d'un joueur réduit au silence ; la commande ne s'exécute alors pas.
4. `run` est appelée. Si elle lève une erreur, l'expéditeur reçoit un court message et l'erreur
   est journalisée avec le nom de votre package.
5. Avec `audit = true`, l'utilisation est enregistrée.
6. `foundation:command_completed` est émis avec le résultat.

Voir [Événements](events.md#événements-de-foundation) pour ces deux événements.

## Chat et console

- **Chat** : les messages commençant par `/` sont des commandes ; ils ne sont pas montrés aux
  autres joueurs. Un message `/` qui n'est pas une commande reçoit « unknown command » et est
  masqué, sauf si le serveur règle `commands.unknown_in_chat = "pass"` (voir
  [Configuration](configuration.md)).
- **Console** : les noms de commandes tiennent compte de la casse ; tapez-les en minuscules.
  Chaque nom de commande est enregistré auprès de la console du serveur quand son package le
  déclare. Le serveur ne peut pas retirer une commande console : après l'arrêt d'un package,
  ses noms répondent « unknown command ».

## Audit

Avec `audit = true`, chaque utilisation est écrite dans le journal d'audit
(`foundation/audit/audit-<date>.log`, une ligne JSON par utilisation) avec l'action
`<package>:command/<chemin>`, l'expéditeur (`console` ou `player:<id>`), le résultat et les
arguments. Les arguments dont le nom ressemble à un secret (`password`, `token`…) sont masqués.
La ligne tapée elle-même n'est pas enregistrée.

Voir la [référence](reference/commands.md) pour tous les champs, méthodes et erreurs.
