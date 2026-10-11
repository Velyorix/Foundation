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

## Canaux de publication

Chaque version est publiée sur la
[page des versions](https://github.com/Velyorix/Foundation/releases) avec son archive,
`foundation-<version>.zip`, et un fichier `SHA256SUMS`, et listée avec les mêmes fichiers sur le
[site de Foundation](https://foundationnw.dev/fr/builds). Son numéro indique le canal :

| Canal | Version et tag | Usage |
| --- | --- | --- |
| Stable | `1.2.0`, tag `v1.2.0` | Recommandé pour les serveurs avec des joueurs |
| Release candidate | `1.2.0-rc.1`, tag `v1.2.0-rc.1` | La prochaine version stable, publiée pour une dernière série de tests |
| Bêta | `1.2.0-beta.1`, tag `v1.2.0-beta.1` | De nouvelles fonctionnalités qui peuvent encore changer. À utiliser sur des serveurs de test |
| Nightly | `1.2.0-nightly.20261011`, tag `v1.2.0-nightly.20261011` | Construite automatiquement depuis la branche de développement quand elle a changé. Attendez-vous à des changements incompatibles |

Les release candidates, bêtas et nightlies sont marquées comme préversions. Une préversion
porte le numéro de la version vers laquelle elle mène : `1.2.0-beta.1` vient avant `1.2.0`.
`foundation version` affiche la version complète du build installé.

Pour vérifier un téléchargement, comparez sa somme de contrôle SHA-256 avec `SHA256SUMS`, ou
vérifiez où il a été construit avec la [CLI GitHub](https://cli.github.com/) :

```
gh attestation verify foundation-<version>.zip --repo Velyorix/Foundation
```
