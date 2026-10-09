# Référence de l'API : événements

Disponibilité : **serveur**. Introduit en 0.1.0 (API 0.1). Statut : préliminaire ; l'API peut
changer avant la 1.0.

Guide : [Événements](../events.md).

## `context:DefineEvent(name, definition)`

Définit un événement appartenant au package et renvoie son nom complet.

| Paramètre | Type | Description |
| --- | --- | --- |
| `name` | chaîne | `"<nom>"` ou `"<package>:<nom>"`, une [clé](validation.md#foundationkeysparsetext-default_namespace) dans l'espace de noms du package |
| `definition` | table, facultatif | Voir ci-dessous |

| Champ de `definition` | Type | Description |
| --- | --- | --- |
| `fields` | table, facultatif | Nom de champ → [schéma](validation.md#foundationschema) |
| `mutable` | tableau, facultatif | Champs que les écouteurs peuvent modifier ; chacun doit figurer dans `fields` |
| `cancellable` | booléen, facultatif | Si les écouteurs peuvent annuler l'événement. Par défaut `false` |

L'événement est retiré, avec tous ses écouteurs, quand le package est désactivé.

Lève `invalid_argument` pour un mauvais type, `invalid_value` pour un nom mal formé, un nom
hors de l'espace de noms du package, un champ de définition inconnu ou une entrée de `mutable`
qui n'est pas un champ, `invalid_state` si l'événement est déjà défini ou si le contexte n'est
plus actif.

## `context:Emit(name, payload)`

Exécute les écouteurs d'un événement défini par le package et renvoie
l'[événement](#objet-événement) une fois qu'ils se sont tous exécutés.

| Paramètre | Type | Description |
| --- | --- | --- |
| `name` | chaîne | Nom utilisé dans `DefineEvent`, avec ou sans l'espace de noms |
| `payload` | table, facultatif | Valeurs des champs ; validées avec les schémas des champs (les valeurs par défaut des schémas `Optional` s'appliquent) |

Les écouteurs s'exécutent par priorité (`lowest`, `low`, `normal`, `high`, `highest`, `monitor`),
puis dans l'ordre où ils ont été ajoutés. Les écouteurs ajoutés pendant la diffusion attendent
la suivante ; ceux retirés pendant la diffusion sont ignorés. Une erreur dans un écouteur est
journalisée (`event_listener callback of <package> failed`) et la diffusion continue. Les
événements émis depuis des écouteurs peuvent s'imbriquer sur 16 niveaux au plus.

Lève `invalid_value` si l'événement n'est pas défini par le package ou si les données ne
respectent pas la définition, `invalid_state` au-delà de 16 niveaux d'imbrication ou si le
contexte n'est plus actif.

## `context:Listen(name, fn, options)`

Appelle `fn(event)` à chaque émission de l'événement. Renvoie un handle avec `Release()` et
`IsActive()`, comme [`context:Track`](foundation.md#contexttrackkind-release-info).

| Paramètre | Type | Description |
| --- | --- | --- |
| `name` | chaîne | Nom complet de l'événement ; sans espace de noms, celui du package |
| `fn` | fonction | Écouteur |
| `options` | table, facultatif | Voir ci-dessous |

| Option | Type | Description |
| --- | --- | --- |
| `priority` | chaîne | `"lowest"`, `"low"`, `"normal"` (par défaut), `"high"`, `"highest"` ou `"monitor"` |
| `ignore_cancelled` | booléen | Ignore l'écouteur tant que l'événement est annulé. Par défaut `false` |

Lève `invalid_argument` pour un mauvais type, `invalid_value` si l'événement n'est pas défini
ou si une option est inconnue ou invalide, `invalid_state` si la même fonction écoute déjà cet
événement pour le package ou si le contexte n'est plus actif.

## Objet événement

| Méthode | Description |
| --- | --- |
| `event:GetName()` | Nom complet de l'événement |
| `event:Get(field)` | Valeur d'un champ (les tables sont copiées). Lève `invalid_value` pour un champ non déclaré |
| `event:GetData()` | Copie de toutes les valeurs |
| `event:IsCancellable()` | Si la définition autorise l'annulation |
| `event:IsCancelled()` | État d'annulation actuel |
| `event:Set(field, value)` | Modifie un champ `mutable` ; la valeur est validée avec son schéma |
| `event:Cancel()` | Équivaut à `SetCancelled(true)` |
| `event:SetCancelled(cancelled)` | Annule l'événement ou le rétablit |

`Set`, `Cancel` et `SetCancelled` ne fonctionnent que dans un écouteur de priorité autre que
`monitor`, pendant la diffusion ; sinon ils lèvent `invalid_state`. `Set` lève `invalid_value`
pour un champ non `mutable` ou une valeur qui ne respecte pas son schéma ; `Cancel` et
`SetCancelled` lèvent `invalid_state` pour un événement non annulable.

## Événements de Foundation

Définis dans l'espace de noms réservé `foundation`, émis par Foundation uniquement. Seul
`foundation:command` est annulable.

| Événement | Champs |
| --- | --- |
| `foundation:package_ready` | `package` (chaîne), `version` (chaîne ou `nil`) |
| `foundation:package_failed` | `package`, `version`, `message` (raison traduite) |
| `foundation:package_disabled` | `package`, `version`, `reason` : `"unload"`, `"dependency_disabled"`, `"dependency_failed"` ou `"foundation_stopping"` |
| `foundation:config_reloaded` | `package` (`"foundation"` pour le fichier de Foundation), `path`, `changed` et `pending` (tableaux de clés de réglages) |
| `foundation:command` | `command` (chemin, `"home set"`), `owner` (package), `sender` (`"console"` ou `"player"`), `name` (nom de l'expéditeur), `arguments` (table par nom d'argument) |
| `foundation:command_completed` | Les champs de `foundation:command` et `outcome` : `"success"` ou `"failure"` |

`package_disabled` est émis pour les packages dépendants avant leur dépendance.
`config_reloaded` est émis une fois par fichier rechargé sans erreur, après les fonctions
`OnChange` du package.
