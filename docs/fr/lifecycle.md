# Cycle de vie

Chaque package enregistré a un état :

| État | Signification |
| --- | --- |
| `initializing` | Enregistré ; son `Index.lua` s'exécute ou n'a pas encore reçu l'événement `Load` du serveur |
| `ready` | Le serveur a déclenché l'événement `Load` du package et tous ses hooks de démarrage ont réussi |
| `failed` | Un hook de démarrage a levé une erreur ou une dépendance obligatoire n'est plus active |
| `disabled` | Le package a été déchargé, ou Foundation l'a désactivé |

`context:GetState()` renvoie l'état courant ; `context:IsActive()` vaut `true` tant que le
package est `initializing` ou `ready`.

## Devenir prêt

Le serveur déclenche l'événement `Load` de chaque package une fois ses scripts exécutés. Au
démarrage du serveur, cela se produit après le chargement de tous les packages, avant
l'événement `Start` du serveur. Quand un package est rechargé en cours de partie, cela se
produit juste après la nouvelle exécution de ses scripts.

À cet événement, Foundation exécute les hooks `OnReady` du package dans l'ordre où ils ont été
ajoutés. Si l'un d'eux lève une erreur, celle-ci est journalisée avec sa trace d'appels, le
package passe en `failed`, ses hooks de désactivation s'exécutent et ses ressources sont
libérées.

## Arrêt

Un package est désactivé quand :

- le serveur le décharge (`package unload`, `package reload`, arrêt du serveur, changement de
  map) ;
- un package qu'il liste dans `depends` est désactivé ou échoue ;
- Foundation s'arrête.

La désactivation se déroule dans cet ordre :

1. les packages qui listent celui-ci dans `depends` sont désactivés d'abord ;
2. ses hooks `OnDisable` s'exécutent, du plus récent au plus ancien, pendant que ses
   ressources existent encore ;
3. ses ressources suivies sont libérées, de la plus récente à la plus ancienne.

Chaque étape n'a lieu qu'une fois, même si plusieurs de ces causes surviennent ensemble.
Ensuite, tout appel sur le contexte lève une erreur `invalid_state` ; aucune ressource ne peut
être enregistrée pour un package désactivé.

## Ressources suivies

`context:Track(kind, release)` rattache au cycle de vie du package quelque chose qu'il a créé :
`release` s'exécute une fois quand le package est désactivé.

C'est important parce que Foundation peut désactiver un package que le serveur garde chargé,
par exemple quand une dépendance est rechargée ou quand Foundation s'arrête. Dans ce cas, les
abonnements aux événements, timers et autres ressources natives créés par votre package
continuent de fonctionner tant que vous ne les libérez pas. Les suivre les fait s'arrêter avec
le package.

Une fonction `release` qui lève une erreur est journalisée avec sa trace d'appels ; les autres
ressources sont tout de même libérées.

## Dépendances

Listez dans `depends` les packages Foundation sans lesquels votre package ne peut pas
fonctionner, et ajoutez-les aussi à `packages_requirements` dans votre `Package.toml` pour que
le serveur les charge d'abord.

- L'enregistrement échoue si un package listé n'est pas enregistré ou pas actif.
- Quand une dépendance est désactivée ou échoue, votre package est désactivé avant elle.
- Quand une dépendance est rechargée, votre package reste désactivé : le serveur ne le
  recharge pas. Rechargez-le aussi, par exemple `package reload my-package`.

## Rechargements

| Action | Prise en charge | Effet |
| --- | --- | --- |
| `package reload my-package` | Oui | Votre package est désactivé, puis s'enregistre à nouveau à partir d'un état propre |
| `package reload all`, redémarrage du serveur | Oui | Tout redémarre dans l'ordre de chargement |
| `package reload foundation` | Non | Tous les packages enregistrés sont désactivés. Foundation journalise un avertissement qui les liste avec la commande pour les rétablir. Les packages gardent des références vers le Foundation arrêté jusqu'à leur rechargement |
| `package hotreload foundation` | Non | Non géré ; redémarrez le serveur |

## Arrêt du serveur

À l'arrêt du serveur, Foundation désactive les packages du plus récent au plus ancien (les
dépendants avant leurs dépendances), puis écrit `Foundation stopped`. Cela se produit avant que
le serveur ne décharge les packages eux-mêmes : utilisez `OnDisable` plutôt que l'événement
natif `Unload` pour le travail qui a besoin de Foundation, car au moment où votre gestionnaire
`Unload` s'exécute, Foundation peut déjà être arrêté.
