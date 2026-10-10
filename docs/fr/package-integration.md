# Intégration d'un package

Un package utilise Foundation en s'y enregistrant depuis son code serveur. L'enregistrement
lui donne un **contexte** : l'objet par lequel Foundation sait ce que le package possède, et
quand il démarre et s'arrête.

Foundation ne fonctionne pour l'instant que côté serveur. Tout le code de cette page est du
code serveur (dossier `Server/`).

## Déclarer la dépendance

Ajoutez `foundation` dans votre `Package.toml` pour que le serveur le charge toujours avant
votre package :

```toml
[script]
    packages_requirements = [
        "foundation",
    ]
```

## S'enregistrer

Appelez `Foundation.Register` au niveau principal de votre `Server/Index.lua`, en passant
l'objet `Package` de votre propre package et un manifeste :

<!-- example: tests/integration/packages/foundation-example-greeter/Server/Index.lua -->
```lua
local context = Foundation.Register(Package, {
    api = "0.1",
    name = "Greeter",
})

local function on_ping(player_name)
    Console.Log("pong for %s", player_name)
end

Events.Subscribe("greeter:ping", on_ping)
context:Track("event_listener", function()
    Events.Unsubscribe("greeter:ping", on_ping)
end)

context:OnReady(function()
    Console.Log("Greeter is ready")
end)

context:OnDisable(function()
    Console.Log("Greeter is shutting down")
end)
```

Foundation lit l'identifiant de votre package avec `Package.GetName()`, c'est-à-dire le nom de
son dossier. Modifier le manifeste ne permet pas de s'enregistrer au nom d'un autre package.

Enregistrez-vous pendant l'exécution de `Index.lua`, pas plus tard depuis un timer ou un
événement : Foundation déclare le package prêt quand le serveur déclenche son événement
`Load`, qui n'a lieu qu'une fois, juste après l'exécution de vos scripts. Un package enregistré
plus tard reste dans l'état `initializing`.

## Manifeste

| Champ | Type | Obligatoire | Signification |
| --- | --- | --- | --- |
| `api` | chaîne | oui | Version de l'API Foundation pour laquelle votre code est écrit, `"<majeure>"` ou `"<majeure>.<mineure>"` |
| `name` | chaîne | non | Nom affiché. Par défaut, le `title` de votre `Package.toml` |
| `version` | chaîne | non | Version de votre package. Par défaut, la `version` de votre `Package.toml` |
| `author` | chaîne | non | Auteur ou organisation |
| `id` | chaîne | non | Doit être égal au nom du dossier s'il est présent ; repère les manifestes copiés |
| `depends` | tableau de noms de packages | non | Packages Foundation qui doivent être enregistrés avant le vôtre (voir [Cycle de vie](lifecycle.md#dépendances)) |
| `soft_depends` | tableau de noms de packages | non | Packages que votre code utilise s'ils sont présents ; non obligatoires |
| `services` | tableau | non | Services que votre package exige ou peut utiliser, voir [Services](services.md#exiger-un-service) |
| `capabilities` | tableau | non | Capacités que votre package déclare, voir [Capacités](services.md#capacités) |

Tout autre champ est refusé : un champ mal orthographié fait échouer le démarrage au lieu
d'être ignoré.

## Version de l'API

`Foundation.API_VERSION` est la version du contrat entre Foundation et les packages. Elle est
distincte de la version du produit (`Foundation.VERSION`).

- Avant la 1.0, votre `api` doit correspondre exactement (`"0.1"` ne fonctionne qu'avec
  l'API 0.1), car les versions préliminaires peuvent modifier l'API.
- À partir de la 1.0, la majeure doit correspondre et votre mineure ne doit pas dépasser celle
  de Foundation : `"1"`, `"1.0"` et `"1.2"` fonctionnent avec l'API 1.2 ; `"1.3"` et `"2.0"`,
  non.

Une version incompatible arrête votre package avec :

```
[foundation:incompatible_api] my-package requires Foundation API 0.2; this server runs API 0.1
```

## Quand l'enregistrement échoue

Les erreurs d'enregistrement sont levées à la ligne de votre appel à `Foundation.Register` :
le journal du serveur indique votre fichier et votre ligne. Les causes possibles :

- manifeste invalide (champ inconnu, mauvais type, `id` différent du nom du dossier) ;
- `api` incompatible ;
- un package listé dans `depends` n'est pas enregistré ou n'est pas actif ;
- le package est déjà enregistré (par exemple `Foundation.Register` appelé deux fois) ;
- Foundation lui-même n'est pas en fonctionnement.

Voir la [référence](reference/foundation.md) pour les codes d'erreur exacts.
