# Référence de l'API : réglages d'un package

Disponibilité : **serveur**. Introduit en 0.1.0 (API 0.1). Statut : préliminaire ; l'API peut
changer avant la 1.0.

Guide : [Réglages d'un package](../package-configuration.md). Pour les administrateurs :
[Configuration](../configuration.md).

## `context:Config(spec)`

Déclare les réglages du package, lit `foundation/config/<package>.toml` (en le créant à partir
des valeurs par défaut s'il manque) et renvoie un [objet de réglages](#objet-de-réglages). Ne
peut être appelé qu'une fois par enregistrement du package.

Champs de `spec` :

| Champ | Type | Description |
| --- | --- | --- |
| `fields` | tableau | Tableau non vide de [déclarations de réglages](#déclaration-dun-réglage) |
| `version` | entier, facultatif | Version actuelle de la structure, 1 ou plus. Par défaut `1` |
| `migrations` | table, facultatif | `[n] = function(data) return data end` convertit un fichier en version `n` vers la version `n + 1` |

Les champs inconnus sont refusés.

### Déclaration d'un réglage

| Champ | Type | Description |
| --- | --- | --- |
| `key` | chaîne | `"nom"` ou `"section.nom"` ; chaque partie commence par une lettre ou `_` et contient des lettres, des chiffres et `_` |
| `schema` | schéma | Construit avec [`Foundation.Schema`](validation.md#foundationschema) |
| `default` | chaîne, nombre, booléen ou tableau de ces valeurs | Doit respecter `schema`. Obligatoire sauf si `schema` accepte `nil`. Les tables à clés nommées sont refusées : elles ne peuvent pas être écrites dans le fichier |
| `description` | chaîne, facultatif | Commentaire écrit au-dessus du réglage dans un fichier créé |
| `reload` | chaîne, facultatif | `"restart"` (par défaut) ou `"hot"` |
| `secret` | booléen, facultatif | Masque la valeur dans les journaux de Foundation |

Une clé ne peut pas être déclarée deux fois, ne peut pas valoir `config_version`, et un nom ne
peut pas servir à la fois de réglage et de section.

### Lecture du fichier

- Un fichier manquant est créé avec les commentaires et les valeurs par défaut.
- Un fichier sans `config_version` est lu comme étant de la version actuelle.
- Un `config_version` plus ancien est converti en mémoire avec `migrations`, dans l'ordre ; le
  fichier n'est pas réécrit et un avertissement est journalisé.
- Le fichier n'est utilisé que s'il est lisible, que sa version est prise en charge, que
  chaque migration réussit et que chaque valeur respecte son schéma. Sinon chaque problème est
  journalisé et les valeurs par défaut sont utilisées.

Lève :

| Code | Quand |
| --- | --- |
| `invalid_argument` | `spec`, une déclaration de réglage ou l'un de leurs champs a le mauvais type |
| `invalid_value` | Champ inconnu, clé mal formée ou en double, clé réservée, valeur par défaut qui ne respecte pas son schéma ou qui est une table à clés nommées, `version` ou `reload` invalide |
| `invalid_state` | Le package a déjà appelé `context:Config`, ou son contexte n'est plus actif |

## Objet de réglages

### `settings:Get(key)`

Renvoie la valeur d'un réglage déclaré (une copie pour les tables). `key` s'écrit comme dans la
déclaration. Lève `invalid_value` pour une clé non déclarée.

### `settings:Values()`

Renvoie une copie de toutes les valeurs. Les réglages d'une section sont dans une table
imbriquée : `values.section.nom`.

### `settings:GetPath()`

Renvoie le chemin du fichier, relatif au dossier du serveur.

### `settings:OnChange(fn)`

Ajoute `fn(changed, values)`, appelée après un rechargement du fichier qui a modifié au moins
un réglage `"hot"`. `changed` est le tableau des clés modifiées, `values` une copie de toutes
les valeurs. Un réglage déclaré `"restart"` garde sa valeur jusqu'au prochain démarrage du
package ; un avertissement invite l'administrateur à redémarrer.

Les fichiers sont rechargés par la commande console `foundation reload-config`. Les fonctions
s'exécutent dans l'ordre où elles ont été ajoutées ; une erreur dans l'une d'elles est
journalisée et les autres s'exécutent quand même.

`Get`, `Values` et `OnChange` lèvent `invalid_state` une fois le package désactivé.
