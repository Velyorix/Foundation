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

> Foundation est en début de développement (0.1.0, non publiée). Disponible aujourd'hui :
> l'enregistrement des packages, leur cycle de vie et le suivi des ressources, les fichiers de
> configuration, la localisation, les clés et la validation, les minuteries et les futures, les
> événements, les commandes avec la console et le chat. Ces pages décrivent uniquement ce qui
> existe dans la version actuelle, et l'API peut changer avant la 1.0.

*English version: [Foundation documentation](../en/index.md)*

## Administrateurs de serveur

- [Prérequis](requirements.md)
- [Installation et mises à jour](installation.md)
- [Compatibilité](compatibility.md)
- [Configuration](configuration.md)
- [Commandes d'administration](administration.md)
- [Journalisation](logging.md)

## Développeurs de packages

- [Intégration d'un package](package-integration.md)
- [Cycle de vie](lifecycle.md)
- [Réglages d'un package](package-configuration.md)
- [Localisation](localization.md)
- [Clés et validation](validation.md)
- [Minuteries et travail asynchrone](scheduling.md)
- [Événements](events.md)
- [Commandes](commands.md)

Référence de l'API :

- [Foundation et contextes de package](reference/foundation.md)
- [Réglages d'un package](reference/configuration.md)
- [Localisation](reference/localization.md)
- [Clés et schémas](reference/validation.md)
- [Minuteries et futures](reference/scheduling.md)
- [Événements](reference/events.md)
- [Commandes](reference/commands.md)
