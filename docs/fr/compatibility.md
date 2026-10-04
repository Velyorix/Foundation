# Compatibilité

## Versions de nanos world

| Foundation | nanos world minimum | Testé avec | État | Remarques |
| --- | --- | --- | --- | --- |
| 0.1.0 (non publiée) | 1.156 | 1.156.0 sous Windows | En développement | Linux pas encore testé |

« Testé avec » signifie que les suites de tests d'intégration automatisées ont réussi sur
cette version du serveur.

## Incompatibilités connues

Aucune connue.

## Gestion des versions

Foundation suit le [Semantic Versioning](https://semver.org/lang/fr/). Avant la version 1.0.0,
toute version mineure peut modifier l'API. À partir de la 1.0.0 :

- les versions correctives corrigent des bogues et ne cassent jamais un comportement
  documenté ;
- les versions mineures ajoutent des fonctionnalités sans casser les existantes ;
- les versions majeures peuvent retirer des API dépréciées dans une version précédente, avec
  un guide de migration.
