# Réglages d'un package

`context:Config(spec)` donne à votre package un fichier de réglages que les administrateurs du
serveur modifient : `foundation/config/<package>.toml`. Foundation le crée avec vos valeurs par
défaut et vos commentaires, le lit, valide chaque valeur avec le schéma que vous fournissez et
renvoie le résultat.

## Exemple

<!-- example: tests/integration/packages/foundation-example-rewards/Server/Index.lua -->
```lua
local context = Foundation.Register(Package, {
    api = "0.1",
    name = "Daily Rewards",
})

local S = Foundation.Schema

local settings = context:Config({
    fields = {
        {
            key = "enabled",
            schema = S.Boolean(),
            default = true,
            description = "Give a reward on the first join of each day.",
            reload = "hot",
        },
        {
            key = "reward.amount",
            schema = S.Integer({ min = 1, max = 100000 }),
            default = 250,
            description = "Amount of money given.",
            reload = "hot",
        },
        {
            key = "reward.message",
            schema = S.String({ min = 1, max = 120 }),
            default = "Here is your daily reward!",
            description = "Message shown with the reward.",
        },
    },
})

local function describe()
    if not settings:Get("enabled") then
        return "daily rewards are disabled"
    end
    return string.format("daily reward: %d (%s)", settings:Get("reward.amount"), settings:Get("reward.message"))
end

Console.Log(describe())

settings:OnChange(function()
    Console.Log(describe())
end)
```

Le premier démarrage crée `foundation/config/foundation-example-rewards.toml`, montré dans
[Configuration](configuration.md#réglages-des-packages), et journalise :

```
[foundation] INFO  foundation-example-rewards/config: created foundation/config/foundation-example-rewards.toml with the default settings
daily reward: 250 (Here is your daily reward!)
```

## Champs

Chaque entrée de `fields` déclare un réglage :

| Champ | Obligatoire | Signification |
| --- | --- | --- |
| `key` | oui | `nom`, ou `section.nom` pour placer le réglage sous `[section]` dans le fichier. Lettres, chiffres et `_` |
| `schema` | oui | Un [schéma](validation.md#schémas) auquel la valeur doit correspondre |
| `default` | oui, sauf si le schéma accepte `nil` | Valeur utilisée quand le réglage est absent ; écrite dans le fichier créé. Elle doit correspondre à `schema` |
| `description` | non | Commentaire écrit au-dessus du réglage dans le fichier créé |
| `reload` | non | `"restart"` (par défaut) ou `"hot"`, voir [Rechargement](#rechargement) |
| `secret` | non | `true` pour les mots de passe, jetons et autres secrets : la valeur est remplacée par `***` dans les journaux de Foundation |

Les réglages apparaissent dans le fichier dans l'ordre de déclaration, ceux sans section
d'abord. `config_version` est réservé.

Un réglage peut être une chaîne, un nombre, un booléen, ou un tableau de ces valeurs
(`S.List`).

## Lire les valeurs

- `settings:Get(key)` renvoie une valeur, avec la même clé que dans `fields`
  (`"reward.amount"`). Les tables sont renvoyées sous forme de copies. Une clé non déclarée
  lève une erreur : une faute de frappe est détectée dès la première exécution du code.
- `settings:Values()` renvoie une copie de toutes les valeurs, les sections sous forme de
  tables imbriquées : `values.reward.amount`.
- `settings:GetPath()` renvoie le chemin du fichier, pour vos messages aux administrateurs.

`context:Config` ne peut être appelé qu'une fois par package. Appelez-le pendant l'exécution de
votre `Index.lua`, pour qu'un fichier invalide soit signalé au démarrage.

## Quand le fichier est invalide

Votre package reçoit toujours des valeurs utilisables. Si le fichier ne peut pas être lu ou
qu'une valeur ne correspond pas à son schéma, Foundation journalise chaque problème pour
l'administrateur et votre package fonctionne avec les valeurs par défaut. Vous n'avez pas à
gérer ce cas.

## Rechargement

Le fichier est lu à l'appel de `context:Config` (au démarrage du serveur, et quand votre
package est rechargé), puis de nouveau quand un administrateur tape
`foundation reload-config`. `reload` indique comment un réglage peut changer pendant que votre
package continue de fonctionner :

- `"restart"` : jamais ; une nouvelle valeur n'est utilisée qu'après un redémarrage. À utiliser
  pour les réglages lus une seule fois (chemin d'une base de données, port).
- `"hot"` : la nouvelle valeur remplace l'ancienne, et les fonctions enregistrées avec
  `settings:OnChange(fn)` sont appelées avec la liste des clés modifiées et toutes les
  valeurs : `fn(changed, values)`.

Si le fichier rechargé est invalide, rien ne change et les fonctions `OnChange` ne sont pas
appelées. Les autres packages peuvent suivre les rechargements avec l'événement
[`foundation:config_reloaded`](events.md#événements-de-foundation).

## Changer la structure

Quand une nouvelle version de votre package renomme, déplace ou convertit des réglages,
augmentez `version` et fournissez une migration depuis chaque version précédente :

```lua
local settings = context:Config({
    version = 2,
    migrations = {
        [1] = function(data)
            data.reward = { amount = data.reward_amount }
            data.reward_amount = nil
            return data
        end,
    },
    fields = {
        { key = "reward.amount", schema = S.Integer({ min = 1 }), default = 250 },
    },
})
```

Une migration reçoit le contenu du fichier sous forme de table et renvoie la table convertie.
`migrations[1]` convertit la version 1 en version 2, `migrations[2]` la version 2 en 3, et
ainsi de suite. Les fichiers ne sont convertis qu'en mémoire ; Foundation ne réécrit jamais le
fichier de l'administrateur. Voir la [référence](reference/configuration.md).
