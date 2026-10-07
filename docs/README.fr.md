# Kornucopia

Kornucopia organise votre travail sur un tableau Kanban avec des notes adhésives, pour Mac avec Apple Silicon et Windows 11. Les colonnes À prévoir, En cours, Révision et Terminé proposent chacune un tutoriel pratique et une couleur distincte.

**[Télécharger la dernière version](https://github.com/allanpscheidt/Kornucopia/releases/latest)** · [Português brasileiro](../README.md)

## Version 1.0.1

- Tutoriels pratiques dans les quatre colonnes.
- Interface en portugais brésilien, anglais, espagnol, français et japonais.
- Choix de langue conservé dans les réglages. Vos notes gardent leur texte d'origine.
- Paquets Mac arm64 et Windows x64 et ARM64.

En cours commence avec une limite de deux cartes. Une alerte bloque l'ajout d'une carte lorsque la limite est atteinte. Terminez une tâche et déplacez-la vers Révision avant d'en commencer une autre. Vous pouvez augmenter la limite dans les réglages. Les autres colonnes acceptent des cartes sans limite artificielle.

## Installation et utilisation

Les commandes standard de macOS, comme Fermer, suivent la langue du système. Le choix de langue traduit les commandes, les alertes et les tutoriels de Kornucopia.

Sur Mac, Apple Silicon et macOS 14 ou ultérieur sont requis. Décompressez le ZIP macOS arm64 et copiez Kornucopia.app dans Applications. Le paquet utilise une signature ad hoc, sans Developer ID ni notarisation Apple. Consultez les [instructions Apple](https://support.apple.com/fr-fr/102445) si le système bloque la première ouverture.

Sur Windows 11, choisissez le ZIP x64 ou ARM64 adapté au processeur. Extrayez le dossier entier et gardez Kornucopia.exe avec Resources. Ouvrez l'exécutable. Le runtime est inclus. Le paquet actuel ne possède pas de signature Authenticode. Vérifiez la provenance et conservez les protections du système.

Ajoutez une idée à À prévoir, modifiez son titre et ses notes, puis suivez les tutoriels. Déplacez les cartes par glisser-déposer ou depuis l'éditeur. Choisissez la langue et la limite de travail dans les réglages. Les couleurs restent distinctes : jaune, bleu, violet et vert.

Les modifications s'enregistrent automatiquement. Les données se trouvent dans `~/Library/Application Support/Kornucopia/` sur Mac et `%LOCALAPPDATA%\Kornucopia\` sur Windows. Les fichiers JSON sont lisibles et une copie conserve l'état précédent. Incluez ce dossier dans vos sauvegardes habituelles. L'app fonctionne localement, sans compte ni synchronisation dans le cloud.

Consultez la [documentation complète](../README.md), le [guide de contribution](../CONTRIBUTING.md) et la [politique de sécurité](../SECURITY.md).
