# Installation et mises à jour

## Installer

1. Téléchargez les sources du dépôt (jusqu'à la première version publiée, il n'existe pas
   d'archive séparée).
2. Copiez son dossier `package/` dans le dossier `Packages/` de votre serveur et renommez-le
   `foundation`. Le nom du dossier est l'identifiant du package et doit être exactement
   `foundation` :

   ```
   NanosWorldServer.exe
   Config.toml
   Packages/
   └── foundation/
       ├── Package.toml
       └── Shared/
   ```

3. Chargez-le. Ajoutez-le à la liste `packages` de `Config.toml` :

   ```toml
   [game]
       packages = [
           "foundation",
       ]
   ```

   ou laissez les packages qui l'utilisent s'en charger : un package qui déclare
   `foundation` dans ses `packages_requirements` fait charger Foundation en premier.

4. Démarrez le serveur et vérifiez que le journal contient :

   ```
   [foundation] INFO  foundation/config: created foundation/config.toml with the default settings
   [foundation] INFO  foundation/core: Foundation 0.1.0 started (API 0.1, server)
   Package 'foundation' (0.1.0) loaded.
   ```

   Au premier démarrage, Foundation crée son fichier de réglages, `foundation/config.toml`, à
   côté de l'exécutable du serveur ; les démarrages suivants journalisent
   `loaded foundation/config.toml` à la place. Voir [Configuration](configuration.md).

## Mettre à jour

Arrêtez le serveur, remplacez le dossier `Packages/foundation/` par la nouvelle version, puis
redémarrez le serveur. Le dossier du package ne contient aucune donnée du serveur : le
remplacer ne fait rien perdre. Les réglages sont conservés dans le dossier `foundation/` à côté
de l'exécutable du serveur.

Lisez le [journal des modifications](../../CHANGELOG.md) avant chaque mise à jour : il indique
les changements qui demandent une action aux administrateurs ou aux développeurs de packages.

## Désinstaller

Retirez `foundation` de `packages` dans `Config.toml` et supprimez `Packages/foundation/`. Les
packages qui dépendent de Foundation ne se chargeront plus. Supprimez aussi le dossier
`foundation/` à côté de l'exécutable du serveur si vous ne souhaitez pas conserver les
réglages.
