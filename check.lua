-- Vérification hors jeu (jamais dans un TOC) : luajit Compagnie/check.lua, lancé depuis le dossier des add-ons.
-- Le calcul de la Compagnie est pur : chargé sans aucun bouchon, et toute lecture d'une globale inconnue (une
-- fonction de l'API du jeu) fait échouer la vérification.
setmetatable(_G, { __index = function(_, k) error("globale inconnue (API du jeu ?) : " .. tostring(k), 2) end })
local ns = {}
assert(loadfile("Compagnie/Calcul.lua"))("Compagnie", ns)

local PATTES = 1001 -- une quête : 8 pattes de loup
local function pattes(fait) return { objectifs = { { texte = "Patte de loup", fait = fait, total = 8 } }, finie = fait == 8 } end

-- Virgile a 8/8 pattes de loup, Léo 5/8 et n'est pas connecté ce soir : 5/8, en attente de Léo, pas à rendre.
local c = ns.calculer({
  { nom = "Virgile", niveau = 10, quetes = { [PATTES] = pattes(8) } },
  { nom = "Léo", niveau = 10, absent = true, quetes = { [PATTES] = pattes(5) } },
})
local q = assert(c.quetes[PATTES], "la quête est une quête de la Compagnie")
assert(q.objectifs[1].fait == 5 and q.objectifs[1].total == 8, "avancement commun : celui du moins avancé, absent compris")
assert(q.objectifs[1].texte == "Patte de loup", "l'objectif garde son texte")
assert(#q.enAttente == 1 and q.enAttente[1] == "Léo", "en attente de Léo")
assert(q.aRendre == false, "pas à rendre tant que Léo n'a pas fini")

-- Tous les membres ont fini : à rendre, personne n'est attendu.
c = ns.calculer({
  { nom = "Virgile", niveau = 10, quetes = { [PATTES] = pattes(8) } },
  { nom = "Léo", niveau = 10, absent = true, quetes = { [PATTES] = pattes(8) } },
})
assert(c.quetes[PATTES].aRendre == true, "tous ont fini : à rendre")
assert(#c.quetes[PATTES].enAttente == 0, "personne en attente")

-- Un objectif fini chez tous, un autre non : l'avancement commun est donné objectif par objectif.
local CHASSE = 1002 -- 8 pattes de loup et 4 crocs de loup
local function chasse(p, cr)
  return { objectifs = { { texte = "Patte de loup", fait = p, total = 8 }, { texte = "Croc de loup", fait = cr, total = 4 } },
    finie = p == 8 and cr == 4 }
end
c = ns.calculer({
  { nom = "Virgile", niveau = 10, quetes = { [CHASSE] = chasse(8, 4) } },
  { nom = "Léo", niveau = 10, quetes = { [CHASSE] = chasse(8, 1) } },
  { nom = "Mira", niveau = 10, quetes = { [CHASSE] = chasse(8, 3) } },
})
local o = c.quetes[CHASSE].objectifs
assert(o[1].fait == 8 and o[1].total == 8, "pattes : 8/8, fini chez tous")
assert(o[2].fait == 1 and o[2].total == 4 and o[2].texte == "Croc de loup", "crocs : 1/4, celui de Léo")
assert(c.quetes[CHASSE].aRendre == false, "pas à rendre")
assert(table.concat(c.quetes[CHASSE].enAttente, ",") == "Léo,Mira", "en attente de Léo et Mira, dans l'ordre des membres")

-- Membres niveaux 9, 10 et 11 : niveau de la Compagnie 9, celui du plus bas.
c = ns.calculer({ { nom = "Virgile", niveau = 10 }, { nom = "Léo", niveau = 9 }, { nom = "Mira", niveau = 11 } })
assert(c.niveau == 9, "niveau de la Compagnie : celui du membre le plus bas")

-- Léo n'a pas la quête dans son journal (ni rendue) : il compte à 0, donc jamais à rendre sans lui.
c = ns.calculer({
  { nom = "Virgile", niveau = 10, quetes = { [PATTES] = pattes(8) } },
  { nom = "Léo", niveau = 10, quetes = {} },
})
q = c.quetes[PATTES]
assert(q.objectifs[1].fait == 0 and q.objectifs[1].total == 8, "sans la quête : 0/8")
assert(q.aRendre == false and q.enAttente[1] == "Léo", "en attente de Léo, pas à rendre")

-- Virgile a déjà rendu la quête : il ne retient plus la Compagnie, seul l'avancement de Léo compte.
local rendue = { nom = "Virgile", niveau = 10, quetes = {}, rendues = { [PATTES] = true } }
c = ns.calculer({ rendue, { nom = "Léo", niveau = 10, quetes = { [PATTES] = pattes(5) } } })
assert(c.quetes[PATTES].objectifs[1].fait == 5 and c.quetes[PATTES].enAttente[1] == "Léo", "rendue : 5/8, en attente de Léo")
c = ns.calculer({ rendue, { nom = "Léo", niveau = 10, quetes = { [PATTES] = pattes(8) } } })
assert(c.quetes[PATTES].aRendre == true and #c.quetes[PATTES].enAttente == 0, "rendue et Léo a fini : à rendre")
-- Rendue par tous : plus une quête de la Compagnie.
c = ns.calculer({ rendue, { nom = "Léo", niveau = 10, quetes = {}, rendues = { [PATTES] = true } } })
assert(c.quetes[PATTES] == nil, "rendue par tous : plus dans les quêtes de la Compagnie")

-- Le journal de Léo n'a pas encore tous les objectifs (pas encore chargé) : un objectif qui lui manque compte à 0,
-- avec le texte et le total pris chez les autres ; l'avancement commun n'affiche jamais un objectif fini à tort.
c = ns.calculer({
  { nom = "Virgile", niveau = 10, quetes = { [CHASSE] = chasse(8, 4) } },
  { nom = "Léo", niveau = 10, quetes = { [CHASSE] = { objectifs = { { texte = "Patte de loup", fait = 8, total = 8 } } } } },
})
o = c.quetes[CHASSE].objectifs
assert(o[1].fait == 8, "pattes : 8/8 chez les deux")
assert(o[2].fait == 0 and o[2].total == 4 and o[2].texte == "Croc de loup", "crocs absents du journal de Léo : 0/4")
c = ns.calculer({
  { nom = "Léo", niveau = 10, quetes = { [CHASSE] = { objectifs = {} } } },
  { nom = "Virgile", niveau = 10, quetes = { [CHASSE] = chasse(8, 4) } },
})
o = c.quetes[CHASSE].objectifs
assert(o[1].fait == 0 and o[2].fait == 0, "journal de Léo vide, même en premier : 0/8 et 0/4")

-- La liste À faire (#5). Kobolds : une quête que le jeu permet de partager.
local KOBOLDS = 1003
local function kobolds(partageable) return { finie = false, objectifs = {}, partageable = partageable } end
local function seul(aFaire, type, membre, quete)
  assert(#aFaire == 1, "un seul écart : " .. #aFaire)
  local x = aFaire[1]
  assert(x.type == type and x.membre == membre and x.quete == quete, ("écart %s %s %s"):format(x.type, x.membre, x.quete))
  return x
end

-- Quête partageable chez un seul membre : « à partager » chez lui, avec ceux qui ne l'ont pas (un absent compris).
c = ns.calculer({
  { nom = "Virgile", niveau = 5, quetes = { [KOBOLDS] = kobolds(true) } },
  { nom = "Léo", niveau = 5, quetes = {} },
  { nom = "Mira", niveau = 5, absent = true, quetes = {} },
})
local x = seul(c.aFaire, "partager", "Virgile", KOBOLDS)
assert(#x.manquants == 2 and x.manquants[1] == "Léo" and x.manquants[2] == "Mira", "Léo et Mira ne l'ont pas")
-- Non partageable : pas « à partager » (« à prendre soi-même », ci-dessous) ; pas dit (partageable inconnu) : rien.
c = ns.calculer({ { nom = "Virgile", niveau = 5, quetes = { [KOBOLDS] = kobolds(false) } }, { nom = "Léo", niveau = 5, quetes = {} } })
seul(c.aFaire, "prendre", "Léo", KOBOLDS)
c = ns.calculer({ { nom = "Virgile", niveau = 5, quetes = {} }, { nom = "Léo", niveau = 5, quetes = { [KOBOLDS] = kobolds() } } })
assert(#c.aFaire == 0, "partageable inconnu : rien")

-- Quête à prendre soi-même (#6) : non partageable chez un seul membre → « à prendre soi-même » chez chacun des autres
-- (un absent compris), avec le PNJ et sa position : le relevé du membre qui l'a prise (origine : où il l'a acceptée).
local DUGHAN = { nom = "Maréchal Dughan", carte = 1429, x = 42, y = 65 }
local function aPrendre(origine) return { finie = false, objectifs = {}, partageable = false, origine = origine } end
c = ns.calculer({ { nom = "Virgile", niveau = 5, quetes = { [KOBOLDS] = aPrendre(DUGHAN) } },
  { nom = "Léo", niveau = 5, quetes = {} }, { nom = "Mira", niveau = 5, absent = true, quetes = {} } })
assert(#c.aFaire == 2 and c.aFaire[1].type == "prendre" and c.aFaire[2].type == "prendre", "à prendre chez Léo et Mira")
x = c.aFaire[1]
assert(x.membre == "Léo" and c.aFaire[2].membre == "Mira" and x.quete == KOBOLDS, "chez ceux qui ne l'ont pas")
assert(x.donneur.nom == "Maréchal Dughan" and x.donneur.carte == 1429 and x.donneur.x == 42 and x.donneur.y == 65,
  "le PNJ et sa position, relevés par Virgile")
assert(x.objet == nil, "pas d'objet de départ")
-- Sans relevé : le donneur de la base des quêtes (le PNJ que personne n'a encore vu) ; le relevé passe devant la base.
local BASE6 = { [KOBOLDS] = { donneur = { pnj = 240, nom = "Maréchal Dughan", carte = 1429, x = 42.1, y = 65.9 } } }
c = ns.calculer({ { nom = "Léo", niveau = 5, quetes = { [KOBOLDS] = kobolds(false) } },
  { nom = "Virgile", niveau = 5, quetes = {} } }, 0, nil, BASE6)
x = seul(c.aFaire, "prendre", "Virgile", KOBOLDS)
assert(x.donneur.nom == "Maréchal Dughan" and x.donneur.x == 42.1, "le donneur de la base")
c = ns.calculer({ { nom = "Léo", niveau = 5, quetes = { [KOBOLDS] = kobolds(false) } },
  { nom = "Mira", niveau = 5, quetes = { [KOBOLDS] = aPrendre({ nom = "Gryan Stoutmantle", carte = 1436, x = 56, y = 47 }) } },
  { nom = "Virgile", niveau = 5, quetes = {} } }, 0, nil, BASE6)
x = seul(c.aFaire, "prendre", "Virgile", KOBOLDS)
assert(x.donneur.nom == "Gryan Stoutmantle" and x.donneur.carte == 1436, "le relevé de Mira passe devant la base")
-- Résorbé : prise, ou déjà rendue ; écartée : « Abandonner aussi » chez qui l'a, rien à prendre ; quête d'avant : rien.
c = ns.calculer({ { nom = "Léo", niveau = 5, quetes = { [KOBOLDS] = aPrendre(DUGHAN) } },
  { nom = "Virgile", niveau = 5, quetes = { [KOBOLDS] = kobolds() } } })
assert(#c.aFaire == 0, "prise : l'écart n'apparaît plus")
c = ns.calculer({ { nom = "Léo", niveau = 5, quetes = { [KOBOLDS] = aPrendre(DUGHAN) } },
  { nom = "Virgile", niveau = 5, quetes = {}, renduesAvant = { [KOBOLDS] = true } } })
assert(#c.aFaire == 0, "déjà rendue : rien à prendre")
c = ns.calculer({ { nom = "Léo", niveau = 5, quetes = { [KOBOLDS] = aPrendre(DUGHAN) } }, { nom = "Virgile", niveau = 5, quetes = {} } },
  0, { [KOBOLDS] = { ecartee = true, date = 1, par = "Virgile" } })
seul(c.aFaire, "ecartee", "Léo", KOBOLDS)
c = ns.calculer({ { nom = "Léo", niveau = 5, quetes = { [KOBOLDS] = aPrendre(DUGHAN) }, avant = { [KOBOLDS] = true } },
  { nom = "Virgile", niveau = 5, quetes = {} } })
assert(#c.aFaire == 0, "quête d'avant de Léo : aucun écart")
-- Quête lancée par un objet (base : objet de départ) : l'écart nomme l'objet et l'endroit où un membre l'a ramassé
-- (son origine relevée : une position, sans PNJ) ; sans ramassage connu, l'origine donnée par la base des quêtes.
local COLLECTEUR = 123
local BASEO = { [COLLECTEUR] = { objet = 1307, origine = { nom = "Plan de route du Collecteur", pnjs = { "Rivepatte chétif" } } } }
c = ns.calculer({ { nom = "Léo", niveau = 5, quetes = { [COLLECTEUR] = aPrendre({ carte = 1436, x = 30, y = 40 }) } },
  { nom = "Virgile", niveau = 5, quetes = {} } }, 0, nil, BASEO)
x = seul(c.aFaire, "prendre", "Virgile", COLLECTEUR)
assert(x.donneur == nil and x.objet.id == 1307 and x.objet.nom == "Plan de route du Collecteur", "l'objet, nommé")
assert(x.objet.ramasse.carte == 1436 and x.objet.ramasse.x == 30 and x.objet.ramasse.y == 40, "où Léo l'a ramassé")
c = ns.calculer({ { nom = "Léo", niveau = 5, quetes = { [COLLECTEUR] = kobolds(false) } },
  { nom = "Virgile", niveau = 5, quetes = {} } }, 0, nil, BASEO)
x = seul(c.aFaire, "prendre", "Virgile", COLLECTEUR)
assert(x.objet.ramasse == nil and x.objet.pnjs[1] == "Rivepatte chétif", "sans ramassage : lâché par les Rivepatte")
-- Ni relevé ni base : l'écart existe quand même, sans endroit.
c = ns.calculer({ { nom = "Léo", niveau = 5, quetes = { [KOBOLDS] = kobolds(false) } }, { nom = "Virgile", niveau = 5, quetes = {} } })
x = seul(c.aFaire, "prendre", "Virgile", KOBOLDS)
assert(x.donneur == nil and x.objet == nil, "sans endroit")
-- Personnelle (#7) ou niveau insuffisant (#7) : pas « à prendre soi-même ».
c = ns.calculer({ { nom = "Léo", niveau = 5, quetes = { [KOBOLDS] = { finie = false, objectifs = {}, partageable = false, personnelle = true } } },
  { nom = "Virgile", niveau = 5, quetes = {} } })
assert(#c.aFaire == 0, "personnelle : rien à prendre")
c = ns.calculer({ { nom = "Léo", niveau = 12, quetes = { [KOBOLDS] = kobolds(false) } }, { nom = "Virgile", niveau = 5, quetes = {} } },
  0, nil, { [KOBOLDS] = { niveau_requis = 10 } })
seul(c.aFaire, "niveau", "Léo", KOBOLDS)
-- Résorbé : tous l'ont, ou l'ont déjà rendue ; l'écart n'apparaît plus.
c = ns.calculer({ { nom = "Virgile", niveau = 5, quetes = { [KOBOLDS] = kobolds(true) } },
  { nom = "Léo", niveau = 5, quetes = { [KOBOLDS] = kobolds() } } })
assert(#c.aFaire == 0, "partagée : l'écart n'apparaît plus")
c = ns.calculer({ { nom = "Virgile", niveau = 5, quetes = { [KOBOLDS] = kobolds(true) } },
  { nom = "Léo", niveau = 5, quetes = {}, rendues = { [KOBOLDS] = true } } })
assert(#c.aFaire == 1 and c.aFaire[1].type == "avance", "déjà rendue par Léo : rien à partager (elle est en avance)")

-- Quête écartée (#21) : « la Compagnie ne fait pas celle-là », décidé par n'importe quel membre (ecartees : les décisions
-- de la Compagnie, la plus récente par quête). Elle disparaît des écarts et de l'avancement commun chez tous.
local function ecartee(par, date) return { ecartee = true, date = date or 100, par = par or "Virgile" } end
local deux = { { nom = "Virgile", niveau = 5, quetes = { [KOBOLDS] = kobolds(true) } }, { nom = "Léo", niveau = 5, quetes = {} } }
c = ns.calculer(deux, 0, { [KOBOLDS] = ecartee("Léo") })
assert(c.quetes[KOBOLDS] == nil, "écartée : hors de l'avancement commun")
x = seul(c.aFaire, "ecartee", "Virgile", KOBOLDS) -- pas à partager à Léo : « Abandonner aussi » chez Virgile, qui l'a
assert(x.par == "Léo", "écartée par Léo")
assert(#c.aPart == 1 and c.aPart[1].membre == "Virgile" and c.aPart[1].ecartee, "gardée par Virgile : sa quête, nommée")
-- Remettre : elle revient (à partager, dans l'avancement commun).
c = ns.calculer(deux, 0, { [KOBOLDS] = { ecartee = false, date = 200, par = "Virgile" } })
seul(c.aFaire, "partager", "Virgile", KOBOLDS)
assert(c.quetes[KOBOLDS] and #c.aPart == 0, "remise : de nouveau une quête de la Compagnie")
-- Abandon dans le jeu par Virgile (= écartée par lui) : « Abandonner aussi » chez Léo et chez Mira, qui l'ont encore ;
-- s'ils la gardent, elle compte comme leur quête, nommée, avec leur avancement, hors de l'avancement commun.
c = ns.calculer({
  { nom = "Virgile", niveau = 5, quetes = {} },
  { nom = "Léo", niveau = 5, quetes = { [PATTES] = pattes(3) } },
  { nom = "Mira", niveau = 5, quetes = { [PATTES] = pattes(6) } },
}, 0, { [PATTES] = ecartee("Virgile") })
assert(#c.aFaire == 2 and c.aFaire[1].type == "ecartee" and c.aFaire[1].membre == "Léo" and c.aFaire[2].membre == "Mira",
  "« Abandonner aussi » chez Léo et Mira")
assert(c.quetes[PATTES] == nil and #c.aPart == 2 and c.aPart[1].membre == "Léo" and c.aPart[1].objectifs[1].fait == 3,
  "gardée par Léo : nommée, avec son avancement, hors de l'avancement commun")
-- Plus personne ne l'a : plus rien. Rendue en avance par un membre : rien non plus (écartée).
c = ns.calculer({ { nom = "Virgile", niveau = 5, quetes = {} }, { nom = "Léo", niveau = 5, quetes = {} } }, 0, { [PATTES] = ecartee() })
assert(#c.aFaire == 0 and #c.aPart == 0, "écartée par tous : rien")
c = ns.calculer({ { nom = "Virgile", niveau = 5, quetes = {}, rendues = { [PATTES] = true } },
  { nom = "Léo", niveau = 5, quetes = { [PATTES] = pattes(5) } } }, 0, { [PATTES] = ecartee() })
seul(c.aFaire, "ecartee", "Léo", PATTES)
-- Les écarts de plusieurs quêtes : triés par quête, toujours dans le même ordre.
c = ns.calculer({
  { nom = "Virgile", niveau = 5, quetes = { [KOBOLDS] = kobolds(true), [PATTES] = { finie = false, objectifs = {}, partageable = true } } },
  { nom = "Léo", niveau = 5, quetes = {} },
}, 0, { [KOBOLDS] = ecartee() })
assert(#c.aFaire == 2 and c.aFaire[1].quete == PATTES and c.aFaire[1].type == "partager" and c.aFaire[2].type == "ecartee",
  "trié par quête")

-- Quête en avance (#8) : rendue par un seul membre, les autres en cours → « en avance » chez chacun des autres qui ne
-- l'a pas finie, jamais chez celui qui l'a rendue ; résorbée quand il l'a finie.
c = ns.calculer({
  { nom = "Virgile", niveau = 10, quetes = {}, rendues = { [PATTES] = true } },
  { nom = "Léo", niveau = 10, absent = true, quetes = { [PATTES] = pattes(5) } },
  { nom = "Mira", niveau = 10, quetes = { [PATTES] = pattes(2) } },
})
assert(#c.aFaire == 2, "chez Léo et chez Mira : " .. #c.aFaire)
for i, nom in ipairs({ "Léo", "Mira" }) do
  x = c.aFaire[i]
  assert(x.type == "avance" and x.membre == nom and x.quete == PATTES, ("écart %s %s"):format(x.type, x.membre))
  assert(#x.par == 1 and x.par[1] == "Virgile", "rendue par Virgile")
end
c = ns.calculer({
  { nom = "Virgile", niveau = 10, quetes = {}, rendues = { [PATTES] = true } },
  { nom = "Léo", niveau = 10, quetes = { [PATTES] = pattes(8) } },
})
assert(#c.aFaire == 0, "Léo l'a finie : résorbée")
assert(c.quetes[PATTES].aRendre, "et à rendre")

-- Foyer de la Compagnie (#9) : deux auberges → le foyer est celle du membre lié le plus récemment ; « foyer différent »
-- chez l'autre, avec l'auberge où se lier. Une liaison sans date (faite add-on éteint) ne l'emporte jamais.
local OR, HURLEVENT = "Comté-de-l'Or", "Hurlevent"
c = ns.calculer({
  { nom = "Virgile", niveau = 5, quetes = {}, auberge = HURLEVENT, liaison = 1000 },
  { nom = "Léo", niveau = 5, absent = true, quetes = {}, auberge = OR, liaison = 2000 },
  { nom = "Mira", niveau = 5, quetes = {}, auberge = OR },
}, 5000)
assert(c.foyer == OR, "foyer : la liaison la plus récente, " .. tostring(c.foyer))
x = seul(c.aFaire, "foyer", "Virgile", nil)
assert(x.auberge == OR, "se lier à Comté-de-l'Or")
c = ns.calculer({
  { nom = "Virgile", niveau = 5, quetes = {}, auberge = HURLEVENT, liaison = 3000 },
  { nom = "Léo", niveau = 5, quetes = {}, auberge = OR, liaison = 2000 },
}, 5000)
assert(c.foyer == HURLEVENT and c.aFaire[1].membre == "Léo", "Virgile se lie ensuite à Hurlevent : c'est le foyer, Léo invité")
c = ns.calculer({ { nom = "Virgile", niveau = 5, quetes = {}, auberge = HURLEVENT }, { nom = "Léo", niveau = 5, quetes = {}, auberge = OR } }, 5000)
assert(c.foyer == nil and #c.aFaire == 0, "aucune date connue : pas de foyer, rien de deviné")
c = ns.calculer({ { nom = "Virgile", niveau = 5, quetes = {}, auberge = OR, liaison = 10 }, { nom = "Léo", niveau = 5, quetes = {} } }, 5000)
assert(c.foyer == OR and #c.aFaire == 0, "un membre jamais entendu (sans auberge) : pas d'écart")
-- Avec une quête : le foyer différent passe en tête, l'ordre reste fixe.
c = ns.calculer({
  { nom = "Virgile", niveau = 5, quetes = { [KOBOLDS] = kobolds(true) }, auberge = HURLEVENT, liaison = 1 },
  { nom = "Léo", niveau = 5, quetes = {}, auberge = OR, liaison = 2 },
}, 5000)
assert(#c.aFaire == 2 and c.aFaire[1].type == "foyer" and c.aFaire[2].type == "partager", "foyer en tête")

-- Pierre de la Compagnie : une pierre en recharge → indisponible, avec le temps restant (la plus longue) ; toutes
-- prêtes → 0. Un absent compte avec sa recharge recalculée : sa fin (heure serveur de son envoi + recharge) moins
-- l'heure de maintenant ; finie depuis son envoi, elle ne retient plus. Un membre jamais entendu ne retient pas.
c = ns.calculer({
  { nom = "Virgile", niveau = 5, quetes = {} },
  { nom = "Léo", niveau = 5, quetes = {}, finRecharge = 7400 },
  { nom = "Mira", niveau = 5, absent = true, quetes = {}, finRecharge = 6200 },
}, 5000)
assert(c.pierre == 2400, "indisponible : 40 min, la plus longue recharge, " .. c.pierre)
c = ns.calculer({
  { nom = "Virgile", niveau = 5, quetes = {} },
  { nom = "Mira", niveau = 5, absent = true, quetes = {}, finRecharge = 6200 }, -- envoyée à 5000 avec 20 min de recharge
}, 5600)
assert(c.pierre == 600, "absente : recharge recalculée depuis son envoi, 10 min, " .. c.pierre)
c = ns.calculer({ { nom = "Virgile", niveau = 5, quetes = {} },
  { nom = "Mira", niveau = 5, absent = true, quetes = {}, finRecharge = 6200 } }, 9000)
assert(c.pierre == 0, "sa recharge est finie depuis : prête")
assert(ns.calculer({ { nom = "Virgile", niveau = 5, quetes = {} }, { nom = "Léo" } }, 9000).pierre == 0, "jamais entendu : prête")

-- Quêtes d'avant (#20) : fondée en cours d'aventure, chacun arrive avec les restes de sa zone de départ. Elles sont à
-- part (nommées, avec l'avancement de qui l'a), sans écart, et ne font attendre personne.
local TELDRASSIL, COMTE = 2002, 2001 -- à part : triées par quête
c = ns.calculer({
  { nom = "Virgile", niveau = 12, quetes = { [COMTE] = kobolds(true) }, avant = { [COMTE] = true } },
  { nom = "Léo", niveau = 13, quetes = { [TELDRASSIL] = pattes(8) }, avant = { [TELDRASSIL] = true } },
})
assert(next(c.quetes) == nil, "journaux différents : aucune quête de la Compagnie")
assert(#c.aFaire == 0, "aucun écart (ni à partager, ni en attente) : " .. #c.aFaire)
assert(#c.aPart == 2, "deux quêtes à part : " .. #c.aPart)
local a = c.aPart[2]
assert(a.quete == TELDRASSIL and a.membre == "Léo" and a.aRendre, "la quête de Léo est à part, À rendre sans attendre Virgile")
assert(a.objectifs[1].fait == 8, "avec l'avancement de Léo")
assert(c.aPart[1].quete == COMTE and c.aPart[1].membre == "Virgile" and not c.aPart[1].aRendre, "celle de Virgile")
-- Une quête d'avant que tous les membres ont (d'avant chez chacun) redevient une quête de la Compagnie (même zone de départ).
c = ns.calculer({
  { nom = "Virgile", niveau = 12, quetes = { [COMTE] = pattes(8) }, avant = { [COMTE] = true } },
  { nom = "Léo", niveau = 12, quetes = { [COMTE] = pattes(3) }, avant = { [COMTE] = true } },
})
assert(c.quetes[COMTE] and c.quetes[COMTE].objectifs[1].fait == 3 and #c.aPart == 0, "tous l'ont : commune, 3/8")
-- Mira (jamais entendue) ne l'a pas : elle reste à part.
c = ns.calculer({
  { nom = "Virgile", niveau = 12, quetes = { [COMTE] = pattes(8) }, avant = { [COMTE] = true } },
  { nom = "Léo", niveau = 12, quetes = { [COMTE] = pattes(3) }, avant = { [COMTE] = true } }, { nom = "Mira" },
})
assert(not c.quetes[COMTE] and #c.aPart == 2, "d'avant chez tous ceux qui l'ont, pas tous : à part, chez chacun qui l'a")
-- Une quête d'avant chez Virgile, que Léo a prise après la fondation : de la Compagnie ; Mira, qui ne l'a pas, la reçoit
-- par « Partager » de qui peut la partager (Virgile : le jeu ne dit « partageable » que pour mes quêtes).
c = ns.calculer({
  { nom = "Virgile", niveau = 12, quetes = { [COMTE] = { finie = false, objectifs = { { fait = 6, total = 8 } }, partageable = true } },
    avant = { [COMTE] = true } },
  { nom = "Léo", niveau = 12, quetes = { [COMTE] = pattes(2) } },
  { nom = "Mira", niveau = 12, quetes = {} },
})
assert(c.quetes[COMTE] and #c.aPart == 0, "prise après la fondation par Léo : de la Compagnie")
assert(c.quetes[COMTE].objectifs[1].fait == 0 and table.concat(c.quetes[COMTE].enAttente, ",") == "Virgile,Léo,Mira",
  "la quête d'avant de Virgile compte normalement, Mira à 0")
x = seul(c.aFaire, "partager", "Virgile", COMTE)
assert(#x.manquants == 1 and x.manquants[1] == "Mira", "Mira reçoit « Partager »")
-- Une quête en avance ne compte que pour une remise vue après l'entrée : Léo a rendu COMTE avant (renduesAvant), il
-- ne retient pas la Compagnie et rien n'est en avance ; rendue après (rendues) : en avance.
c = ns.calculer({
  { nom = "Virgile", niveau = 12, quetes = { [COMTE] = pattes(8) } },
  { nom = "Léo", niveau = 12, quetes = {}, renduesAvant = { [COMTE] = true } },
})
assert(#c.aFaire == 0, "rendue avant l'entrée : pas en avance")
assert(c.quetes[COMTE].aRendre, "et Léo ne retient pas la Compagnie")
c = ns.calculer({
  { nom = "Virgile", niveau = 12, quetes = { [COMTE] = pattes(5) } },
  { nom = "Léo", niveau = 12, quetes = {}, rendues = { [COMTE] = true } },
})
seul(c.aFaire, "avance", "Virgile", COMTE)
-- Rendue avant l'entrée : pas à partager à Léo non plus.
c = ns.calculer({ { nom = "Virgile", niveau = 5, quetes = { [KOBOLDS] = kobolds(true) } },
  { nom = "Léo", niveau = 5, quetes = {}, renduesAvant = { [KOBOLDS] = true } } })
assert(#c.aFaire == 0, "déjà faite par Léo avant l'entrée : rien à partager")

-- La suite d'une quête (#25, le bandeau d'abandon) : ses suites, de proche en proche, chacune une fois (une boucle dans
-- la base ne fait pas tourner en rond) ; une quête sans suite connue : rien.
local BASE_SUITE = { [1001] = { suites = { 1002, 1004 } }, [1002] = { suites = { 1003 } }, [1003] = { suites = { 1001 } } }
assert(table.concat(ns.suite(BASE_SUITE, 1001), ",") == "1002,1004,1003", "la suite : " .. table.concat(ns.suite(BASE_SUITE, 1001), ","))
assert(#ns.suite(BASE_SUITE, 1004) == 0 and #ns.suite({}, 1001) == 0, "sans suite connue : rien")

-- Peut-il la prendre ? (raceID, classID ; listes de la base, nil : toutes ; une quête inconnue de la base : oui.)
assert(ns.peutPrendre({ races = { 1, 3 } }, 3, 1) and not ns.peutPrendre({ races = { 1, 3 } }, 4, 1), "race")
assert(ns.peutPrendre({ classes = { 2 } }, 1, 2) and not ns.peutPrendre({ classes = { 2 } }, 1, 1) and ns.peutPrendre(nil, 1, 1), "classe")

-- Quête personnelle (#7) : le jeu interdit aux autres de la prendre (classe, race : la base des quêtes ; chaque membre
-- porte sa race et sa classe). Pas d'écart ; à part chez tous, nommée, avec l'avancement de qui l'a.
local PALADIN = 1780 -- « La lumière sacrée », paladins seulement (classID 2)
local BASE_PALADIN = { [PALADIN] = { classes = { 2 } } }
c = ns.calculer({
  { nom = "Virgile", niveau = 12, race = 1, classe = 2, quetes = { [PALADIN] = { finie = false, partageable = true,
    objectifs = { { texte = "Lettre", fait = 0, total = 1 } } } } },
  { nom = "Léo", niveau = 12, race = 1, classe = 1, quetes = {} },
}, 0, nil, BASE_PALADIN)
assert(c.quetes[PALADIN] == nil, "quête de paladin : hors de l'avancement commun")
assert(#c.aPart == 1 and c.aPart[1].quete == PALADIN and c.aPart[1].membre == "Virgile" and c.aPart[1].personnelle
  and c.aPart[1].objectifs[1].total == 1, "à part, nommée (Virgile), avec son avancement")
assert(#c.aFaire == 0, "personnelle : pas d'écart, pas de « Partager »")
-- Léo, dont la classe est inconnue (rien n'est deviné) : une quête comme une autre, à partager.
c = ns.calculer({
  { nom = "Virgile", niveau = 12, race = 1, classe = 2, quetes = { [PALADIN] = { finie = false, partageable = true, objectifs = {} } } },
  { nom = "Léo", niveau = 12, quetes = {} },
}, 0, nil, BASE_PALADIN)
assert(c.quetes[PALADIN] and #c.aFaire == 1 and c.aFaire[1].type == "partager", "classe de Léo inconnue : à partager")
-- Deux paladins, un guerrier : personnelle aussi (le guerrier ne peut pas la prendre) ; chacun à part avec la sienne.
c = ns.calculer({
  { nom = "Virgile", niveau = 12, race = 1, classe = 2, quetes = { [PALADIN] = { finie = false, objectifs = {} } } },
  { nom = "Léo", niveau = 12, race = 1, classe = 1, quetes = {} },
  { nom = "Mira", niveau = 12, race = 3, classe = 2, quetes = { [PALADIN] = { finie = true, objectifs = {} } } },
}, 0, nil, BASE_PALADIN)
assert(#c.aPart == 2 and c.aPart[2].membre == "Mira" and c.aPart[2].aRendre and #c.aFaire == 0, "chacun la sienne, à part")
-- Marquée personnelle à la main (sans Questie : la base ne dit rien de la quête) : personnelle, sans écart.
c = ns.calculer({
  { nom = "Virgile", niveau = 5, quetes = { [KOBOLDS] = { finie = false, partageable = true, personnelle = true, objectifs = {} } } },
  { nom = "Léo", niveau = 5, quetes = {} },
})
assert(c.quetes[KOBOLDS] == nil and #c.aPart == 1 and c.aPart[1].personnelle and #c.aFaire == 0,
  "marquée personnelle à la main : à part, pas d'écart")

-- Niveau insuffisant (#7) : niveau requis 10 (base des quêtes), Léo niveau 9 → « au niveau 10 pour toute la Compagnie »
-- chez qui l'a, pas de « Partager » ; résorbé quand Léo passe 10 (la quête redevient à partager).
local BASE_DIX = { [KOBOLDS] = { niveau_requis = 10 } }
local function dix(niveauLeo, base, appris)
  return ns.calculer({ { nom = "Virgile", niveau = 10, quetes = { [KOBOLDS] = kobolds(true) } },
    { nom = "Léo", niveau = niveauLeo, quetes = {} } }, 0, nil, base, nil, appris)
end
x = seul(dix(9, BASE_DIX).aFaire, "niveau", "Virgile", KOBOLDS)
assert(x.niveau == 10, "au niveau 10")
assert(dix(9, BASE_DIX).quetes[KOBOLDS], "toujours une quête de la Compagnie")
seul(dix(10, BASE_DIX).aFaire, "partager", "Virgile", KOBOLDS)
-- Non partageable ou pas dit (la quête d'un autre membre) : l'écart quand même, pour qui l'a.
c = ns.calculer({ { nom = "Virgile", niveau = 9, quetes = {} }, { nom = "Léo", niveau = 12, quetes = { [KOBOLDS] = kobolds() } } },
  0, nil, BASE_DIX)
seul(c.aFaire, "niveau", "Léo", KOBOLDS)
-- Sans base : le niveau appris quand un partage échoue (appris = { [id] = niveau requis }) fait le même écart.
seul(dix(9, {}, { [KOBOLDS] = 10 }).aFaire, "niveau", "Virgile", KOBOLDS)
seul(dix(9, {}).aFaire, "partager", "Virgile", KOBOLDS)
assert(seul(dix(9, { [KOBOLDS] = { niveau_requis = 8 } }, { [KOBOLDS] = 10 }).aFaire, "niveau", "Virgile", KOBOLDS).niveau == 10,
  "le plus haut des deux")

-- Les zones du menu de la zone de la Compagnie (#24) : d'après la base des quêtes, une zone par areaID avec au moins 10
-- quêtes ; son niveau d'entrée, le niveau requis du premier quart de ses quêtes ; les zones dont la Compagnie a le niveau
-- d'entrée d'abord (de la plus haute à la plus basse), les autres ensuite (de la plus basse à la plus haute).
local BASE_ZONES, n = {}, 0
local function zone(areaID, requis, combien)
  for _ = 1, combien do n = n + 1; BASE_ZONES[n] = { zone = areaID, niveau_requis = requis } end
end
zone(12, 1, 12) -- Forêt d'Elwynn : 1
zone(40, 9, 10); zone(40, 1, 2) -- Marche de l'Ouest : 9 (deux quêtes de niveau 1 ne la font pas commencer à 1)
zone(148, 10, 10) -- Sombrivage : 10
zone(10, 20, 10) -- Bois de la Pénombre : 20
zone(1581, 15, 6) -- les Mortemines : trop peu de quêtes, une instance
zone(-101, 1, 30) -- une catégorie de QuestieDB (métier) : pas une zone
local zs = ns.zones(BASE_ZONES, 10)
local vu = {}
for i, z in ipairs(zs) do vu[i] = z.zone .. ":" .. z.niveau .. (z.ouverte and "" or "x") end
assert(table.concat(vu, ",") == "148:10,40:9,12:1,10:20x", "zones : " .. table.concat(vu, ","))

-- Un perso de la Horde (Compagnie#35) : la vraie réserve du socle pour la Horde (AzerothCommune#112), mise en forme comme
-- le fait le socle (les champs lus ici). Ses zones de départ ouvertes, pas celles de l'Alliance ; une chaîne de la Horde.
do
  local socle = {}
  assert(loadfile("AzerothCommune/QuetesReserve.lua"))("AzerothCommune", socle)
  local HORDE = {}
  for id, c in pairs(assert(loadstring(socle.quetesReserve.Horde))()) do
    HORDE[id] = { zone = c[2], niveau_requis = c[4], suites = c[9] }
  end
  local ouvertes = {}
  for _, z in ipairs(ns.zones(HORDE, 5)) do if z.ouverte then ouvertes[z.zone] = true end end
  assert(ouvertes[14] and ouvertes[85] and ouvertes[215], "Horde : Durotar, Tirisfal, Mulgore ouvertes")
  assert(not ouvertes[12] and not ouvertes[141], "Horde : ni Elwynn ni Teldrassil")
  assert(ns.suite(HORDE, 4641)[1] == 788, "Horde : Votre place en ce monde, puis 788")
end

-- Le contrôle des prérequis (#27), sur une base des quêtes fabriquée. Sombrivage (148) : le Bosquet des Anciens (952)
-- demande Teldrassil (940), au bout d'une chaîne de 4 quêtes à Teldrassil (141) qui commence par La clairière enchantée.
local SOMBRIVAGE, TELD = 148, 141
local HUMAIN, ELFE, GUERRIER, DRUIDE = 1, 4, 1, 11
local BASE = {
  [952] = { nom = "Bosquet des Anciens", zone = SOMBRIVAGE, prerequis_un = { 940 } },
  [937] = { nom = "La clairière enchantée", zone = TELD, suites = { 98392 }, donneur = { pnj = 3519, nom = "Sentinelle Arynia" } },
  [98392] = { zone = TELD, prerequis_un = { 937 }, suites = { 98398 } },
  [98398] = { zone = TELD, prerequis_un = { 98392 }, suites = { 940 } },
  [940] = { nom = "Teldrassil", zone = TELD, prerequis_un = { 98398 }, suites = { 952 } },
  [2000] = { zone = SOMBRIVAGE, suites = { 2001 } }, [2001] = { zone = SOMBRIVAGE, prerequis = { 2000 } }, -- dans la zone
  [2010] = { zone = SOMBRIVAGE, prerequis = { 2011 }, amorces = { 2011 } }, [2011] = { zone = TELD }, -- une amorce
  [2020] = { zone = SOMBRIVAGE, races = { ELFE }, prerequis = { 2021 } }, [2021] = { zone = TELD }, -- de race
  [2030] = { zone = SOMBRIVAGE, classes = { DRUIDE }, prerequis = { 2031 } }, [2031] = { zone = TELD }, -- de classe
  [2040] = { zone = SOMBRIVAGE, prerequis_un = { 2041, 2042 } }, [2041] = { zone = TELD }, [2042] = { zone = TELD }, -- un seul
  [2050] = { zone = SOMBRIVAGE, prerequis_un = { 2052 } }, [2051] = { zone = SOMBRIVAGE, prerequis_un = { 2052 } },
  [2052] = { zone = TELD, suites = { 2050, 2051 } }, -- un prérequis qui ouvre deux quêtes
}
local function faites(...) local t = {} for _, id in ipairs({ ... }) do t[id] = true end return function(id) return t[id] end end
local function paires(l) local t = {} for i, x in ipairs(l) do t[i] = x.quete .. ":" .. x.prerequis end return table.concat(t, ",") end
-- Virgile, humain guerrier, n'a rien fait ; 2042 compte (un seul suffit) : le Bosquet (chaîne hors de la zone), et 2050,
-- 2051 (2052) ; rien pour la chaîne dans la zone, l'amorce, la quête d'elfe, la quête de druide.
local mv = ns.prerequisManquants(SOMBRIVAGE, BASE, faites(2042), HUMAIN, GUERRIER, {})
assert(paires(mv) == "952:940,2050:2052,2051:2052", "les prérequis manquants de Virgile : " .. paires(mv))
-- Léo, elfe druide, a fait Teldrassil et 2052 : la quête d'elfe et la quête de druide lui demandent les leurs, à lui seul.
local ml = ns.prerequisManquants(SOMBRIVAGE, BASE, faites(940, 2052, 2041), ELFE, DRUIDE, {})
assert(paires(ml) == "2020:2021,2030:2031", "ceux de Léo : " .. paires(ml))
-- Une quête de la zone déjà faite ne demande rien (il accompagne les autres).
assert(paires(ns.prerequisManquants(SOMBRIVAGE, BASE, faites(2042, 952, 2050, 2051), HUMAIN, GUERRIER, {})) == "", "déjà faite : rien")
-- Le calcul : l'écart « prérequis manquant » chez Virgile seul, avec la chaîne, sa zone, son premier donneur, à qui.
local function calc(mv2, ml2, ecartees, mira)
  local membres = { { nom = "Virgile", niveau = 15, quetes = {}, prerequis = { zone = SOMBRIVAGE, manquants = mv2 } },
    { nom = "Léo", niveau = 15, quetes = {}, prerequis = { zone = SOMBRIVAGE, manquants = ml2 } } }
  if mira then membres[3] = mira end
  return ns.calculer(membres, 0, ecartees, BASE, SOMBRIVAGE)
end
local function ecartsDe(c, quete)
  local t = {}
  for _, x in ipairs(c.aFaire) do if x.type == "prerequis" and x.quete == quete then t[#t + 1] = x end end
  return t
end
c = calc(mv, {})
local g = ecartsDe(c, 952)
assert(#g == 1 and g[1].membre == "Virgile" and g[1].prerequis == 940, "le Bosquet : chez Virgile seul, rien chez l'elfe qui l'a fait")
assert(table.concat(g[1].chaine, ",") == "937,98392,98398,940" and g[1].zone == TELD and g[1].donneur.nom == "Sentinelle Arynia",
  "la chaîne (4 quêtes à Teldrassil), son premier donneur : " .. table.concat(g[1].chaine, ","))
assert(#g[1].manquants == 1 and not g[1].tous and #c.aControler == 0, "manque à Virgile seul ; personne à contrôler")
-- Personne ne l'a faite : chez chacun, « toute la Compagnie ».
g = ecartsDe(calc(mv, { { quete = 952, prerequis = 940 } }), 952)
assert(#g == 2 and g[1].tous and g[2].tous and g[1].membre == "Léo" and g[2].membre == "Virgile", "toute la Compagnie")
-- Écarter le Bosquet : l'écart disparaît, la chaîne aussi ; un prérequis qui ouvre aussi une quête gardée reste.
local ecBosquet = { [952] = { ecartee = true, date = 1, par = "Léo" }, [2050] = { ecartee = true, date = 1, par = "Léo" } }
c = calc(mv, {}, ecBosquet)
assert(#ecartsDe(c, 952) == 0 and #ecartsDe(c, 2050) == 0 and #ecartsDe(c, 2051) == 1, "écartées : leurs écarts disparaissent, 2051 reste")
local eff = ns.ecarteesEffectives(ecBosquet, BASE)
assert(eff[940] and eff[98398] and eff[98392] and eff[937] and eff[937].par == "Léo", "la chaîne du Bosquet est écartée avec lui")
assert(not eff[2052] and not eff[2051], "2052 ouvre aussi 2051, gardée : il reste")
assert(paires(ns.prerequisManquants(SOMBRIVAGE, BASE, faites(2042), HUMAIN, GUERRIER, eff)) == "2051:2052", "écartées : plus demandées")
-- Une écartée emporte aussi ses suites ; une quête qui a sa propre décision (remise) la garde.
eff = ns.ecarteesEffectives({ [937] = { ecartee = true, date = 1, par = "Mira" }, [98398] = { ecartee = false, date = 2, par = "Léo" } }, BASE)
assert(eff[98392] and not eff[98398] and not eff[940], "les suites d'une écartée, jusqu'à une quête remise")
-- Remettre le Bosquet : l'écart revient.
assert(#ecartsDe(calc(mv, {}, { [952] = { ecartee = false, date = 2, par = "Virgile" } }), 952) == 1, "remis : l'écart revient")
-- Mira, absente depuis le choix de la zone (son état couvre une autre zone), ou jamais entendue : à contrôler.
c = calc(mv, {}, nil, { nom = "Mira", absent = true, quetes = {}, prerequis = { zone = 40, manquants = {} } })
assert(#c.aControler == 1 and c.aControler[1] == "Mira" and ecartsDe(c, 952)[1].aControler[1] == "Mira", "Mira : à contrôler")
assert(#ecartsDe(c, 952) == 1, "on ne lui prête rien")
assert(#calc(mv, {}, nil, { nom = "Mira" }).aControler == 1, "jamais entendue : à contrôler")
assert(#ns.calculer({ { nom = "Virgile", quetes = {} } }, 0, nil, BASE, nil).aControler == 0, "sans zone : pas de contrôle")

print("Compagnie : calcul de la Compagnie OK")

-- L'arbre des chaînes (#33), sur une base des quêtes fabriquée : la Forêt (12), Teldrassil (141) pour un début hors zone.
local FORET, PALADIN = 12, 2
local ARBRE = {
  [100] = { nom = "Les loups", zone = FORET, niveau = 5, suites = { 101 } }, -- une chaîne de trois, au niveau 5
  [101] = { zone = FORET, niveau = 6, prerequis = { 100 }, suites = { 102 } },
  [102] = { zone = FORET, niveau = 7, prerequis = { 101 } },
  [200] = { nom = "Les kobolds", zone = FORET, niveau = 3 }, [201] = { zone = FORET, niveau = 4 }, -- deux fils qui se rejoignent
  [202] = { zone = FORET, niveau = 5, prerequis = { 200, 201 } },
  [210] = { zone = FORET, niveau = 20, niveau_requis = 18, prerequis_un = { 202, 9999 } }, -- un seul parmi plusieurs
  [400] = { zone = FORET, niveau = 10, prerequis = { 940 } }, -- au bout d'une chaîne de Teldrassil
  [937] = { zone = TELD, niveau = 2, suites = { 940 } }, [940] = { nom = "Teldrassil", zone = TELD, niveau = 4, prerequis = { 937 }, suites = { 400 } },
  [500] = { zone = FORET, niveau = 2, prerequis = { 501 }, amorces = { 501 } }, [501] = { zone = FORET, niveau = 1, suites = { 500 } }, -- une amorce
  [600] = { zone = FORET, niveau = 9 }, [601] = { zone = FORET, niveau = 1 }, -- seules
  [700] = { zone = FORET, niveau = 3, races = { ELFE } }, -- personne ne peut la prendre
  [800] = { zone = FORET, niveau = 8, classes = { PALADIN }, suites = { 801 } }, -- Léo seul, paladin
  [801] = { zone = FORET, niveau = 9, classes = { PALADIN }, prerequis = { 800 } },
}
local function arbre(membres, ecartees, deplies)
  local a = ns.arbreDesChaines(membres, ecartees, ARBRE, FORET, deplies)
  a.case, a.bande = {}, {}
  for _, c in ipairs(a.cases) do a.case[c.repliee and c.key or c.quete] = c end
  for _, b in ipairs(a.bandes) do a.bande[b.key] = b end
  return a
end
local function bandeDe(a, id) return a.bande[a.case[id].band] end
local function idsDe(a, b) -- les quêtes d'une bande, triées
  local t = {}
  for _, c in ipairs(a.cases) do if c.band == b.key then t[#t + 1] = c.quete end end
  table.sort(t)
  return table.concat(t, ",")
end
local function lie(a, de, vers)
  for _, l in ipairs(a.liens) do if not l.hidden and l.from.quete == de and l.to.quete == vers then return true end end
end
local function fin(fait, total) return { finie = fait == total, objectifs = { { fait = fait, total = total } } } end
local virgile = function(q) return { nom = "Virgile", niveau = 10, race = HUMAIN, classe = GUERRIER, quetes = q or {} } end
local leo = function(q) return { nom = "Léo", niveau = 10, race = HUMAIN, classe = PALADIN, absent = true, quetes = q or {} } end
local a = arbre({ virgile(), leo() })
-- Bandes : une par chaîne, par niveau de leur première quête (kobolds 3, loups 5, paladin 8, Teldrassil 10), les seules
-- en dernier ; toujours dans le même ordre.
local ordre = {}
for i, b in ipairs(a.bandes) do ordre[i] = idsDe(a, b) end
assert(table.concat(ordre, " | ") == "200,201,202,210 | 100,101,102 | 800,801 | 400,940 | 500,501,600,601", table.concat(ordre, " | "))
assert(a.bandes[#a.bandes].seules and not a.bandes[1].seules, "les quêtes seules : la dernière bande")
for _ = 1, 5 do
  local b = arbre({ virgile(), leo() })
  for i, x in ipairs(b.bandes) do assert(x.key == a.bandes[i].key, "ordre stable") end
end
-- Deux prérequis qui se rejoignent : une seule chaîne, chaque lien dessiné ; « un seul parmi plusieurs » relie aussi.
assert(lie(a, 200, 202) and lie(a, 201, 202) and lie(a, 202, 210) and lie(a, 100, 101) and lie(a, 101, 102), "les liens")
assert(not lie(a, 501, 500) and bandeDe(a, 500).seules, "une amorce ne relie pas")
-- Les quêtes seules, rangées par niveau ; les racines d'une chaîne ont leur rang (l'Arbre les range).
local seules = {}
for _, c in ipairs(a.cases) do if bandeDe(a, c.quete).seules then seules[#seules + 1] = c end end
table.sort(seules, function(x, y) return (x.index or 99) < (y.index or 99) end)
assert(seules[1].index and (seules[1].quete == 501 or seules[1].quete == 601), "la première seule : niveau 1")
assert(a.case[200].index and a.case[201].index and not a.case[202].index, "les racines ont leur rang, pas les suites")
for _, c in ipairs(a.cases) do assert(type(c.key) == "string" and a.bande[c.band], "clé texte, bande déclarée : " .. tostring(c.key)) end
-- Début hors zone : une seule case (le prérequis de Teldrassil qui ouvre la quête), avec sa zone ; pas la chaîne étrangère.
assert(a.case[940].horsZone == TELD and not a.case[937] and lie(a, 940, 400), "Teldrassil : une case hors zone, reliée")
-- Personne ne peut la prendre : absente ; seul Léo (paladin) : chaîne personnelle.
assert(not a.case[700], "quête impossible pour tous : hors de l'arbre")
assert(bandeDe(a, 800).personnelle == "Léo" and not bandeDe(a, 100).personnelle, "chaîne personnelle de Léo")
-- États : en cours avec l'avancement commun (Léo, absent, compte avec son dernier état connu), à rendre, écartée (elle
-- l'emporte sur tout), niveau insuffisant avec le niveau requis.
a = arbre({ virgile({ [100] = fin(5, 8), [200] = fin(1, 1), [201] = fin(1, 1) }),
  leo({ [100] = fin(3, 8), [200] = fin(1, 1), [601] = fin(0, 2) }) }, { [601] = { ecartee = true, date = 1, par = "Léo" } })
assert(a.case[100].etat == "enCours" and a.case[100].objectifs[1].fait == 3, "en cours : 3/8, l'absent compte")
assert(a.case[200].etat == "aRendre", "à rendre : finie chez tous")
assert(a.case[201].etat == "enCours" and a.case[201].objectifs[1].fait == 0, "prise par un seul : en cours, l'autre à 0")
assert(a.case[601].etat == "ecartee", "écartée, même prise")
assert(a.case[210].etat == "niveau" and a.case[210].requis == 18, "niveau insuffisant : 18 requis")

-- Ce que la Compagnie a fait (#34) : chaque membre envoie ses quêtes rendues de la zone (renduesZone, avec la zone
-- couverte) ; faite (par tous), disponible (tous ont les prérequis et le niveau, personne ne l'a), verrouillée.
local function rz(...) local t = {} for _, id in ipairs({ ... }) do t[id] = true end return { zone = FORET, quetes = t } end
local function avec(m, r) m.renduesZone = r return m end
a = arbre({ avec(virgile({ [102] = fin(0, 1) }), rz(200, 100, 940)), avec(leo({ [100] = fin(3, 8) }), rz(200, 940)) })
assert(a.case[200].etat == "faite" and not a.case[200].inegale, "faite : rendue par tous")
assert(a.case[940].etat == "faite", "le début hors zone, rendu par tous : fait")
assert(a.case[201].etat == "disponible", "disponible : sans prérequis, personne ne l'a")
assert(a.case[400].etat == "disponible", "disponible : Teldrassil fait par tous")
assert(a.case[202].etat == "verrouillee", "verrouillée : 201 manque")
local bl = a.case[202].bloque
assert(#bl == 2 and bl[1].prerequis[1] == 201 and #bl[1].prerequis == 1, "ce qui la bloque, pour chacun : 201")
-- Ce qui bloque : tous les prérequis (prerequis) à part de « un seul parmi plusieurs » (un), pour que la bulle dise et / ou.
do
  local b = { [1] = { zone = FORET, niveau = 1, suites = { 3 } }, [2] = { zone = FORET, niveau = 1, suites = { 3 } },
    [3] = { zone = FORET, niveau = 2, prerequis = { 1, 2 } }, [4] = { zone = FORET, niveau = 1, suites = { 6 } },
    [5] = { zone = FORET, niveau = 1, suites = { 6 } }, [6] = { zone = FORET, niveau = 2, prerequis_un = { 4, 5 } } }
  local r = ns.arbreDesChaines({ { nom = "Virgile", niveau = 10, quetes = {}, renduesZone = { zone = FORET, quetes = { [5] = true } } },
    { nom = "Léo", niveau = 10, quetes = {}, renduesZone = { zone = FORET, quetes = {} } } }, {}, b, FORET)
  local c = {}
  for _, x in ipairs(r.cases) do if x.quete then c[x.quete] = x end end
  local b3 = c[3].bloque[1]
  assert(#b3.prerequis == 2 and #b3.un == 0, "3 : 1 et 2, tous deux requis")
  assert(#c[6].bloque == 1 and c[6].bloque[1].membre == "Léo" and #c[6].bloque[1].prerequis == 0 and #c[6].bloque[1].un == 2,
    "6 : Virgile a fait 5 (un seul suffit) ; Léo, l'un de 4 ou 5")
end
-- Inégale : faite par Virgile, prise par Léo (absent : son dernier état connu) ; l'infobulle dit qui.
local ig = a.case[100].inegale
assert(a.case[100].etat == "enCours" and ig and ig.faites[1] == "Virgile" and ig.prises[1] == "Léo", "inégale : qui l'a faite, qui l'a prise")
assert(a.case[102].inegale and a.case[102].inegale.prises[1] == "Virgile", "prise par un seul : inégale")
-- Bloquée pour un seul membre : Léo n'a pas fait 100, prérequis de 101.
bl = a.case[101].bloque
assert(a.case[101].etat == "verrouillee" and #bl == 1 and bl[1].membre == "Léo" and bl[1].prerequis[1] == 100, "bloquée pour Léo seul")
-- Niveau insuffisant pour un seul : le niveau requis, pour qui.
bl = a.case[210].bloque
assert(a.case[210].etat == "niveau" and bl[1].niveau == 18, "niveau 18 requis")
-- À contrôler : l'état de Mira couvre une autre zone ; on ne lui prête rien (ni fait, ni bloqué), elle est nommée.
a = arbre({ avec(virgile(), rz(200)), avec(leo(), rz(200)), avec({ nom = "Mira", niveau = 10, quetes = {} }, { zone = 40, quetes = {} }) })
assert(#a.aControler == 1 and a.aControler[1] == "Mira", "Mira : à contrôler")
assert(a.case[200].etat == "faite" and a.case[201].etat == "disponible", "rien prêté à Mira")
assert(#arbre({ virgile(), leo() }).aControler == 2, "sans le champ : à contrôler")
-- Repli : une chaîne faite par tous se replie en une ligne (son nom, son nombre de quêtes) ; dépliée au clic (deplies,
-- local) ; une chaîne écartée aussi.
local toutes = rz(100, 101, 102)
a = arbre({ avec(virgile(), toutes), avec(leo(), toutes) }, { [800] = { ecartee = true, date = 1, par = "Léo" } })
local loups = a.bande.B100
local ligne = a.case["CB100"]
assert(not a.case[100] and not a.case[101] and ligne and ligne.repliee and ligne.n == 3 and ligne.quete == 100 and ligne.etat == "faite", "chaîne faite : une ligne")
assert(loups.repliee, "la bande est repliée")
local pal = a.case["CB800"]
assert(pal and pal.repliee and pal.etat == "ecartee" and pal.n == 2 and not a.case[801], "chaîne écartée : une ligne, barrée")
a = arbre({ avec(virgile(), toutes), avec(leo(), toutes) }, nil, { B100 = true })
assert(a.case[100] and a.case[101] and a.case[102] and a.case[101].repliable and not a.case["CB100"], "dépliée : ses quêtes, repliables")
assert(not a.case[200].repliable, "une chaîne pas finie ne se replie pas")

print("Compagnie : arbre des chaînes OK")

-- Les membres (Membres.lua) : fonder, accepter, refuser, quitter, retirer, sans l'API du jeu, sous la même garde.
-- Trois clients (Virgile, Léo, Mira) dans un même groupe du jeu : ce que l'un envoie au groupe, les autres le reçoivent,
-- avec le GUID que le serveur donne pour l'expéditeur.
assert(loadfile("Compagnie/Membres.lua"))("Compagnie", ns)
local V, L, M, Z = "Player-1-0000000V", "Player-1-0000000L", "Player-1-0000000M", "Player-1-0000000Z"
local NOMS = { [V] = "Virgile Marteau", [L] = "Léo Lame", [M] = "Mira Feuille", [Z] = "Zoé Pierre" }
local clients
local file -- une table : les messages attendent livrer() (des envois qui se croisent) ; nil : livrés tout de suite
local function distribuer(de, texte)
  for _, autre in pairs(clients) do
    if autre ~= de then ns.recevoir(autre.e, autre.moi, autre.groupe, de.moi, texte, autre.io) end
  end
end
local function livrer()
  while #file > 0 do distribuer(unpack(table.remove(file, 1))) end
  file = nil
end
local function groupeDe(moi, guids)
  local g = { { guid = moi, nom = NOMS[moi] } }
  for _, x in ipairs(guids) do if x ~= moi then g[#g + 1] = { guid = x, nom = NOMS[x] } end end
  return g
end
local horloge = 1764000000 -- l'heure serveur, une seconde de plus à chaque lecture (les listes datées se suivent)
local function client(moi, guids)
  local cl = { moi = moi, e = { db = {}, moi = moi }, dits = {}, envoyes = {}, propositions = 0, maj = 0 }
  cl.groupe = groupeDe(moi, guids)
  cl.io = {
    envoyer = function(texte)
      cl.envoyes[#cl.envoyes + 1] = texte
      if file then file[#file + 1] = { cl, texte } else distribuer(cl, texte) end
    end,
    dire = function(texte) cl.dits[#cl.dits + 1] = texte end,
    proposer = function() cl.propositions = cl.propositions + 1 end,
    maj = function() cl.maj = cl.maj + 1 end,
    entrer = function() cl.entrees = (cl.entrees or 0) + 1 end,
    heure = function() horloge = horloge + 1; return horloge end,
  }
  return cl
end
local function groupe(guids)
  clients = {}
  for _, g in ipairs(guids) do clients[g] = client(g, guids) end
  return clients
end
local function noms(cl)
  local t = {}
  for i, m in ipairs(cl.e.db.compagnie and cl.e.db.compagnie.membres or {}) do t[i] = m.nom end
  return table.concat(t, ",")
end
local function dernier(cl) return cl.dits[#cl.dits] or "" end
local function dit(cl, motif)
  for _, d in ipairs(cl.dits) do if d:find(motif, 1, true) then return true end end
  return false
end

-- Fonder hors d'un groupe : refusé avec un message clair, rien n'est envoyé.
local seul = groupe({ V })[V]
local ok, raison = ns.fonder(seul.e, V, seul.groupe, "id1", seul.io)
assert(not ok and raison:find("groupe", 1, true), "hors d'un groupe : refusé, la raison parle du groupe")
assert(#seul.envoyes == 0, "rien n'est envoyé")

-- Plus de 5 personnages (un raid) : refusé.
local six = groupe({ V, L, M, Z, "Player-1-0000000A", "Player-1-0000000B" })[V]
ok, raison = ns.fonder(six.e, V, six.groupe, "id1", six.io)
assert(not ok and raison:find("5", 1, true) and raison:find("6", 1, true), "6 personnages : refusé, 5 au plus, 6 dans le groupe")

-- Virgile fonde avec Léo et Mira : Léo accepte, Mira refuse ; la Compagnie, c'est Virgile et Léo, chez les deux.
local c = groupe({ V, L, M })
assert(ns.fonder(c[V].e, V, c[V].groupe, "id1", c[V].io), "fonder dans un groupe de 3")
assert(c[V].envoyes[1] == "P;id1;" .. V .. "," .. L .. "," .. M, "proposition : le fondateur d'abord")
assert(c[L].propositions == 1 and c[M].propositions == 1 and c[V].propositions == 0, "chaque autre reçoit la proposition")
assert(not c[L].e.proposition.deja, "Léo n'est membre d'aucune Compagnie")
ns.repondre(c[L].e, true, c[L].io)
assert(c[V].e.db.compagnie == nil, "rien n'est fondé tant que Mira n'a pas répondu")
ns.repondre(c[M].e, false, c[M].io)
assert(dit(c[V], "Mira Feuille refuse"), "le fondateur apprend le refus : " .. dernier(c[V]))
assert(noms(c[V]) == "Virgile Marteau,Léo Lame", "chez Virgile : " .. noms(c[V]))
assert(noms(c[L]) == "Virgile Marteau,Léo Lame", "chez Léo : " .. noms(c[L]))
assert(c[M].e.db.compagnie == nil, "Mira a refusé : pas membre")
assert(c[V].e.db.compagnie.id == "id1" and c[L].e.db.compagnie.id == "id1", "même Compagnie chez les deux")
assert(c[L].maj > 0, "la liste de Léo est redessinée")
-- L'entrée dans la Compagnie (#20) : chacun note ses quêtes d'avant, une fois ; pas Mira, qui a refusé.
assert(c[V].entrees == 1 and c[L].entrees == 1 and not c[M].entrees, "entrée notée chez le fondateur et chez Léo")

-- Déjà membre : il ne peut pas en fonder une autre, et une proposition reçue le dit (refus envoyé tout seul).
ok, raison = ns.fonder(c[L].e, L, c[L].groupe, "id2", c[L].io)
assert(not ok and raison:find("déjà membre", 1, true), "déjà membre : ne peut pas fonder")
assert(ns.fonder(c[M].e, M, c[M].groupe, "id3", c[M].io), "Mira fonde avec Virgile et Léo, déjà membres")
assert(c[L].e.proposition.deja and c[V].e.proposition.deja, "la proposition dit qu'ils sont déjà membres")
assert(c[M].e.db.compagnie == nil and c[M].e.fondation == nil, "les deux ont refusé : pas de Compagnie pour Mira")
assert(dit(c[M], "Léo Lame est déjà membre d'une Compagnie"), "Mira apprend que Léo est déjà membre : " .. dernier(c[M]))
ns.repondre(c[L].e, true, c[L].io) -- accepter quand même : sans effet
assert(c[L].e.db.compagnie.id == "id1", "Léo reste dans sa Compagnie")

-- Personne n'accepte (délai écoulé, ou tous refusent) : pas de Compagnie.
local d = groupe({ V, L })
ns.fonder(d[V].e, V, d[V].groupe, "id4", d[V].io)
ns.cloturer(d[V].e, V, d[V].groupe, d[V].io) -- le délai d'une minute est écoulé, Léo n'a pas répondu
assert(d[V].e.db.compagnie == nil and dernier(d[V]):find("Personne", 1, true), "personne n'a accepté : pas de Compagnie")
ns.repondre(d[L].e, true, d[L].io) -- trop tard
assert(d[L].e.db.compagnie == nil and d[V].e.db.compagnie == nil, "une réponse après la clôture ne fonde rien")

-- Une Compagnie de trois : Mira quitte, la liste se met à jour chez les autres ; puis Virgile retire Léo.
local t = groupe({ V, L, M })
ns.fonder(t[V].e, V, t[V].groupe, "id5", t[V].io)
ns.repondre(t[L].e, true, t[L].io)
ns.repondre(t[M].e, true, t[M].io)
assert(noms(t[M]) == "Virgile Marteau,Léo Lame,Mira Feuille", "trois membres chez Mira : " .. noms(t[M]))
ns.quitter(t[M].e, t[M].io)
assert(t[M].e.db.compagnie == nil, "Mira n'est plus membre")
assert(noms(t[V]) == "Virgile Marteau,Léo Lame" and noms(t[L]) == "Virgile Marteau,Léo Lame", "Mira partie chez les autres")
assert(dernier(t[L]):find("Mira Feuille a quitté", 1, true), dernier(t[L]))
-- Un message d'un non-membre (Mira, partie) est ignoré : elle ne peut plus retirer personne.
t[M].io.envoyer("X;id5;" .. L)
assert(noms(t[V]) == "Virgile Marteau,Léo Lame", "message d'un non-membre ignoré")
-- Une proposition qui ne vient pas de son fondateur (premier de la liste) est ignorée.
t[M].io.envoyer("P;id6;" .. V .. "," .. M)
assert(t[V].e.proposition == nil or t[V].e.proposition.id ~= "id6", "proposition au nom d'un autre : ignorée")
assert(ns.retirer(t[V].e, V, L, t[V].io), "Virgile retire Léo")
assert(t[L].e.db.compagnie == nil and dernier(t[L]):find("Virgile Marteau t'a retiré", 1, true), "Léo l'apprend : " .. dernier(t[L]))
-- Moins de deux membres : il n'y a plus de Compagnie.
assert(t[V].e.db.compagnie == nil, "seul, Virgile n'a plus de Compagnie")
assert(not ns.retirer(t[V].e, V, V, t[V].io), "on ne se retire pas soi-même (quitter)")

-- Retirer dans une Compagnie de trois : les deux autres gardent la Compagnie.
t = groupe({ V, L, M })
ns.fonder(t[V].e, V, t[V].groupe, "id7", t[V].io)
ns.repondre(t[L].e, true, t[L].io)
ns.repondre(t[M].e, true, t[M].io)
ns.retirer(t[L].e, L, M, t[L].io)
assert(noms(t[V]) == "Virgile Marteau,Léo Lame" and noms(t[L]) == "Virgile Marteau,Léo Lame", "Mira retirée chez les deux")
assert(t[M].e.db.compagnie == nil, "Mira, présente, l'apprend")

-- Un message d'une autre Compagnie (autre id) ne touche pas la mienne.
t[V].io.envoyer("Q;autre")
assert(noms(t[L]) == "Virgile Marteau,Léo Lame", "autre id : ignoré")

-- Messages mal formés : ignorés sans erreur.
for _, texte in ipairs({ "", "Z", "P", "P;", "A;;", ";;;", "P;id;", ("x"):rep(300) }) do
  ns.recevoir(t[L].e, L, t[L].groupe, V, texte, t[L].io)
end
assert(noms(t[L]) == "Virgile Marteau,Léo Lame", "messages mal formés : rien ne change")

-- Léo fonde la sienne pendant que la proposition de Virgile est encore ouverte chez lui, et Mira l'accepte ; puis Léo
-- clique « Accepter » sur celle de Virgile : il est déjà membre, sa réponse est non. Personne n'est dans deux Compagnies.
c = groupe({ V, L, M })
ns.fonder(c[V].e, V, c[V].groupe, "idV", c[V].io)
assert(ns.fonder(c[L].e, L, c[L].groupe, "idL", c[L].io), "Léo peut fonder : il n'a pas répondu à Virgile")
assert(dit(c[L], "Virgile Marteau a déjà une fondation en cours"), "Virgile, qui fonde, refuse d'office : " .. dernier(c[L]))
ns.repondre(c[M].e, true, c[M].io) -- Mira accepte celle de Léo, la plus récente
ns.cloturer(c[L].e, L, c[L].groupe, c[L].io) -- le délai de Léo, s'il attend encore une réponse
assert(noms(c[L]) == "Léo Lame,Mira Feuille" and noms(c[M]) == "Léo Lame,Mira Feuille", "Léo et Mira : " .. noms(c[L]))
ns.repondre(c[L].e, true, c[L].io) -- « Accepter » sur la proposition de Virgile, restée ouverte
assert(c[L].envoyes[#c[L].envoyes] == "R;idV;deja", "Léo, déjà membre, répond non : " .. c[L].envoyes[#c[L].envoyes])
assert(dernier(c[L]):find("Tu es déjà membre d'une Compagnie", 1, true), dernier(c[L]))
assert(dit(c[V], "Léo Lame est déjà membre d'une Compagnie"), dernier(c[V]))
ns.cloturer(c[V].e, V, c[V].groupe, c[V].io) -- le délai de Virgile : Mira ne lui a pas répondu
assert(c[V].e.db.compagnie == nil, "chez Virgile, pas de Compagnie avec Léo : " .. noms(c[V]))
assert(c[L].e.db.compagnie.id == "idL", "Léo reste dans la sienne")

-- Deux fondateurs se croisent : Virgile et Léo fondent au même moment, chacun reçoit la proposition de l'autre pendant
-- la sienne et la refuse d'office ; leurs acceptations ne peuvent pas se croiser, aucune Compagnie n'est fondée.
c = groupe({ V, L })
file = {}
ns.fonder(c[V].e, V, c[V].groupe, "idV", c[V].io)
ns.fonder(c[L].e, L, c[L].groupe, "idL", c[L].io)
livrer() -- les deux propositions arrivent
file = {}
ns.repondre(c[V].e, true, c[V].io) -- chacun accepte celle de l'autre, au même moment
ns.repondre(c[L].e, true, c[L].io)
livrer()
ns.cloturer(c[V].e, V, c[V].groupe, c[V].io)
ns.cloturer(c[L].e, L, c[L].groupe, c[L].io)
assert(c[V].e.db.compagnie == nil and c[L].e.db.compagnie == nil, "aucune Compagnie : " .. noms(c[V]) .. " / " .. noms(c[L]))
assert(dit(c[V], "Léo Lame a déjà une fondation en cours") and dit(c[L], "Virgile Marteau a déjà une fondation en cours"),
  "chacun apprend pourquoi : " .. dernier(c[V]) .. " / " .. dernier(c[L]))

-- Léo a accepté la proposition de Virgile et attend qu'elle soit fondée ; Mira propose la sienne entre-temps : Léo la
-- refuse d'office (sa réponse à Virgile tient), puis la Compagnie de Virgile est fondée avec lui, chez les deux.
c = groupe({ V, L, M })
ns.fonder(c[V].e, V, c[V].groupe, "idV", c[V].io)
ns.repondre(c[L].e, true, c[L].io)
assert(ns.fonder(c[M].e, M, c[M].groupe, "idM", c[M].io), "Mira fonde : elle n'a pas répondu à Virgile")
assert(c[L].envoyes[#c[L].envoyes] == "R;idM;occupe", "Léo refuse d'office : " .. c[L].envoyes[#c[L].envoyes])
assert(dit(c[L], "refusé d'office, tu as déjà accepté celle de Virgile Marteau"), dernier(c[L]))
assert(dit(c[M], "Léo Lame a déjà une fondation en cours"), dernier(c[M]))
ns.cloturer(c[M].e, M, c[M].groupe, c[M].io) -- le délai de Mira, si elle attend encore
ns.cloturer(c[V].e, V, c[V].groupe, c[V].io) -- le délai de Virgile : Mira ne lui a pas répondu
assert(noms(c[V]) == "Virgile Marteau,Léo Lame", "chez Virgile : " .. noms(c[V]))
assert(noms(c[L]) == "Virgile Marteau,Léo Lame", "chez Léo : " .. noms(c[L]))

-- Une fondation en cours, la sienne ou acceptée, empêche de fonder ; une proposition acceptée que son fondateur n'a pas
-- close (parti) expire au bout du délai, et Léo peut de nouveau fonder. Mira ne répond pas : Virgile attend.
c = groupe({ V, L, M })
ns.fonder(c[V].e, V, c[V].groupe, "idV", c[V].io)
ok, raison = ns.fonder(c[V].e, V, c[V].groupe, "idV2", c[V].io)
assert(not ok and raison:find("attends les réponses", 1, true), "Virgile a déjà proposé : " .. tostring(raison))
ns.repondre(c[L].e, true, c[L].io)
ok, raison = ns.fonder(c[L].e, L, c[L].groupe, "idL", c[L].io)
assert(not ok and raison:find("Tu as accepté la proposition de Virgile Marteau", 1, true), "Léo a accepté : " .. tostring(raison))
ns.expirer(c[L].e, "idV", c[L].io)
assert(dernier(c[L]):find("La Compagnie proposée par Virgile Marteau n'a pas été fondée", 1, true), dernier(c[L]))
assert(ns.fonder(c[L].e, L, c[L].groupe, "idL", c[L].io), "après l'expiration, Léo fonde")

-- Le fondateur ne devient membre d'aucune autre Compagnie pendant sa fondation, donc sa clôture dit vrai. Virgile
-- propose, Léo fonde la sienne avant de répondre : Virgile la refuse d'office (sans quoi il l'accepterait, deviendrait
-- membre de celle de Léo et dirait « Personne n'a accepté » alors que Léo a accepté la sienne).
c = groupe({ V, L })
ns.fonder(c[V].e, V, c[V].groupe, "idV", c[V].io)
ns.fonder(c[L].e, L, c[L].groupe, "idL", c[L].io)
ns.repondre(c[V].e, true, c[V].io) -- Virgile accepterait celle de Léo
assert(c[V].e.db.compagnie == nil, "pendant sa fondation, Virgile n'est membre de rien")
ns.repondre(c[L].e, true, c[L].io) -- Léo accepte celle de Virgile
assert(not dit(c[V], "Personne n'a accepté"), "Léo a accepté : " .. dernier(c[V]))
assert(noms(c[V]) == "Virgile Marteau,Léo Lame" and noms(c[L]) == "Virgile Marteau,Léo Lame", noms(c[V]) .. " / " .. noms(c[L]))

print("Compagnie : membres de la Compagnie OK")

-- Les états (Etats.lua) : encodage, réception, dernier état connu, envoi regroupé ; sans l'API du jeu, sous la même garde.
assert(loadfile("Compagnie/Etats.lua"))("Compagnie", ns)
local function pareil(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  for k, v in pairs(a) do if not pareil(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

-- Encodage puis décodage d'un état → identique : niveau, quêtes (finie, objectifs dans l'ordre, aucun texte), rendues.
-- Des questID de Forever au-delà de 90000, une quête sans objectif (« va parler à »), une escorte en 0/1.
local etat = {
  niveau = 35,
  quetes = {
    [PATTES] = { finie = false, objectifs = { { fait = 5, total = 8 } } },
    [CHASSE] = { finie = true, objectifs = { { fait = 8, total = 8 }, { fait = 4, total = 4 } } },
    [659] = { finie = false, objectifs = {} },
    [95789] = { finie = false, objectifs = { { fait = 0, total = 1 } } },
  },
  rendues = { [1453] = true, [97331] = true },
  ecartees = {}, avant = {}, renduesAvant = {},
}
local corps = ns.encoder(etat)
assert(type(corps) == "string" and not corps:find("[|\n]"), "un texte simple : " .. tostring(corps))
assert(pareil(ns.decoder(corps), etat), "encodage puis décodage : identique (" .. corps .. ")")
assert(ns.encoder(ns.decoder(corps)) == corps, "le même état s'encode toujours pareil (ordre fixe)")
assert(pareil(ns.decoder(ns.encoder({ niveau = 1, quetes = {}, rendues = {} })),
  { niveau = 1, quetes = {}, rendues = {}, ecartees = {}, avant = {}, renduesAvant = {} }), "état vide")
-- Objets à donner : pattes échangeables, Virgile en a 13 (5 de trop), Léo 5/8, Mira 6/8 : assez pour tous.
local function stock(fait, s) local q = pattes(fait); q.objectifs[1].stock = s; return q end
local function echanges(aFaire)
  local t = {}
  for _, y in ipairs(aFaire) do t[#t + 1] = y.type .. ":" .. y.membre .. ":" .. y.nombre .. ":" .. (y.a or y.de) end
  return table.concat(t, " ")
end
local trois = { { nom = "Virgile", niveau = 5, quetes = { [PATTES] = stock(8, 13) } },
  { nom = "Léo", niveau = 5, quetes = { [PATTES] = pattes(5) } }, { nom = "Mira", niveau = 5, quetes = { [PATTES] = pattes(6) } } }
c = ns.calculer(trois)
assert(echanges(c.aFaire) == "donner:Virgile:3:Léo donner:Virgile:2:Mira recevoir:Léo:3:Virgile recevoir:Mira:2:Virgile",
  "qui donne combien à qui : " .. echanges(c.aFaire))
assert(c.aFaire[1].texte == "Patte de loup" and c.aFaire[1].quete == PATTES, "l'objet et la quête")
-- Pas assez pour tous (12 : 4 de trop pour 5 qui manquent), pas échangeable (pas de stock), ou Mira sans la quête : rien.
trois[1].quetes[PATTES] = stock(8, 12)
assert(#ns.calculer(trois).aFaire == 0, "pas assez pour tous : rien")
trois[1].quetes[PATTES] = pattes(8)
assert(#ns.calculer(trois).aFaire == 0, "pas échangeable : rien")
trois[1].quetes[PATTES], trois[3].quetes = stock(8, 13), {}
assert(echanges(ns.calculer(trois).aFaire) == "", "Mira n'a pas la quête : rien à donner")
-- Mira l'a rendue : elle ne compte plus ; deux donneurs pour un seul receveur.
trois[3].rendues = { [PATTES] = true }
trois[2].quetes[PATTES] = pattes(2)
trois[3].quetes = { [PATTES] = stock(8, 11) }
trois[3].rendues = nil
c = ns.calculer(trois)
assert(echanges(c.aFaire) == "donner:Mira:1:Léo donner:Virgile:5:Léo recevoir:Léo:5:Virgile recevoir:Léo:1:Mira",
  "deux donneurs : " .. echanges(c.aFaire))
-- Un objet échangeable : le total du groupe sur le total à faire pour le groupe (Mira 11, Virgile 13, Léo 2 : 24/24).
assert(c.quetes[PATTES].objectifs[1].fait == 2 and c.quetes[PATTES].objectifs[1].total == 8, "Léo sans stock : le moins avancé")
trois[2].quetes[PATTES] = stock(2, 2)
local o = ns.calculer(trois).quetes[PATTES].objectifs[1]
assert(o.fait == 24 and o.total == 24, "total du groupe : " .. o.fait .. "/" .. o.total)
trois[1].quetes[PATTES], trois[2].quetes[PATTES] = stock(3, 3), stock(0, 0)
o = ns.calculer(trois).quetes[PATTES].objectifs[1]
assert(o.fait == 14 and o.total == 24, "total du groupe, pas fini : " .. o.fait .. "/" .. o.total)
trois[3].rendues, trois[3].quetes = { [PATTES] = true }, {}
o = ns.calculer(trois).quetes[PATTES].objectifs[1]
assert(o.fait == 3 and o.total == 16, "Mira l'a rendue : elle ne compte plus : " .. o.fait .. "/" .. o.total)
trois[3].rendues = nil
o = ns.calculer(trois).quetes[PATTES].objectifs[1]
assert(o.fait == 0 and o.total == 8, "Mira sans la quête : stock inconnu, le moins avancé")
-- Le stock part dès que l'objet s'échange (0 compris) ; reçu tel quel ; moins que le compte de l'objectif, rejeté.
local recuS = ns.decoder(ns.encoder({ niveau = 5, quetes = { [7] = stock(8, 13), [8] = stock(5, 5), [9] = pattes(5) }, rendues = {} }))
assert(recuS.quetes[7].objectifs[1].stock == 13 and recuS.quetes[8].objectifs[1].stock == 5
  and recuS.quetes[9].objectifs[1].stock == nil, "le stock part tel quel")
assert(ns.decoder("5#7:0:5/8/4#############") == nil and ns.decoder("5#7:0:0/8/0#############").quetes[7].objectifs[1].stock == 0
  and ns.decoder("5#7:1:8/8/9#############").quetes[7].objectifs[1].stock == 9, "stock : au moins le compte")

-- Le texte des objectifs n'est jamais envoyé (code de grammaire du jeu « |4… ; ») : seulement les nombres.
local avecTexte = { niveau = 12, quetes = { [7] = { finie = false, objectifs = {
  { texte = "Raptor flagellant : 2/10 |4personnage tué:personnages tués;", fait = 2, total = 10 } } } }, rendues = {} }
assert(not ns.encoder(avecTexte):find("Raptor", 1, true), "le texte n'est pas envoyé")
assert(ns.decoder(ns.encoder(avecTexte)).quetes[7].objectifs[1].fait == 2, "les nombres le sont")
assert(ns.libelle("Raptor flagellant : \1 |4personnage tué:personnages tués;") == "Raptor flagellant"
  and ns.libelle("Kobold Vermin slain: 3/10") == "Kobold Vermin slain" and ns.libelle("Patte de loup : 5/8") == "Patte de loup"
  and ns.libelle(nil) == nil and ns.libelle(" 3/8 ") == nil, "le nom d'un objectif (les plaques)")

-- Les champs ajoutés après le 10e, vides : APRES_ZONE, ceux après la zone de la Compagnie (#27 : les prérequis
-- manquants) ; FIN, tous (#24 : la zone, puis APRES_ZONE). Un état à 10 champs + FIN est complet.
local APRES_ZONE = "####" -- #27 : les prérequis manquants ; #23 : la liste des membres ; #34 : les rendues de la zone ; #6 : les origines
local FIN = "#" .. APRES_ZONE
-- Lecture stricte : un champ mal formé, et tout l'état est rejeté (jamais exécuté ni interprété). Un seul format (bêta) :
-- un état à quatre champs (celui de #13, sans abandons) est rejeté aussi.
for _, mauvais in ipairs({ "", "x", "35", "35#", "35##", "35#1:0#", "35#1:0##", "0####", "35#a:0####",
  "35#1:2####", "35#1:0:9/8####", "35#1:0:1/2:####", "35#1:0#####", "35##1,,2##", "999####", "35#1:0;1:1####",
  "35#-1:0####", "35#1:0:1/2/3####", "35#1:0##" .. ("1,"):rep(300) .. "1##", "35#1:0:" .. ("1/2:"):rep(30) .. "1/2####",
  "os.exit()", "35#1:0##;os.exit()##", "35#1:0###x", "35#1:0###1,,2", "35#1:0###-1", "35#1:0###0",
  "35#1:0###" .. ("1,"):rep(300) .. "1" }) do
  assert(ns.decoder(mauvais) == nil, "rejeté : " .. mauvais:sub(1, 40))
  assert(ns.decoder(mauvais .. "#####" .. FIN) == nil, "rejeté avec le foyer et les quêtes d'avant : " .. mauvais:sub(1, 40))
end
-- Ma race et ma classe (#7 : la quête personnelle) partent avec mon niveau, « niveau:race:classe » ; une quête marquée
-- personnelle à la main porte « p » après finie : encodage puis décodage → identique.
local avecPerso = { niveau = 12, race = 95, classe = 2, quetes = { [PATTES] = { finie = true, personnelle = true, objectifs = {} },
  [CHASSE] = { finie = false, objectifs = {} } }, rendues = {}, ecartees = {}, avant = {}, renduesAvant = {} }
corps = ns.encoder(avecPerso)
assert(corps:find("^12:95:2#1001:1p;1002:0#"), "race et classe, quête marquée : " .. corps)
assert(pareil(ns.decoder(corps), avecPerso), "avec race, classe et quête personnelle : identique (" .. corps .. ")")
for _, mauvais in ipairs({ "12:95#", "12:95:#", "12:x:2#", "12:95:2:1#", "12::2#", "12#1:p#", "12#1:2p#", "12#1:0pp#", "12#1:P#" }) do
  assert(ns.decoder(mauvais .. "########" .. FIN) == nil, "rejeté : " .. mauvais)
end
-- Un état à cinq champs (celui de #5, sans foyer) est rejeté (#9) ; à huit (celui de #9, sans quêtes d'avant) aussi (#20).
assert(ns.decoder("35#1:0####") == nil and ns.decoder("35#1:0######") == nil and ns.decoder("35#1:0########") == nil
  and ns.decoder("35#1:0#########") == nil and ns.decoder("35#1:0##########") == nil and ns.decoder("35#1:0########" .. FIN)
  and ns.decoder("35#1:0############") == nil,
  "cinq, huit, dix (avant #24), onze (avant #27), douze (avant #23) et quatorze champs (avant #34) : rejeté ; le format en cours : lu")

-- Les quêtes d'avant et les quêtes rendues avant l'entrée (#20) partent avec l'état : encodage puis décodage → identique.
local avecAvant = { niveau = 14, quetes = { [PATTES] = { finie = false, objectifs = {} }, [2002] = { finie = true, objectifs = {} } },
  avant = { [2002] = true }, rendues = { [1453] = true }, renduesAvant = { [783] = true, [95790] = true }, ecartees = {} }
corps = ns.encoder(avecAvant)
assert(corps:find("#2002#783,95790" .. FIN .. "$"), "quêtes d'avant, puis rendues avant l'entrée, triées : " .. corps)
assert(pareil(ns.decoder(corps), avecAvant), "avec quêtes d'avant : identique (" .. corps .. ")")
-- Une quête d'avant qui n'est plus dans le journal ne part pas ; reçue, elle fait rejeter l'état.
assert(ns.encoder({ niveau = 2, quetes = {}, avant = { [9] = true } }) == "2#########" .. FIN, "quête d'avant hors du journal : ne part pas")
for _, mauvais in ipairs({ "35#1:0#######2#", "35#1:0#######x#", "35#1:0#######1,1#", "35#1:0########0", "35#1:0########1,,2" }) do
  assert(ns.decoder(mauvais .. FIN) == nil, "rejeté : " .. mauvais)
end

-- Les questID sont bornés à 2147483647 (un entier 32 bits signé, comme le jeu).
assert(ns.decoder("35#2147483647:0#2147483647##2147483647:1:2147483647:V####2147483647#2147483647" .. FIN).quetes[2147483647],
  "2147483647 : accepté")
assert(ns.decoder("35#2147483648:0########" .. FIN) == nil and ns.decoder("35##2147483648#######" .. FIN) == nil and
  ns.decoder("35####2147483648:1:1:V#####" .. FIN) == nil and ns.decoder("35####1:1:2147483648:V#####" .. FIN) == nil and
  ns.decoder("35#########2147483648" .. FIN) == nil, "au-delà : rejeté")

-- Les quêtes écartées (#21) partent avec l'état, datées, avec qui a décidé, remises comprises : encodage puis décodage
-- → identique.
local avecEcartees = { niveau = 12, quetes = { [PATTES] = { finie = false, objectifs = {} } }, rendues = { [1453] = true },
  ecartees = { [783] = { ecartee = true, date = 1764000000, par = "Léo" }, [95790] = { ecartee = false, date = 1764000100, par = "Virgile" } },
  avant = {}, renduesAvant = {} }
corps = ns.encoder(avecEcartees)
assert(corps:find("#783:1:1764000000:Léo;95790:0:1764000100:Virgile#####" .. FIN .. "$"), "écartées triées, puis le foyer (vide) : " .. corps)
assert(pareil(ns.decoder(corps), avecEcartees), "avec écartées : identique (" .. corps .. ")")
-- Mal formées : tout l'état est rejeté (statut 0 ou 1, date entière positive, « par » comme une zone, une quête une fois).
for _, f in ipairs({ "783", "783:1:1", "783:2:1:Léo", "783:1:0:Léo", "783:1:x:Léo", "783:1:1:", "783:1:1:a|b", "x:1:1:Léo",
  "783:1:1:Léo;783:0:2:Léo", "783:1:1:Léo;", "783:1:1:Léo:1" }) do
  assert(ns.decoder("12#####" .. f .. "#####" .. FIN) == nil, "écartée rejetée : " .. f)
end
-- Au-delà de 20 décisions (une décision emporte toute la chaîne, #27), seules les 20 plus récentes partent (l'état reste
-- lisible).
local beaucoup = { niveau = 5, quetes = {}, ecartees = {} }
for i = 1, 30 do beaucoup.ecartees[i] = { ecartee = true, date = 1000 + i, par = "Léo" } end
lu = assert(ns.decoder(ns.encoder(beaucoup)), "30 décisions : lisible")
local function compter(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
assert(compter(lu.ecartees) == 20 and lu.ecartees[30] and lu.ecartees[11] and not lu.ecartees[10],
  "les 20 plus récentes : " .. compter(lu.ecartees))
-- Une remise récente ne pousse pas dehors une écartée plus ancienne : les écartées partent d'abord.
for i = 1, 20 do beaucoup.ecartees[i] = { ecartee = true, date = 1000 + i, par = "Léo" } end
for i = 21, 30 do beaucoup.ecartees[i] = nil end
beaucoup.ecartees[99] = { ecartee = false, date = 5000, par = "Mira" }
lu = ns.decoder(ns.encoder(beaucoup))
assert(compter(lu.ecartees) == 20 and lu.ecartees[1] and not lu.ecartees[99], "les 20 écartées partent, pas la remise")
-- Plus de 20 décisions reçues : l'état est rejeté.
local vingt1 = {}
for i = 1, 21 do vingt1[i] = i .. ":1:1:Léo" end
assert(ns.decoder("5####" .. table.concat(vingt1, ";") .. "#####" .. FIN) == nil, "21 décisions reçues : rejeté")
-- Une décision datée de plus d'un jour après mon heure serveur fait rejeter l'état (elle l'emporterait pour toujours).
local futur = "5####783:1:" .. (100000 + 86401) .. ":Léo#####" .. FIN
assert(ns.decoder(futur, 100000) == nil and ns.decoder("5####783:1:" .. (100000 + 86400) .. ":Léo#####" .. FIN, 100000),
  "plus d'un jour dans le futur : rejeté ; un jour : lu")

-- Le pire cas réaliste tient dans MAX_MORCEAUX (10) : un journal plein (25 quêtes de 1 à 3 objectifs, 8 zones), 20
-- décisions (dont 6 remises) signées de prénoms longs, 10 quêtes d'avant, 10 quêtes des autres rendues depuis l'entrée
-- et 10 avant, la zone de la Compagnie (#24), 8 prérequis manquants (#27), 5 membres (#23), race et classe, toutes les
-- quêtes marquées personnelles (#7) ; l'id de la Compagnie est celui de Compagnie.lua (GUID et heure serveur). Le texte
-- des objectifs ne part pas.
local ZONES = { "Contreforts de Hautebrande", "Marche de l'Ouest", "Forêt d'Elwynn", "Les Carmines", "Bois de la Pénombre",
  "Loch Modan", "Les Paluns", "Vallée de Strangleronce" }
local OBJECTIFS = { { texte = "Raptor flagellant : 12/15 |4personnage tué:personnages tués;", fait = 12, total = 15 },
  { texte = "Croc de raptor : 9/10", fait = 9, total = 10 }, { texte = "Sauvetage de Kernobee", fait = 0, total = 1 } }
local plein = { niveau = 60, race = 95, classe = 11, quetes = {}, rendues = {}, renduesAvant = {}, avant = {}, ecartees = {},
  auberge = "Comté-de-l'Or", liaison = 1764000000, finRecharge = 1764003600 }
for i = 1, 25 do
  local o = {}
  for k = 1, i % 3 + 1 do o[k] = OBJECTIFS[k] end
  plein.quetes[90000 + i] = { finie = false, zone = ZONES[i % 8 + 1], objectifs = o, personnelle = true } -- #7 : toutes marquées
end
for i = 1, 10 do plein.avant[90000 + i] = true; plein.rendues[91000 + i] = true; plein.renduesAvant[92000 + i] = true end
for i = 1, 20 do plein.ecartees[93000 + i] = { ecartee = i % 3 > 0, date = 1764000000 + i, par = i % 2 == 0 and "Éléonorette" or "Virgile" } end
plein.zoneCompagnie = { zone = 16941, date = 1764000000, par = "Éléonorette" } -- #24
plein.prerequis = { zone = 16941, manquants = {} } -- #27
for i = 1, 8 do plein.prerequis.manquants[i] = { quete = 95000 + i, prerequis = 96000 + i } end
plein.renduesZone = { zone = 16941, quetes = {} } -- #34 : la borne, 100 quêtes rendues de la zone
for i = 1, 100 do plein.renduesZone.quetes[97000 + i] = true end
plein.liste = { date = 1764000000, membres = {} } -- #23 : cinq membres aux noms longs
for i = 1, 5 do plein.liste.membres[i] = { guid = "Player-4395-0A1B2C3" .. i, nom = "Éléonorette Bourselourdé" } end
local idC = "Player-4395-0A1B2C3D-1764000000"
local parts = ns.morceaux(idC, ns.encoder(plein), 99)
assert(#parts >= 1 and #parts <= 14, "le pire cas réaliste tient : " .. #parts .. " morceaux, " .. #ns.encoder(plein) .. " octets")
-- Les origines (#6) remplissent la place qui reste : toutes les quêtes non partageables, relevées avec un PNJ au nom
-- long, le pire cas tient toujours, avec les premières origines.
local avecToutes = {}
for k, v in pairs(plein) do avecToutes[k] = v end
avecToutes.quetes = {}
for id, q in pairs(plein.quetes) do
  avecToutes.quetes[id] = { finie = q.finie, zone = q.zone, objectifs = q.objectifs, partageable = false,
    origine = { nom = "Grand Géomètre Fizzledowser", carte = 1429, x = 42, y = 65 } }
end
local n = #ns.morceaux(idC, ns.encoder(avecToutes), 99)
local recu = assert(ns.decoder(ns.encoder(avecToutes)), "le pire cas avec origines se décode")
assert(n >= 1 and n <= 14 and recu.quetes[90001].origine, "le pire cas avec origines tient : " .. n .. " morceaux, la 1re origine part")
print(("Compagnie : pire cas réaliste, %d octets, %d morceaux sur 14"):format(#ns.encoder(plein), #parts))

-- Écarter, Remettre (#21) : une décision datée de la Compagnie. Les décisions reçues avec un état : la plus récente
-- l'emporte, quête par quête ; fusionner rend celles qui ont changé (pour le message dans le chat).
local dbE = {}
ns.decider(dbE, PATTES, true, "Virgile", 100)
assert(dbE.ecartees[PATTES].ecartee and dbE.ecartees[PATTES].par == "Virgile", "écartée par Virgile")
local changees = ns.fusionner(dbE, { [PATTES] = { ecartee = false, date = 90, par = "Léo" } })
assert(#changees == 0 and dbE.ecartees[PATTES].ecartee, "une remise plus ancienne : ignorée")
changees = ns.fusionner(dbE, { [PATTES] = { ecartee = false, date = 120, par = "Léo" }, [CHASSE] = { ecartee = true, date = 50, par = "Mira" } })
assert(#changees == 2 and changees[1].quete == PATTES and changees[2].quete == CHASSE, "deux décisions nouvelles, triées")
assert(not dbE.ecartees[PATTES].ecartee and dbE.ecartees[PATTES].par == "Léo", "remise par Léo, la plus récente : elle l'emporte")
assert(#ns.fusionner(dbE, { [PATTES] = { ecartee = false, date = 120, par = "Léo" } }) == 0, "la même décision : rien de nouveau")
ns.decider(dbE, PATTES, true, "Virgile", 130)
assert(dbE.ecartees[PATTES].ecartee, "écartée de nouveau")
-- À la même seconde, écarter l'emporte sur remettre, dans les deux sens.
assert(#ns.fusionner(dbE, { [PATTES] = { ecartee = false, date = 130, par = "Léo" } }) == 0 and dbE.ecartees[PATTES].ecartee,
  "même seconde : la remise ne l'emporte pas sur l'écartée")
ns.decider(dbE, PATTES, false, "Virgile", 140)
assert(#ns.fusionner(dbE, { [PATTES] = { ecartee = true, date = 140, par = "Léo" } }) == 1 and dbE.ecartees[PATTES].ecartee,
  "même seconde : l'écartée l'emporte sur la remise")
-- Une remise reçue n'est annoncée que si je connaissais la quête écartée ; gardée quand même.
changees = ns.fusionner(dbE, { [KOBOLDS] = { ecartee = false, date = 150, par = "Léo" } })
assert(#changees == 0 and dbE.ecartees[KOBOLDS] and not dbE.ecartees[KOBOLDS].ecartee, "remise d'une quête inconnue : pas annoncée")
changees = ns.fusionner(dbE, { [PATTES] = { ecartee = false, date = 160, par = "Léo" } })
assert(#changees == 1 and changees[1].ecartee == false, "remise d'une quête que je savais écartée : annoncée")
-- Les remises de plus de 7 jours sont oubliées ; une écartée reste, si vieille soit-elle.
local dbP = { ecartees = { [1] = { ecartee = false, date = 1000, par = "Léo" }, [2] = { ecartee = false, date = 1000 + 86400, par = "Léo" },
  [3] = { ecartee = true, date = 1, par = "Léo" } } }
ns.purger(dbP, 1001 + 7 * 86400)
assert(not dbP.ecartees[1] and dbP.ecartees[2] and dbP.ecartees[3], "remise de plus de 7 jours oubliée, écartée gardée")
-- La zone de la Compagnie (#24) part avec l'état, datée, avec qui l'a choisie : encodage puis décodage → identique.
local avecZone = { niveau = 12, quetes = {}, rendues = {}, ecartees = {}, avant = {}, renduesAvant = {},
  zoneCompagnie = { zone = 148, date = 1764000000, par = "Léo" } }
corps = ns.encoder(avecZone)
assert(corps:find("#148:1764000000:Léo" .. APRES_ZONE .. "$"), "la zone, en 11e champ : " .. corps)
assert(pareil(ns.decoder(corps), avecZone), "avec la zone : identique (" .. corps .. ")")
for _, f in ipairs({ "148", "148:1", "x:1:Léo", "0:1:Léo", "148:0:Léo", "148:1:", "148:1:a|b", "148:1:Léo:2", "-148:1:Léo" }) do
  assert(ns.decoder("12#########" .. f .. APRES_ZONE) == nil, "zone rejetée : " .. f)
end
assert(ns.decoder("12#########148:" .. (100000 + 86401) .. ":Léo" .. APRES_ZONE, 100000) == nil, "choisie plus d'un jour dans le futur : rejeté")
-- Les prérequis manquants (#27) partent avec l'état, avec la zone qu'ils couvrent : encodage puis décodage → identique.
local avecPrerequis = { niveau = 12, quetes = {}, rendues = {}, ecartees = {}, avant = {}, renduesAvant = {},
  prerequis = { zone = 148, manquants = { { quete = 952, prerequis = 940 }, { quete = 2050, prerequis = 2052 } } } }
corps = ns.encoder(avecPrerequis)
assert(corps:find("##148=952:940,2050:2052###$"), "les prérequis, en 12e champ : " .. corps)
assert(pareil(ns.decoder(corps), avecPrerequis), "avec les prérequis : identique (" .. corps .. ")")
avecPrerequis.prerequis.manquants = {}
corps = ns.encoder(avecPrerequis)
assert(corps:find("##148###$") and pareil(ns.decoder(corps), avecPrerequis), "rien ne manque, la zone couverte : " .. corps)
for _, f in ipairs({ "x", "0", "148=", "148=952", "148=952:", "148=a:940", "148=952:940,", "148:952:940", "=952:940",
  "148=" .. ("1:2,"):rep(8) .. "1:2" }) do
  assert(ns.decoder("12##########" .. f .. "###") == nil, "prérequis rejetés : " .. f)
end
-- Mes quêtes rendues de la zone de la Compagnie (#34) partent avec l'état, avec la zone qu'elles couvrent, en 14e champ
-- (avant les origines) : encodage puis décodage → identique.
local avecRendues = { niveau = 12, quetes = {}, rendues = {}, ecartees = {}, avant = {}, renduesAvant = {},
  renduesZone = { zone = 12, quetes = { [100] = true, [101] = true, [940] = true } } }
corps = ns.encoder(avecRendues)
assert(corps:find("#12=100,101,940#$"), "les rendues de la zone, en 14e champ : " .. corps)
assert(pareil(ns.decoder(corps), avecRendues), "avec les rendues de la zone : identique (" .. corps .. ")")
avecRendues.renduesZone.quetes = {}
corps = ns.encoder(avecRendues)
assert(corps:find("#12#$") and pareil(ns.decoder(corps), avecRendues), "rien de rendu, la zone couverte : " .. corps)
local cent = {}
for i = 1, 101 do cent[i] = 1000 + i end
for _, f in ipairs({ "x", "0", "12=", "12=a", "12=1,,2", "12=1,", "12:1", "=1", "12=1,1", "12=" .. table.concat(cent, ",") }) do
  assert(ns.decoder("12#############" .. f .. "#") == nil, "rendues de la zone rejetées : " .. f:sub(1, 20))
end
table.remove(cent)
assert(ns.decoder("12#############12=" .. table.concat(cent, ",") .. "#"), "100 : la borne, acceptée")
-- Au-delà de la borne, les 100 premières partent (l'état reste lisible).
for i = 1, 150 do avecRendues.renduesZone.quetes[2000 + i] = true end
lu = assert(ns.decoder(ns.encoder(avecRendues)), "150 rendues : lisible")
assert(compter(lu.renduesZone.quetes) == 100 and lu.renduesZone.quetes[2001] and not lu.renduesZone.quetes[2150], "les 100 premières")
-- Au-delà de MAX_PREREQUIS (8), les premiers seuls partent.
for i = 1, 12 do avecPrerequis.prerequis.manquants[i] = { quete = 3000 + i, prerequis = 4000 + i } end
assert(#ns.decoder(ns.encoder(avecPrerequis)).prerequis.manquants == 8, "les 8 premiers partent")
-- Deux choix : le plus récent l'emporte (à la même seconde, le plus grand areaID : tous retiennent la même) ; rend true
-- quand elle change (le chat le dit).
local dbZ = {}
assert(ns.fusionnerZone(dbZ, { zone = 40, date = 100, par = "Virgile" }) and dbZ.zoneCompagnie.zone == 40, "un premier choix")
assert(not ns.fusionnerZone(dbZ, { zone = 148, date = 90, par = "Léo" }) and dbZ.zoneCompagnie.zone == 40, "un choix plus ancien : ignoré")
assert(ns.fusionnerZone(dbZ, { zone = 148, date = 120, par = "Léo" }) and dbZ.zoneCompagnie.par == "Léo", "le plus récent l'emporte")
assert(not ns.fusionnerZone(dbZ, { zone = 148, date = 120, par = "Léo" }) and not ns.fusionnerZone(dbZ, nil), "le même : rien de nouveau")
assert(not ns.fusionnerZone(dbZ, { zone = 40, date = 120, par = "Mira" }) and ns.fusionnerZone(dbZ, { zone = 1519, date = 120, par = "Mira" }),
  "même seconde : le plus grand areaID")

-- Le foyer (#9) part avec l'état : auberge, heure de la liaison, heure où la pierre est prête → identique.
local avecFoyer = { niveau = 12, quetes = {}, rendues = {}, ecartees = {}, avant = {}, renduesAvant = {}, auberge = "Comté-de-l'Or", liaison = 1763990000,
  finRecharge = 1764002400 }
corps = ns.encoder(avecFoyer)
assert(corps == "12#####Comté-de-l'Or#1763990000#1764002400##" .. FIN, corps)
assert(pareil(ns.decoder(corps), avecFoyer), "avec foyer : identique")
-- Mal formé : tout l'état est rejeté (auberge comme une zone ; heures entières, positives, 32 bits).
for _, f in ipairs({ "a|b#1#1", ("x"):rep(49) .. "#1#1", "a;b##", "Or#x#", "Or#0#", "Or##-1", "Or##2147483648", "Or#1.5#" }) do
  assert(ns.decoder("12#####" .. f .. "##" .. FIN) == nil, "foyer rejeté : " .. f:sub(1, 20))
end
-- « partageable » (lu dans mon journal) ne part pas ; « non partageable » si (#6, ci-dessous).
assert(ns.encoder({ niveau = 2, quetes = { [7] = { finie = false, objectifs = {}, partageable = true } } }) == "2#7:0########" .. FIN,
  "partageable ne part pas")

-- Quête à prendre soi-même (#6) : « non partageable » part avec la quête (« n », après « p »), et en 14e champ l'origine que j'ai relevée : le PNJ et ma position quand je l'ai acceptée, ou ma position
-- quand j'ai ramassé l'objet qui la lance (« id=PNJ@carte:x:y », x et y en % entiers) → identique.
local avecOrigines = { niveau = 12, rendues = {}, ecartees = {}, avant = {}, renduesAvant = {}, quetes = {
  [7] = { finie = false, objectifs = {}, partageable = false, origine = { nom = "Maréchal Dughan", carte = 1429, x = 42, y = 65 } },
  [8] = { finie = true, objectifs = {}, partageable = false, origine = { carte = 1436, x = 0, y = 100 } }, -- un objet ramassé
  [9] = { finie = false, objectifs = {}, partageable = false, origine = { nom = "Gryan Stoutmantle" } }, -- sans carte (instance)
  [10] = { finie = false, objectifs = {}, partageable = false }, -- rien de relevé
} }
corps = ns.encoder(avecOrigines)
assert(corps:find("^12#7:0n;8:1n;9:0n;10:0n#"), "non partageable : n — " .. corps)
assert(corps:find("#7=Maréchal Dughan@1429:42:65;8@1436:0:100;9=Gryan Stoutmantle$"), "les origines, en 14e champ : " .. corps)
assert(pareil(ns.decoder(corps), avecOrigines), "avec les origines : identique (" .. corps .. ")")
-- Une position hors carte (relevée au bord) ne part pas : le reste de l'état, et le PNJ, restent lisibles.
corps = ns.encoder({ niveau = 2, quetes = { [7] = { finie = false, objectifs = {}, partageable = false,
  origine = { nom = "Dughan", carte = 1429, x = 101, y = -1 } }, [8] = { finie = false, objectifs = {}, partageable = false,
  origine = { carte = 1429, x = 4.5, y = 5 } } } })
assert(corps:find("#7=Dughan$") and ns.decoder(corps), "position hors carte : pas envoyée — " .. corps)
-- L'origine d'une quête partageable ne part pas.
assert(ns.encoder({ niveau = 2, quetes = { [7] = { finie = false, objectifs = {}, partageable = true, origine = { nom = "Dughan" } } } })
  == "2#7:0########" .. FIN, "partageable : pas d'origine")
-- Mal formé : tout l'état est rejeté (une origine d'une quête absente de l'état, partageable, ou deux fois ; ni PNJ ni
-- position ; un nom comme une zone, sans « @ » ; une position entière, x et y de 0 à 100).
for _, f in ipairs({ "8=Dughan", "6=Dughan", "7=Dughan;7=Dughan", "7", "7=", "7@", "7=@1:2:3", "7Dughan", "7=a|b", "7=a@b@1:2:3",
  "7@1:2", "7@1:2:3:4", "7@0:2:3", "7@1:101:3", "7@1:2:-3", "7@x:2:3", "7=" .. ("x"):rep(49), "7=Dughan;" }) do
  assert(ns.decoder("12#6:0;7:0n#############" .. f) == nil, "origine rejetée : " .. f:sub(1, 20))
end
assert(ns.decoder("12#6:0;7:0n#############7=Dughan@1:2:3"), "bien formée : acceptée")
for _, q in ipairs({ "7:0x", "7:0nn", "7:0np", "7:n", "7:2" }) do assert(ns.decoder("12#" .. q .. "########" .. FIN) == nil, "drapeau rejeté : " .. q) end

-- La zone de chaque quête (#13 : l'en-tête de zone de mon journal) part avec l'état : encodage puis décodage → identique.
local avecZones = { niveau = 35, rendues = { [1453] = true }, ecartees = {}, avant = {}, renduesAvant = {}, quetes = {
  [PATTES] = { finie = false, objectifs = { { fait = 5, total = 8 } }, zone = "Forêt d'Elwynn" },
  [CHASSE] = { finie = true, objectifs = {}, zone = "Marche de l'Ouest" },
  [95789] = { finie = false, objectifs = { { fait = 0, total = 1 } }, zone = "Forêt d'Elwynn" },
  [659] = { finie = false, objectifs = {} }, -- sans zone
} }
corps = ns.encoder(avecZones)
assert(pareil(ns.decoder(corps), avecZones), "avec zones : identique (" .. corps .. ")")
assert(ns.encoder(ns.decoder(corps)) == corps, "avec zones : toujours encodé pareil")
-- Un état sans zone est accepté (champ des zones vide).
local sansZone = assert(ns.decoder("35#1001:0:5/8;659:0#1453#######" .. FIN), "sans zone : accepté")
assert(sansZone.quetes[1001].zone == nil and sansZone.quetes[1001].objectifs[1].fait == 5, "…ses quêtes sans zone")
-- Une zone mal formée fait rejeter tout l'état : vide, trop longue, caractère de contrôle, « | » (codes du chat), un
-- séparateur du format ; une zone sans quête, une quête absente de l'état ou rangée deux fois, une zone répétée.
for _, z in ipairs({ "", ("x"):rep(49), "a|cffff0000b", "a\nb", "a\1b", "a\0b", "a\127b", "a#b", "a;b", "a:b", "a,b",
  "a/b", "a=b" }) do
  assert(ns.decoder("35#1001:0#1453#" .. z .. "=1001######" .. FIN) == nil, "zone rejetée : " .. z:sub(1, 20))
end
assert(ns.decoder("35#1001:0##" .. ("é"):rep(24) .. "=1001######" .. FIN), "48 octets : acceptée")
for _, mauvais in ipairs({ "35#1001:0##Elwynn#", "35#1001:0##Elwynn=#", "35#1001:0##Elwynn=x#", "35#1001:0##Elwynn=2002#",
  "35#1001:0##A=1001;B=1001#", "35#1001:0;1002:0##A=1001;A=1002#", "35#1001:0##A=1001,1001#", "35#1001:0##A=1001;#",
  "35#1001:0##A=1001##" }) do
  assert(ns.decoder(mauvais .. "#####" .. FIN) == nil, "rejeté : " .. mauvais)
end
-- Mon journal peut avoir un en-tête que le format refuse : il ne part pas (la quête part sans zone), l'état reste lisible.
local bizarre = { niveau = 5, rendues = {}, quetes = { [1] = { finie = false, objectifs = {}, zone = "a|b" },
  [2] = { finie = false, objectifs = {}, zone = ("x"):rep(60) }, [3] = { finie = false, objectifs = {}, zone = "Dun Morogh" } } }
local lu = assert(ns.decoder(ns.encoder(bizarre)), "un en-tête refusé ne rend pas mon état illisible")
assert(lu.quetes[1].zone == nil and lu.quetes[2].zone == nil and lu.quetes[3].zone == "Dun Morogh", "seul l'en-tête valable part")
-- La zone d'une quête de la Compagnie : prise chez qui l'a (une quête que seul Léo a : sa zone vient de son état).
c = ns.calculer({
  { nom = "Virgile", niveau = 10, quetes = { [PATTES] = { finie = false, objectifs = {} } } },
  { nom = "Léo", niveau = 10, quetes = { [PATTES] = { finie = false, objectifs = {}, zone = "Forêt d'Elwynn" },
    [CHASSE] = { finie = false, objectifs = {}, zone = "Marche de l'Ouest" } } },
})
assert(c.quetes[PATTES].zone == "Forêt d'Elwynn" and c.quetes[CHASSE].zone == "Marche de l'Ouest", "zone prise chez qui l'a")

-- Un état part en morceaux de messages d'add-on bornés (255 octets) et se recompose chez un membre.
local V2, L2, Z2 = "Player-1-0000000V", "Player-1-0000000L", "Player-1-0000000Z"
local gros = { niveau = 40, quetes = {}, rendues = {}, ecartees = {}, avant = {}, renduesAvant = {} }
for i = 1, 35 do gros.quetes[90000 + i] = { finie = false, objectifs = { { fait = 3, total = 10 }, { fait = 1, total = 12 } } } end
for i = 1, 60 do gros.rendues[100000 + i] = true end
local morceaux = ns.morceaux("id-1234567890", ns.encoder(gros), 7)
assert(#morceaux > 1, "un gros état part en plusieurs messages : " .. #morceaux)
for _, m in ipairs(morceaux) do assert(#m <= 255, "message de " .. #m .. " octets") end

local function compagnieDe(moi)
  return { db = { compagnie = { id = "id-1234567890", membres = { { guid = V2, nom = "Virgile Marteau" },
    { guid = L2, nom = "Léo Lame" } } } }, moi = moi }
end
local recus = {}
local function ioRecu() return { maj = function() recus.maj = (recus.maj or 0) + 1 end,
  annoncer = function(t) recus.annonces = t end, zone = function(z) recus.zone = z end, liste = function(l) recus.liste = l end,
  demande = function(de) recus.demande = de end, maintenant = function() return recus.t or 1000 end,
  heure = function() return 1764000000 end,
  envoyerVersion = function() recus.versionsEnvoyees = (recus.versionsEnvoyees or 0) + 1 end,
  programmer = function(_, fn) recus.plusTard = fn end,
  incompatible = function(de, sa) recus.incompatible = { de = de, sa = sa or false } end } end
local chezV = compagnieDe(V2)
for _, m in ipairs(morceaux) do ns.recevoirEtat(chezV, L2, m, ioRecu()) end
assert(pareil(chezV.db.etats[L2], gros), "l'état de Léo est recomposé et gardé comme dernier état connu")
assert(recus.maj and recus.maj > 0, "le suivi est redessiné")
-- Ses décisions sur les quêtes écartées (#21) rejoignent celles de la Compagnie, et celles qui changent sont annoncées.
recus.annonces = nil
for _, m in ipairs(ns.morceaux("id-1234567890", ns.encoder(avecEcartees), 9)) do ns.recevoirEtat(chezV, L2, m, ioRecu()) end
assert(chezV.db.ecartees[783].ecartee and chezV.db.ecartees[783].par == "Léo", "la décision de Léo est celle de la Compagnie")
assert(recus.annonces and #recus.annonces == 1 and recus.annonces[1].quete == 783, "l'écartée annoncée, pas la remise d'une quête inconnue")
recus.annonces = nil
for _, m in ipairs(ns.morceaux("id-1234567890", ns.encoder(avecEcartees), 10)) do ns.recevoirEtat(chezV, L2, m, ioRecu()) end
assert(recus.annonces == nil, "reçues de nouveau : rien à annoncer")
-- La zone qu'il a choisie (#24) devient celle de la Compagnie, annoncée une fois ; un absent l'apprend ainsi à son retour.
for _, m in ipairs(ns.morceaux("id-1234567890", ns.encoder(avecZone), 11)) do ns.recevoirEtat(chezV, L2, m, ioRecu()) end
assert(chezV.db.zoneCompagnie.zone == 148 and recus.zone and recus.zone.par == "Léo", "la zone de Léo, annoncée")
recus.zone = nil
for _, m in ipairs(ns.morceaux("id-1234567890", ns.encoder(avecZone), 12)) do ns.recevoirEtat(chezV, L2, m, ioRecu()) end
assert(recus.zone == nil, "reçue de nouveau : rien à annoncer")

-- Un message d'un non-membre ne change rien (ni état, ni demande), pas plus qu'un état d'une autre Compagnie.
chezV = compagnieDe(V2)
for _, m in ipairs(ns.morceaux("id-1234567890", ns.encoder(etat), 1)) do ns.recevoirEtat(chezV, Z2, m, ioRecu()) end
for _, m in ipairs(ns.morceaux("autre", ns.encoder(etat), 1)) do ns.recevoirEtat(chezV, L2, m, ioRecu()) end
recus.demande = nil
ns.recevoirEtat(chezV, Z2, "D;id-1234567890", ioRecu())
assert(chezV.db.etats == nil or next(chezV.db.etats) == nil, "non-membre ou autre Compagnie : aucun état gardé")
assert(recus.demande == nil, "la demande d'un non-membre est ignorée")
ns.recevoirEtat(chezV, L2, "D;id-1234567890", ioRecu())
assert(recus.demande == L2, "Léo demande mon état : on y répond")
-- Sans Compagnie, rien n'est gardé.
local sans = { db = {}, moi = V2 }
for _, m in ipairs(ns.morceaux("id-1234567890", ns.encoder(etat), 1)) do ns.recevoirEtat(sans, L2, m, ioRecu()) end
assert(sans.db.etats == nil, "sans Compagnie : rien")
-- Morceaux mal formés, incomplets ou mélangés : rien n'est gardé, sans erreur.
chezV = compagnieDe(V2)
for _, m in ipairs({ "E", "E;", "E;id-1234567890", "E;id-1234567890;1/1/1", "E;id-1234567890;0/1/1;35#######",
  "E;id-1234567890;1/2/1;35#######", "E;id-1234567890;1/1/99;35#######", "E;id-1234567890;1/1/1;x#######", "D", "D;" }) do
  ns.recevoirEtat(chezV, L2, m, ioRecu())
end
ns.recevoirEtat(chezV, L2, morceaux[1], ioRecu()) -- le début d'un envoi…
ns.recevoirEtat(chezV, L2, ns.morceaux("id-1234567890", ns.encoder(gros), 8)[2], ioRecu()) -- …et la suite d'un autre
assert(chezV.db.etats == nil or chezV.db.etats[L2] == nil, "rien de mal formé n'est gardé")
-- Débit : un membre qui inonde est coupé (au-delà de 60 messages par minute), puis réécouté la minute suivante.
chezV = compagnieDe(V2)
recus.t = 5000
for _ = 1, 61 do ns.recevoirEtat(chezV, L2, "D;id-1234567890", ioRecu()) end
local un = ns.morceaux("id-1234567890", ns.encoder(etat), 3)
ns.recevoirEtat(chezV, L2, un[1], ioRecu())
assert(chezV.db.etats == nil or chezV.db.etats[L2] == nil, "au-delà du débit : ignoré")
recus.t = 5061
ns.recevoirEtat(chezV, L2, un[1], ioRecu())
assert(pareil(chezV.db.etats[L2], etat), "la minute suivante : écouté")
recus.t = nil

do -- les tests des versions ont leur propre chezV
local chezV
-- Versions : la demande d'état porte la version ; un état rejeté (autre format) prévient, une fois, avec la sienne.
local function versionsDe(v) local e = compagnieDe(V2); e.version = v; return e end
local illisible = "E;id-1234567890;1/1/1;35#######" -- 8 champs : le format d'une autre version
chezV, recus = versionsDe("v0.1.0-beta9"), {}
ns.recevoirEtat(chezV, L2, "D;id-1234567890;v0.1.0-beta10", ioRecu())
assert(recus.demande == L2 and chezV.versions[L2] == "v0.1.0-beta10", "une demande avec version : notée, et on y répond")
assert(recus.versionsEnvoyees == 1, "une autre version que la mienne : je lui dis la mienne")
ns.recevoirEtat(chezV, L2, "D;id-1234567890;v0.1.0-beta10", ioRecu())
assert(recus.versionsEnvoyees == 1, "une seule fois par membre : pas d'échange sans fin")
ns.recevoirEtat(chezV, L2, illisible, ioRecu())
assert(recus.incompatible == nil and recus.plusTard, "état rejeté : on attend un peu sa version avant de prévenir")
recus.plusTard()
assert(recus.incompatible.de == L2 and recus.incompatible.sa == "v0.1.0-beta10", "prévenu avec sa version")
recus.incompatible, recus.plusTard = nil, nil
ns.recevoirEtat(chezV, L2, illisible, ioRecu())
assert(recus.plusTard == nil, "prévenu une seule fois par membre et par session")
-- Une version d'avant beta9 ne dit pas la sienne : son état rejeté me fait envoyer la mienne, puis prévenir sans numéro.
chezV, recus = versionsDe("v0.1.0-beta9"), {}
ns.recevoirEtat(chezV, L2, "D;id-1234567890", ioRecu())
assert(recus.demande == L2 and chezV.versions == nil and recus.versionsEnvoyees == nil, "demande sans version : comme avant")
ns.recevoirEtat(chezV, L2, illisible, ioRecu())
assert(recus.versionsEnvoyees == 1, "état rejeté : je dis ma version (il saura que la sienne est ancienne)")
recus.plusTard()
assert(recus.incompatible.sa == false, "sans version connue : une version ancienne")
-- Même version et état rejeté (horloge, bug) : pas de faux « mettez à jour ». Version mal formée : ignorée.
chezV, recus = versionsDe("v0.1.0-beta9"), {}
ns.recevoirEtat(chezV, L2, "D;id-1234567890;v0.1.0-beta9", ioRecu())
assert(recus.versionsEnvoyees == nil, "même version : rien à dire")
ns.recevoirEtat(chezV, L2, illisible, ioRecu())
recus.plusTard()
assert(recus.incompatible == nil, "même version : pas de message de version")
ns.recevoirEtat(chezV, L2, "D;id-1234567890;|cffff0000x", ioRecu())
assert(chezV.versions[L2] == "v0.1.0-beta9", "version mal formée : ignorée")
recus = {}
end

-- Le dernier état connu compte pour un absent : les membres du calcul, dans l'ordre de la Compagnie, moi en direct ;
-- un membre jamais entendu compte sans quête (jamais à rendre sans lui) ; l'état d'un ancien membre est oublié.
chezV.db.etats[Z2] = etat -- Zoé n'est plus membre
local liste = ns.membresDuCalcul(chezV.db, V2, { niveau = 10, quetes = { [PATTES] = pattes(8) }, rendues = {} }, {})
assert(#liste == 2 and liste[1].nom == V2 and liste[2].nom == L2, "moi puis Léo")
assert(liste[2].absent and not liste[1].absent, "Léo absent")
assert(liste[2].quetes[PATTES].objectifs[1].fait == 5, "Léo compte avec son dernier état connu")
assert(chezV.db.etats[Z2] == nil, "l'état d'un ancien membre est oublié")
c = ns.calculer(liste)
assert(c.quetes[PATTES].objectifs[1].fait == 5 and c.quetes[PATTES].enAttente[1] == L2, "5/8, en attente de Léo")
assert(c.quetes[PATTES].objectifs[1].texte == "Patte de loup", "le texte vient de mon journal, pas du message")
chezV.db.etats[L2] = nil
liste = ns.membresDuCalcul(chezV.db, V2, { niveau = 10, quetes = { [PATTES] = pattes(8) }, rendues = {} }, {})
c = ns.calculer(liste)
assert(c.niveau == 10, "un membre jamais entendu n'a pas de niveau : celui des autres")
assert(c.quetes[PATTES].aRendre == false and c.quetes[PATTES].objectifs[1].fait == 0, "jamais entendu : 0/8, pas à rendre")
local sansC = { etats = { [L2] = etat } }
assert(#ns.membresDuCalcul(sansC, V2, etat, {}) == 0 and sansC.etats == nil, "plus de Compagnie : les états sont oubliés")

-- Le foyer d'un membre passe au calcul, corrigé ou non par le jeu.
local dbF = compagnieDe(V2).db
dbF.etats = { [L2] = avecFoyer }
local lf = ns.membresDuCalcul(dbF, V2, { quetes = {} }, {})[2]
assert(lf.auberge == "Comté-de-l'Or" and lf.finRecharge == 1764002400 and ns.corriger(lf, {}, function() end).liaison == 1763990000,
  "le foyer passe au calcul")
dbF.etats = { [L2] = avecAvant }
lf = ns.corriger(ns.membresDuCalcul(dbF, V2, { quetes = {} }, {})[2], {}, function() end)
assert(lf.avant[2002] and lf.renduesAvant[783], "les quêtes d'avant et les rendues avant l'entrée passent au calcul")

-- Quand un membre est dans le groupe, IsUnitOnQuest corrige son état : une quête qu'il n'a plus est retirée, une quête
-- qu'il a prise sans qu'on le sache compte à 0 ; une réponse inconnue (nil) ne change rien. Son état gardé n'est pas touché.
local garde = { niveau = 10, quetes = { [PATTES] = pattes(8), [CHASSE] = chasse(1, 1) }, rendues = {} }
local SUR = { [PATTES] = false, [CHASSE] = nil, [1003] = true, [1004] = false }
local corrige = ns.corriger(garde, { PATTES, CHASSE, 1003, 1004 }, function(id) return SUR[id] end)
assert(corrige.quetes[PATTES] == nil, "il n'a plus la quête : retirée")
assert(corrige.quetes[CHASSE] == garde.quetes[CHASSE], "réponse inconnue : inchangée")
assert(corrige.quetes[1003] and #corrige.quetes[1003].objectifs == 0 and not corrige.quetes[1003].finie, "prise : à 0")
assert(corrige.quetes[1004] == nil, "pas sur la quête, pas dans l'état : rien")
assert(garde.quetes[PATTES] and garde.quetes[1003] == nil, "l'état gardé n'est pas touché")

-- Les envois d'une rafale d'événements sont regroupés en un seul message ; un état inchangé ne repart pas, sauf en
-- réponse à une demande.
local e2, programmes, partis = { db = compagnieDe(V2).db }, {}, {}
local monEtat = { niveau = 10, quetes = { [PATTES] = pattes(3) }, rendues = {} }
local ioEnvoi = {
  programmer = function(delai, fn) programmes[#programmes + 1] = { delai = delai, fn = fn } end,
  monEtat = function() return monEtat end,
  envoyerEtat = function(texte) partis[#partis + 1] = texte end,
}
for _ = 1, 20 do ns.signaler(e2, false, ioEnvoi) end -- vingt QUEST_LOG_UPDATE d'affilée
assert(#programmes == 1 and programmes[1].delai > 0, "un seul envoi programmé pour la rafale")
monEtat = { niveau = 10, quetes = { [PATTES] = pattes(4) }, rendues = {} } -- l'état lu au moment de l'envoi
table.remove(programmes, 1).fn()
assert(#partis == 1, "un seul message : " .. #partis)
local recu1 = partis[1]:match("^E;[^;]+;%d+/%d+/%d+;(.*)$")
assert(recu1 and ns.decoder(recu1).quetes[PATTES].objectifs[1].fait == 4, "il porte l'état lu à l'envoi : " .. partis[1])
ns.signaler(e2, false, ioEnvoi)
table.remove(programmes, 1).fn()
assert(#partis == 1, "état inchangé : rien ne repart")
ns.signaler(e2, true, ioEnvoi) -- une demande d'état
ns.signaler(e2, false, ioEnvoi)
assert(#programmes == 1, "toujours un seul envoi programmé")
table.remove(programmes, 1).fn()
assert(#partis == 2, "en réponse à une demande : il repart")
-- Un message refusé par la file d'envoi (pleine) : l'état n'est pas noté comme parti, il repart au prochain envoi.
local refuse = true
ioEnvoi.envoyerEtat = function(texte) if refuse then return false end partis[#partis + 1] = texte end
monEtat = { niveau = 11, quetes = {}, rendues = {} }
ns.signaler(e2, false, ioEnvoi)
table.remove(programmes, 1).fn()
assert(#partis == 2, "refusé : rien n'est parti")
refuse = false
ns.signaler(e2, false, ioEnvoi)
table.remove(programmes, 1).fn()
assert(#partis == 3, "le même état repart : " .. #partis)
-- Un état qui ne tient pas dans MAX_MORCEAUX : rien ne part (jamais un état tronqué), et c'est dit une fois.
local trop = 0
ioEnvoi.trop = function() trop = trop + 1 end
local enorme = { niveau = 11, quetes = {}, rendues = {} }
for i = 1, 120 do enorme.quetes[90000 + i] = { finie = false, objectifs = { { fait = 1, total = 2 }, { fait = 1, total = 2 } }, zone = "Zone " .. i } end
monEtat = enorme
for _ = 1, 3 do ns.signaler(e2, true, ioEnvoi); table.remove(programmes, 1).fn() end
assert(#partis == 3 and trop == 1, "trop gros : rien ne part, dit une fois (" .. trop .. ")")
monEtat = { niveau = 12, quetes = {}, rendues = {} }
ns.signaler(e2, false, ioEnvoi)
table.remove(programmes, 1).fn()
assert(#partis == 4, "de nouveau petit : il part")
monEtat = enorme
ns.signaler(e2, false, ioEnvoi)
table.remove(programmes, 1).fn()
assert(trop == 2, "trop gros de nouveau : redit")
-- Sans Compagnie, rien ne part.
local e3 = { db = {} }
ns.signaler(e3, true, ioEnvoi)
table.remove(programmes, 1).fn()
assert(#partis == 4, "sans Compagnie : rien")

-- La liste des membres (#23) part avec l'état, datée : encodage puis décodage → identique (le GUID sans « Player- »).
local avecListe = { niveau = 12, quetes = {}, rendues = {}, ecartees = {}, avant = {}, renduesAvant = {},
  liste = { date = 1764000000, membres = { { guid = "Player-4395-0A1B2C3D", nom = "Virgile Marteau" }, { guid = "Player-4395-0A1B2C3E", nom = "Léo Lame" } } } }
corps = ns.encoder(avecListe)
assert(corps:find("#1764000000=4395%-0A1B2C3D:Virgile Marteau,4395%-0A1B2C3E:Léo Lame##$"), "la liste, en 13e champ : " .. corps)
assert(pareil(ns.decoder(corps), avecListe), "avec la liste : identique (" .. corps .. ")")
for _, f in ipairs({ "x", "1764000000", "1764000000=", "1764000000=1-A:Léo", "1764000000=1-A:Léo,1-A:Mira", "1764000000=1-A:,1-B:Mira",
  "1764000000=1-A:L|o,1-B:Mira", "1764000000=Player-1-A:Léo,1-B:Mira", "=1-A:Léo,1-B:Mira",
  "1764000000=1-A:A,1-B:B,1-C:C,1-D:D,1-E:E,1-F:F" }) do
  assert(ns.decoder("12############" .. f .. "##") == nil, "liste rejetée : " .. f)
end

-- Inviter (#23) : Virgile et Léo sont une Compagnie, Mira est dans le groupe. Virgile invite Mira : proposition ;
-- acceptée, elle entre chez Virgile, puis chez elle et chez Léo avec l'état de Virgile, qui porte la nouvelle liste.
c = groupe({ V, L, M })
ns.fonder(c[V].e, V, c[V].groupe, "idI", c[V].io)
ns.repondre(c[L].e, true, c[L].io)
ns.repondre(c[M].e, false, c[M].io)
assert(noms(c[V]) == "Virgile Marteau,Léo Lame" and noms(c[L]) == noms(c[V]), "Virgile et Léo")
local function etatDe(cl) -- l'état de cl, tel qu'il part (ses quêtes n'importent pas ici)
  local cc = cl.e.db.compagnie
  return ns.morceaux(cc.id, ns.encoder({ niveau = 10, quetes = {}, liste = { date = cc.date, membres = cc.membres },
    ecartees = cl.e.db.ecartees, zoneCompagnie = cl.e.db.zoneCompagnie }), 1)
end
local function livrerEtat(de, a, io)
  for _, m in ipairs(etatDe(de)) do ns.recevoirEtat(a.e, de.moi, m, io or ioRecu()) end
end
c[V].e.db.zoneCompagnie = { zone = 148, date = 1764000000, par = "Léo" } -- la zone et une écartée, gardées pour Mira
c[V].e.db.ecartees = { [783] = { ecartee = true, date = 1764000000, par = "Léo" } }
local propositions = c[M].propositions
assert(ns.inviter(c[V].e, V, c[V].groupe, M, c[V].io), "inviter Mira, du groupe")
assert(c[V].envoyes[#c[V].envoyes] == "I;idI;" .. M and c[M].propositions == propositions + 1 and c[M].e.proposition.invitation,
  "la proposition part, Mira la reçoit")
assert(c[L].propositions == 0 or not (c[L].e.proposition and c[L].e.proposition.invitation), "Léo n'est pas invité")
-- Avant que Mira soit dans la liste, l'état de Virgile ne la fait pas entrer.
recus.liste = nil
livrerEtat(c[V], c[M])
assert(c[M].e.db.compagnie == nil and recus.liste == nil, "pas encore acceptée : rien")
ns.repondre(c[M].e, true, c[M].io)
assert(noms(c[V]) == "Virgile Marteau,Léo Lame,Mira Feuille" and dit(c[V], "Mira Feuille entre dans la Compagnie"), "chez Virgile")
recus.annonces = nil
livrerEtat(c[V], c[M])
assert(noms(c[M]) == "Virgile Marteau,Léo Lame,Mira Feuille" and recus.liste.entre, "chez Mira : membre, son entrée notée")
assert(c[M].e.db.zoneCompagnie.zone == 148 and c[M].e.db.ecartees[783].ecartee and recus.annonces == nil,
  "elle arrive avec la zone et les écartées de la Compagnie (sans un message par écartée)")
assert(c[M].e.proposition == nil and c[M].e.db.compagnie.id == "idI", "dans la même Compagnie")
recus.liste = nil
livrerEtat(c[V], c[L])
assert(noms(c[L]) == "Virgile Marteau,Léo Lame,Mira Feuille" and recus.liste.ajoutes[1] == "Mira Feuille", "chez Léo, Mira annoncée")
recus.liste = nil
livrerEtat(c[V], c[L])
assert(recus.liste == nil, "la même liste : rien de nouveau")
-- Refusée : rien.
c = groupe({ V, L, M })
ns.fonder(c[V].e, V, c[V].groupe, "idR", c[V].io)
ns.repondre(c[L].e, true, c[L].io)
ns.repondre(c[M].e, false, c[M].io)
ns.inviter(c[V].e, V, c[V].groupe, M, c[V].io)
ns.repondre(c[M].e, false, c[M].io)
assert(noms(c[V]) == "Virgile Marteau,Léo Lame" and dit(c[V], "Mira Feuille refuse d'entrer"), "refusée : " .. dernier(c[V]))
livrerEtat(c[V], c[M])
assert(c[M].e.db.compagnie == nil, "Mira n'est pas membre")
-- Déjà membre d'une autre Compagnie : refusé d'office, avec la raison.
c[M].e.db.compagnie = { id = "autre", date = 1, membres = { { guid = M, nom = "Mira Feuille" }, { guid = Z, nom = "Zoé Pierre" } } }
ns.inviter(c[V].e, V, c[V].groupe, M, c[V].io)
assert(c[M].envoyes[#c[M].envoyes] == "R;idR;deja" and dit(c[V], "Mira Feuille est déjà membre d'une Compagnie"), dernier(c[V]))
assert(noms(c[V]) == "Virgile Marteau,Léo Lame", "pas entrée")
-- Une Compagnie à 5 : refusé, avec la raison ; déjà membre, ou hors du groupe : refusé aussi.
local cinq = { id = "id5", date = 1, membres = {} }
for i, g in ipairs({ V, L, M, Z, "Player-1-0000000A" }) do cinq.membres[i] = { guid = g, nom = NOMS[g] or "Anne" } end
local e5 = { db = { compagnie = cinq }, moi = V }
ok, raison = ns.inviter(e5, V, groupeDe(V, { L, "Player-1-0000000B" }), "Player-1-0000000B", c[V].io)
assert(not ok and raison:find("déjà 5 membres", 1, true), "à 5 : " .. tostring(raison))
ok, raison = ns.inviter(c[V].e, V, c[V].groupe, L, c[V].io)
assert(not ok and raison:find("déjà membre de la Compagnie", 1, true), tostring(raison))
ok, raison = ns.inviter(c[V].e, V, c[V].groupe, Z, c[V].io)
assert(not ok and raison:find("groupe du jeu", 1, true), tostring(raison))
-- Un absent apprend la nouvelle liste à son retour : Léo, parti avant l'invitation de Mira, reçoit l'état de Virgile.
c = groupe({ V, L, M })
ns.fonder(c[V].e, V, c[V].groupe, "idA", c[V].io)
ns.repondre(c[L].e, true, c[L].io)
ns.repondre(c[M].e, false, c[M].io)
local absent = c[L]
clients[L] = nil -- Léo est hors ligne : il ne reçoit plus rien
ns.inviter(c[V].e, V, c[V].groupe, M, c[V].io)
ns.repondre(c[M].e, true, c[M].io)
assert(noms(absent) == "Virgile Marteau,Léo Lame", "absent, Léo a l'ancienne liste")
recus.liste = nil
livrerEtat(c[V], absent) -- à son retour
assert(noms(absent) == "Virgile Marteau,Léo Lame,Mira Feuille" and recus.liste.ajoutes[1] == "Mira Feuille", "il apprend la nouvelle")
-- Une liste plus ancienne ne remplace pas la mienne ; une liste plus récente sans moi : je ne suis plus membre.
local vieux = { db = { compagnie = { id = "idA", date = horloge + 100, membres = { { guid = V, nom = "Virgile Marteau" }, { guid = L, nom = "Léo Lame" } } } }, moi = L }
livrerEtat(c[V], { e = vieux })
assert(#vieux.db.compagnie.membres == 2, "une liste plus ancienne : ignorée")
assert(ns.fusionnerListe(vieux, "idA", { date = horloge + 200, membres = { { guid = V, nom = "Virgile Marteau" }, { guid = M, nom = "Mira Feuille" } } }).sorti
  and vieux.db.compagnie == nil, "plus récente, sans moi : plus de Compagnie")

print("Compagnie : états de la Compagnie OK")
