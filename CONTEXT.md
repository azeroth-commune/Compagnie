# Compagnie — quêtes en groupe

Une équipe fixe de personnages fait l'aventure ensemble à partir de sa fondation, et ne fait que les quêtes ensemble ; l'add-on garde les journaux de quêtes alignés et dit quoi faire quand ils divergent.

## Language

### Qui

**Compagnie**:
Une équipe fixe et durable de personnages qui font l'aventure ensemble à partir de sa fondation, à n'importe quel niveau, races différentes comprises (même faction : le jeu l'impose pour grouper) ; elle existe aussi quand certains membres sont hors ligne.
_Avoid_: groupe (réservé au groupe du jeu), équipe, guilde, party

**Membre**:
Un personnage d'une Compagnie ; un personnage est membre d'une seule Compagnie à la fois.
_Avoid_: joueur (un joueur peut avoir des personnages dans plusieurs Compagnies)

**Fonder**:
Créer une Compagnie depuis un groupe du jeu ; chaque personnage du groupe accepte ou refuse d'en être membre.
_Avoid_: créer, inviter (réservé à l'entrée dans une Compagnie qui existe)

**Inviter**:
Proposer à un joueur de mon groupe du jeu d'entrer dans la Compagnie qui existe déjà (n'importe quel membre le peut, depuis la fenêtre de la Compagnie) ; il accepte ou refuse, comme à la fondation, avec les mêmes gardes (5 membres au plus, une seule Compagnie par personnage). Accepté, il arrive avec ses quêtes d'avant ; le foyer, la zone de la Compagnie et les quêtes écartées sont gardés. La nouvelle liste des membres, datée, part avec l'état de chacun : un absent l'apprend à son retour (comme un départ : celui qui n'est plus dans la liste la plus récente n'est plus membre).
_Avoid_: recruter, ajouter, rejoindre

**Retirer**:
Sortir un membre de la Compagnie sans son accord (typiquement un absent qui a arrêté) ; n'importe quel membre peut le faire, il n'y a pas de chef.
_Avoid_: exclure, kick

**Absent**:
Un membre qui ne joue pas en ce moment ; il compte avec son dernier état connu.
_Avoid_: hors ligne (seul), inactif

**Dernier état connu**:
Ce que Compagnie sait du journal d'un autre membre, d'après son dernier envoi ; une donnée propre de Compagnie (perdue pour de bon sinon), utilisée telle quelle car rien n'est en jeu.
_Avoid_: cache, copie

### Quêtes

**Écart**:
Une différence entre les journaux de quêtes des membres, qui demande une action pour être résorbée.
_Avoid_: désynchro, divergence

**Quête d'avant**:
Une quête qu'un membre avait dans son journal en entrant dans la Compagnie (les restes de sa zone de départ) : à lui, affichée chez tous à part, avec son nom et son avancement, comme une quête personnelle ; elle ne crée aucun écart et ne fait attendre personne. Elle est de la Compagnie dès qu'un membre l'a prise après son entrée (sa quête d'avant compte alors normalement, et qui ne l'a pas reçoit « Partager ») ou que tous les membres l'ont ; elle disparaît quand il la rend ou l'abandonne (l'abandonner ne l'écarte pas : elle n'était qu'à lui).
_Avoid_: ancienne quête, quête héritée

**Quête à partager**:
Écart où un membre a une quête que d'autres n'ont pas, et que le jeu permet de partager.

**Quête à prendre soi-même**:
Écart où un membre a une quête que d'autres n'ont pas, et que le jeu ne permet pas de partager (lancée par un objet, ou le PNJ remet un objet) : chacun doit aller la chercher. L'écart dit où : « Va voir Maréchal Dughan » avec l'endroit (le PNJ et la position relevés par le membre qui l'a acceptée, sinon le donneur de la base des quêtes), ou l'objet à trouver avec l'endroit où un membre l'a ramassé (sinon d'où il vient d'après la base : « lâché par les kobolds ») ; sans rien de connu, l'écart existe quand même, sans endroit. Une quête personnelle ou de niveau insuffisant n'en fait pas.
_Avoid_: quête non partageable

**Quête écartée**:
Une quête que la Compagnie ne fait pas, décidé par n'importe quel membre, avant ou après l'avoir prise (clic droit sur la quête dans le suivi, la liste À faire ou un prérequis manquant) ; abandonner une quête dans le jeu, c'est l'écarter. Elle emporte sa chaîne : ses suites, et les prérequis qui ne servaient qu'à des quêtes écartées (un prérequis qui ouvre une autre quête gardée reste) ; une quête qui a sa propre décision la garde. Elle sort de l'avancement commun et des écarts chez tous, et n'est jamais à partager. Chez un membre qui l'a encore : écart « Abandonner aussi », jamais d'abandon automatique ; s'il la garde, elle est à lui, à part, nommée et dite écartée. « Remettre » annule, comme reprendre une quête qu'on avait soi-même écartée ; chaque décision est datée, la plus récente l'emporte (à la même seconde, écarter), et le chat dit qui a écarté ou remis quoi (une remise, seulement à qui la savait écartée). Une remise est oubliée au bout de 7 jours.
_Avoid_: quête abandonnée (l'abandon n'est qu'une façon d'écarter), quête ignorée, quête refusée

**Acceptation automatique**:
Une quête qu'un autre membre a dans son journal est acceptée toute seule à l'ouverture de sa fenêtre (partage, PNJ, confirmation d'une escorte lancée par un membre), sauf si elle est écartée ; une quête qu'aucun autre membre n'a s'ouvre normalement : le membre choisit ce que la Compagnie commence. Réglage allumé par défaut, dans la page de Compagnie des réglages.
_Avoid_: auto-accept

**Quête en avance**:
Écart où un membre a rendu, ou s'apprête à rendre, une quête dont l'avancement commun n'est pas complet ; l'add-on avertit, il ne bloque pas. Seule compte une remise que l'add-on du membre a vue après son entrée dans la Compagnie : ce qu'il a rendu avant n'est jamais en avance. Avant : un bandeau sous la fenêtre de remise du jeu (« La Compagnie n'a pas fini : 5/8 »), le bouton du jeu intact. Après : chez chaque membre qui l'a encore sans l'avoir finie, « Rendue en avance », sans nommer qui l'a rendue ; résorbée quand il l'a finie.
_Avoid_: remise anticipée

**Niveau insuffisant**:
Écart où un membre a une quête que d'autres n'ont pas encore le niveau de prendre ; il se résorbe quand le niveau de la Compagnie l'atteint.

**Niveau de la Compagnie**:
Le niveau du membre le plus bas (même principe que l'avancement commun).

**Quête personnelle**:
Une quête que le jeu interdit aux autres membres de prendre (classe, race, d'après la base des quêtes), ou qu'un membre a marquée personnelle (clic droit sur la quête : une quête de métier, ce que la base ne dit pas) ; ce n'est pas un écart, la Compagnie l'accompagne, et son affichage nomme le membre concerné (comme celui d'une quête d'avant, ou d'une quête écartée qu'il garde).
_Avoid_: quête solo

**Avancement commun**:
L'avancement d'une quête pour la Compagnie : celui du membre le moins avancé, absents compris.

**Objets à donner**:
Écart sur un objectif d'objet échangeable (jamais lié : pas un objet de quête lié) quand la Compagnie en a assez pour que tous finissent, en comptant ce que chacun a dans ses sacs au-delà du total : chez celui qui en a de trop, « Donne 5 Patte de loup à Léo » (le clic ouvre l'échange, Léo dans le groupe) ; chez celui à qui il en manque, « Léo te donne 5 Patte de loup ». Rien tant qu'un membre n'a pas la quête, ni quand il n'y en a pas assez pour tous.
_Avoid_: partage d'objets (« partager » est réservé aux quêtes), don

**À rendre**:
Une quête dont l'avancement commun est complet : tous les membres peuvent la rendre.

### Foyer

**Foyer de la Compagnie**:
L'auberge à laquelle la Compagnie est liée : la dernière choisie par un membre (sans vote ni chef) ; les autres sont invités à s'y lier. Seule compte une liaison que l'add-on du membre a vue se faire : une liaison sans date ne l'emporte jamais, et sans aucune date il n'y a pas encore de foyer.
_Avoid_: point de retour, bind

**Foyer différent**:
Écart où un membre est lié à une autre auberge que le foyer de la Compagnie : « Lie-toi à l'auberge de Comté-de-l'Or ».

**Pierre de la Compagnie**:
La pierre de foyer vue par la Compagnie : disponible seulement quand celle de chaque membre l'est (même principe que l'avancement commun) ; pour un absent, la recharge est recalculée depuis son envoi. Le suivi la montre sur le bouton qui utilise ma pierre (« Foyer dans 40 min », « Rentrer au foyer »), sans dire à cause de qui ; le clic n'est jamais bloqué.

### Zone

**Prérequis manquant**:
Écart sur la zone de la Compagnie : une quête de la zone, que le membre peut prendre (race, classe) et n'a pas faite, demande une chaîne qui commence hors de la zone, que ce membre n'a pas faite (ni amorce, ni chaîne restée dans la zone : on la fera en avançant ; « un seul parmi plusieurs » : n'importe lequel suffit). Il nomme la quête débloquée, la chaîne, sa zone, son premier donneur et à qui elle manque (« toute la Compagnie ») ; seuls ceux à qui elle manque l'ont dans leur liste À faire. Chaque membre calcule les siens et les envoie avec la zone qu'ils couvrent ; un membre dont l'état ne couvre pas la zone choisie est **à contrôler** (on ne lui prête rien). Résorbé quand la chaîne est faite ou que la quête débloquée est écartée (« Écarter » sur l'écart).
_Avoid_: quête manquée, prérequis manquant pour une chaîne dans la zone

**Zone de la Compagnie**:
La zone où va la Compagnie, choisie par n'importe quel membre (sans vote ni chef : le choix le plus récent l'emporte, daté comme une décision sur une quête écartée) dans le menu de son bouton, en tête du suivi. Le menu propose les zones de la base des quêtes, d'abord celles dont la Compagnie a le **niveau d'entrée** (le niveau requis du premier quart des quêtes de la zone), les autres en grisé, choisissables. Les autres membres l'apprennent dans le chat, un absent à son retour. Entrer dans une autre zone propose de la choisir dans le chat, une fois par zone ; rien ne change tout seul. Elle n'a rien à voir avec le filtre d'affichage par zone du suivi, qui reste personnel.
_Avoid_: zone (seul, ambigu avec la zone d'une quête ou le filtre), destination, zone cible

### Affichage

**Mode Compagnie**:
L'affichage du suivi des quêtes qui ne montre que l'avancement commun, sans dire qui est en retard ni qui est en avance.
_Avoid_: mode groupe, mode synchro

**À faire**:
La liste des écarts qui demandent une action d'un membre (partager, aller voir un PNJ, se lier à l'auberge) ; visible même quand le mode Compagnie est éteint.
_Avoid_: alertes, notifications

**Bandeau d'abandon**:
Un bandeau posé au-dessus de la fenêtre d'abandon du jeu quand abandonner écarterait la quête : « Abandonner « X » l'écarte pour la Compagnie », et la suite que l'abandon coupe, d'après la base des quêtes (sans les quêtes d'une autre race ou classe). Le bouton du jeu n'est jamais touché ; pas de bandeau hors d'une Compagnie, pour une quête déjà écartée ni pour ma quête d'avant.

### Plus tard

**Chemin de synchronisation**:
La suite de quêtes, calculée par l'add-on, qui ramène tous les membres au même point (par exemple quand un personnage rejoint une Compagnie en cours).
_Avoid_: rattrapage

## Relationships

- Une **Compagnie** a de 2 à 5 membres ; un **Membre** n'appartient qu'à une **Compagnie**.
- L'**avancement commun** compte tous les membres ; un **absent** compte avec son dernier état connu, donc une quête n'est jamais **à rendre** sans lui.
- Les quêtes de la **Compagnie** sont celles que ses membres prennent, sauf une **quête d'avant** que personne n'a prise après son entrée ; l'add-on ne choisit pas les quêtes (le guide viendra avec le **chemin de synchronisation**).
- Une **quête personnelle** ou une **quête d'avant** n'entre pas dans l'**avancement commun** des autres.

## Example dialogue

> **Dev :** « Virgile a 8/8 pattes de loup, Léo 5/8 et n'est pas connecté ce soir. Le suivi affiche quoi ? »
> **Joueur :** « En mode Compagnie : 5/8, en attente de Léo. La quête n'est pas à rendre tant que Léo n'a pas fini. »

## Flagged ambiguities

- « Groupe » pouvait désigner le groupe du jeu (party) ou l'équipe qui fait l'aventure ensemble. Tranché : **Compagnie** pour l'équipe, « groupe » réservé au jeu.
