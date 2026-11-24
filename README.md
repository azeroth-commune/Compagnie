# Compagnie

**Une équipe fixe de 2 à 5 personnages qui font toute l'aventure ensemble, du niveau 1 à la fin.** Add-on pour
WoW Forever, en bêta, interface en français.

*English: a fixed party of 2 to 5 characters questing together from level 1. Compagnie mode replaces the quest tracker
with the shared progress: a quest is ready to turn in only when everyone is done. French UI for now.*

## Ce que ça fait

- **Fonder une Compagnie** en un clic depuis ton groupe du jeu : chaque membre accepte ou refuse. Un personnage n'est
  membre que d'une Compagnie ; il n'y a pas de chef.
- **Les add-ons des membres s'échangent leur journal de quêtes**, et chacun garde le dernier état connu des autres.
- **Le mode Compagnie** remplace le suivi des quêtes du jeu par l'**avancement commun** : celui du membre le moins avancé,
  absents compris. Une quête n'est **à rendre** que quand tout le monde a fini.

  > Tu as 8/8 pattes de loup, Léo 5/8 et il n'est pas là ce soir : le suivi affiche 5/8. La quête attend Léo.

- **Le suivi par zone** : les quêtes de la zone où tu es, ou d'une zone choisie (clic sur le titre « Quêtes »).
- **La liste À faire** : « Partager » une quête que tu as et qu'un membre n'a pas ; « Abandonner aussi » une quête
  qu'un membre a abandonnée (abandonner, c'est dire « la Compagnie ne fait pas celle-là »). Un bouton chacun : l'add-on
  n'abandonne jamais rien tout seul. Mode Compagnie éteint, une petite liste À faire reste à l'écran.

### À venir

Dans la liste À faire, la quête à aller prendre soi-même ; l'avertissement quand on rend
une quête trop tôt, les quêtes personnelles (classe, métier), le foyer commun de la Compagnie. Voir les
[issues](https://github.com/azeroth-commune/Compagnie/issues).

## Installation

Avec le client CurseForge : installe **Compagnie** et **Azeroth Commune** (le socle, requis), puis clic droit sur chacun →
*Release type* : **Beta**.

À la main : dézippe `Compagnie` et `AzerothCommune` dans `_forever_\Interface\AddOns\`.

Compatible avec Questie s'il est installé.

## Commandes

| Commande | Effet |
|---|---|
| `/compagnie` | ouvre la fenêtre de la Compagnie (aussi par le bouton de minicarte Azeroth Commune) |
| `/compagnie fonder` | propose la Compagnie à ton groupe du jeu |
| `/compagnie suivi` | allume ou éteint le mode Compagnie (le suivi du jeu revient quand il est éteint) |
| `/compagnie quitter` | quitte la Compagnie |

## Soutenir

Ça te plaît ? Tu peux m'offrir un café sur [Ko-fi](https://ko-fi.com/virgile86017). ☕

## Un souci ?

Ouvre une [issue](https://github.com/azeroth-commune/Compagnie/issues) : ce que tu as fait, ce que tu attendais, ce qui
s'est passé (et l'erreur Lua s'il y en a une).

## Développement

Le vocabulaire est dans [`CONTEXT.md`](CONTEXT.md). Vérifier depuis le dossier des add-ons : `luajit Compagnie/check.lua`
(logique, bouchons de l'API WoW) ; les tests de `tests/` tournent dans le simulateur de l'atelier. Une version part sur
CurseForge à chaque étiquette `v*` (`-beta` dans l'étiquette : version Beta).

## Licence

Tous droits réservés.
