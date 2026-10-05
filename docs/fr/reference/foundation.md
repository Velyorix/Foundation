# Référence de l'API : Foundation et contextes de package

Disponibilité : **serveur**. Introduit en 0.1.0 (API 0.1). Statut : préliminaire ; l'API peut
changer avant la 1.0.

## `Foundation`

Table globale exportée par le package `foundation`. Elle est en lecture seule : affecter un
champ lève `invalid_state`.

### `Foundation.VERSION`

Chaîne. Version du produit Foundation installé, par exemple `"0.1.0"`.

### `Foundation.API_VERSION`

Chaîne. Version du contrat d'API, `"<majeure>.<mineure>"`, par exemple `"0.1"`. Utilisez-la
dans des journaux ou des diagnostics ; dans votre manifeste, indiquez plutôt la version pour
laquelle votre code a été écrit, afin qu'un Foundation incompatible soit détecté.

### `Foundation.Register(package, manifest)`

Enregistre le package appelant et renvoie son [contexte](#contexte-de-package).

| Paramètre | Type | Description |
| --- | --- | --- |
| `package` | table | L'objet `Package` de votre package |
| `manifest` | table | Voir les [champs du manifeste](../package-integration.md#manifeste) |

À appeler une fois, au niveau principal de `Server/Index.lua`.

Lève, à la ligne de l'appelant :

| Code | Quand |
| --- | --- |
| `invalid_argument` | `package` ou `manifest` n'a pas le bon type, ou un champ du manifeste n'a pas le bon type |
| `invalid_value` | Champ de manifeste inconnu, `api` mal formé, `id` différent du nom du dossier, nom de package invalide dans `depends` ou `soft_depends` |
| `incompatible_api` | `manifest.api` n'est pas compatible avec `Foundation.API_VERSION` |
| `invalid_state` | Déjà enregistré ; une entrée de `depends` est absente ou inactive ; Foundation n'est pas en fonctionnement |

### `Foundation.Keys` et `Foundation.Schema`

Voir [Clés et schémas](validation.md).

## Contexte de package

Renvoyé par `Foundation.Register`. Les méthodes s'appellent avec `:`. Cette page décrit les
méthodes du cycle de vie ; le contexte fournit aussi :

| Méthodes | Référence |
| --- | --- |
| `RegisterCatalog`, `Translate` | [Localisation](localization.md) |
| `Config` | [Réglages d'un package](configuration.md) |
| `NextTick`, `Delay`, `Repeat`, `Debounce`, `Throttle`, `Future`, `All` | [Minuteries et futures](scheduling.md) |

### `context:GetId()`

Renvoie l'identifiant du package (nom de son dossier).

### `context:GetName()`

Renvoie le nom affiché : `manifest.name`, sinon le titre du package.

### `context:GetVersion()`

Renvoie `manifest.version`, sinon la version de `Package.toml`.

### `context:GetState()`

Renvoie `"initializing"`, `"ready"`, `"failed"` ou `"disabled"`. Voir [Cycle de vie](../lifecycle.md).

### `context:IsActive()`

Renvoie `true` tant que l'état est `initializing` ou `ready` et que le contexte appartient à
l'enregistrement courant du package.

### `context:OnReady(hook)`

Ajoute une fonction appelée une fois quand le package devient prêt, avec le contexte en
argument. Les hooks s'exécutent dans l'ordre d'ajout. Si un hook lève une erreur, le package
passe en `failed`.

Lève `invalid_argument` si `hook` n'est pas une fonction, `invalid_state` si le package n'est
plus `initializing`.

### `context:OnDisable(hook)`

Ajoute une fonction appelée une fois quand le package est désactivé ou échoue, avec le
contexte en argument. Les hooks s'exécutent du plus récent au plus ancien, avant la libération
des ressources suivies. Une erreur dans un hook est journalisée ; les autres hooks s'exécutent
quand même.

Lève `invalid_argument` si `hook` n'est pas une fonction, `invalid_state` si le contexte n'est
plus actif.

### `context:Track(kind, release, info)`

Rattache une ressource au package. `release` est appelée une fois, avec le handle renvoyé,
quand le package est désactivé ou échoue, ou quand vous appelez `handle:Release()`.

| Paramètre | Type | Description |
| --- | --- | --- |
| `kind` | chaîne | Libellé court affiché dans les diagnostics, par exemple `"event_listener"` |
| `release` | fonction | Annule ce qui a créé la ressource |
| `info` | table, optionnel | Valeurs supplémentaires pour les diagnostics (copiées) |

Renvoie un handle avec :

- `handle:Release()` : exécute `release` immédiatement ; renvoie `true` la première fois,
  `false` ensuite ;
- `handle:IsActive()` : `true` jusqu'à la libération de la ressource.

Lève `invalid_argument` ou `invalid_value` pour des arguments incorrects, `invalid_state` si le
contexte n'est plus actif.

## Erreurs

Foundation signale deux sortes d'erreurs.

Les **appels incorrects** (une erreur de programmation dans le code appelant) sont levés sous
forme de chaînes, à la ligne de l'appel :

```
[foundation:<code>] <fonction>: <explication>
```

| Code | Signification |
| --- | --- |
| `invalid_argument` | Un argument n'a pas le bon type |
| `invalid_value` | Un argument a le bon type mais une valeur inutilisable |
| `invalid_state` | L'appel n'est pas possible dans l'état actuel |
| `incompatible_api` | Le package requiert une version d'API que ce Foundation ne fournit pas |

Les **échecs prévisibles** (entrée invalide, délai dépassé) sont renvoyés, pas levés : la
fonction renvoie `nil` et une valeur d'erreur, ou une future est rejetée avec une valeur
d'erreur. Une valeur d'erreur est une table :

| Champ | Description |
| --- | --- |
| `code` | Identifiant stable, voir plus bas |
| `category` | `"developer"`, `"user"`, `"configuration"` ou `"infrastructure"` |
| `message` | Explication dans la langue du serveur |
| `params` | Valeurs utilisées dans le message |
| `details` | Données supplémentaires pour certains codes, par exemple les problèmes de `validation_failed` |
| `cause` | Erreur d'origine, quand celle-ci en enveloppe une autre |

`tostring(err)` donne `[foundation:<code>] <message>`. Comparez `err.code`, jamais le message,
qui dépend de la langue.

| Code | Catégorie | Renvoyé par |
| --- | --- | --- |
| `invalid_key` | user | [`Foundation.Keys.Parse`](validation.md#foundationkeysparsetext-default_namespace) |
| `validation_failed` | user | [`Foundation.Schema.Validate`](validation.md#foundationschemavalidateschema-value-limits) |
| `async_failed` | developer | Une [future](scheduling.md#futures) dont l'exécuteur ou une fonction a levé une erreur |
| `timeout` | infrastructure | [`future:Timeout`](scheduling.md#méthodes-des-futures) |
