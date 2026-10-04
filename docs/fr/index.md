# Documentation Foundation

Foundation est un framework serveur pour nanos world. Il s'installe comme un package de type
script nommé `foundation` et fournit l'infrastructure sur laquelle reposent les autres
packages : cycle de vie des packages et propriété des ressources, événements, commandes, API
de permissions, services, planification de tâches, échanges client-serveur contrôlés,
configuration, stockage, localisation, journalisation et diagnostics.

Foundation ne contient aucun gameplay. Un serveur conserve son propre game-mode, et les
fonctionnalités comme l'économie, les grades, les homes, les warps ou les boutiques sont
fournies par des packages séparés qui utilisent Foundation. Chacun de ces packages peut être
remplacé sans modifier Foundation.

> Foundation est en début de développement (0.1.0, non publiée). Le package s'installe et se
> charge, mais l'API publique n'est pas encore disponible. Ces pages décrivent uniquement ce
> qui existe dans la version actuelle.

*English version: [Foundation documentation](../en/index.md)*

## Administrateurs de serveur

- [Prérequis](requirements.md)
- [Installation et mises à jour](installation.md)
- [Compatibilité](compatibility.md)

## Développeurs de packages

Les guides de développement et la référence de l'API sont ajoutés au fur et à mesure que
chaque partie de l'API devient disponible. Commencez par les [Prérequis](requirements.md) et
[Installation et mises à jour](installation.md) pour préparer un serveur de développement.
