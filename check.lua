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
-- Non partageable (ou pas dit, la quête d'un autre membre) : pas « à partager » (c'est « à prendre soi-même », plus tard).
c = ns.calculer({ { nom = "Virgile", niveau = 5, quetes = { [KOBOLDS] = kobolds(false) } }, { nom = "Léo", niveau = 5, quetes = {} } })
assert(#c.aFaire == 0, "non partageable : pas à partager")
c = ns.calculer({ { nom = "Virgile", niveau = 5, quetes = {} }, { nom = "Léo", niveau = 5, quetes = { [KOBOLDS] = kobolds() } } })
assert(#c.aFaire == 0, "partageable inconnu : rien")
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
-- Une quête d'avant que tous les membres ont redevient une quête de la Compagnie (même zone de départ).
c = ns.calculer({
  { nom = "Virgile", niveau = 12, quetes = { [COMTE] = pattes(8) }, avant = { [COMTE] = true } },
  { nom = "Léo", niveau = 12, quetes = { [COMTE] = pattes(3) } },
})
assert(c.quetes[COMTE] and c.quetes[COMTE].objectifs[1].fait == 3 and #c.aPart == 0, "tous l'ont : commune, 3/8")
-- Mira (jamais entendue) ne l'a pas : elle reste à part.
c = ns.calculer({
  { nom = "Virgile", niveau = 12, quetes = { [COMTE] = pattes(8) }, avant = { [COMTE] = true } },
  { nom = "Léo", niveau = 12, quetes = { [COMTE] = pattes(3) } }, { nom = "Mira" },
})
assert(not c.quetes[COMTE] and #c.aPart == 2, "pas tous : à part, chez chacun qui l'a")
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

print("Compagnie : calcul de la Compagnie OK")

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
local function client(moi, guids)
  local cl = { moi = moi, e = { db = {} }, dits = {}, envoyes = {}, propositions = 0, maj = 0 }
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
-- Le texte des objectifs n'est jamais envoyé (code de grammaire du jeu « |4… ; ») : seulement les nombres.
local avecTexte = { niveau = 12, quetes = { [7] = { finie = false, objectifs = {
  { texte = "Raptor flagellant : 2/10 |4personnage tué:personnages tués;", fait = 2, total = 10 } } } }, rendues = {} }
assert(not ns.encoder(avecTexte):find("Raptor", 1, true), "le texte n'est pas envoyé")
assert(ns.decoder(ns.encoder(avecTexte)).quetes[7].objectifs[1].fait == 2, "les nombres le sont")

-- Lecture stricte : un champ mal formé, et tout l'état est rejeté (jamais exécuté ni interprété). Un seul format (bêta) :
-- un état à quatre champs (celui de #13, sans abandons) est rejeté aussi.
for _, mauvais in ipairs({ "", "x", "35", "35#", "35##", "35#1:0#", "35#1:0##", "0####", "35#a:0####",
  "35#1:2####", "35#1:0:9/8####", "35#1:0:1/2:####", "35#1:0#####", "35##1,,2##", "999####", "35#1:0;1:1####",
  "35#-1:0####", "35#1:0:1/2/3####", "35#1:0##" .. ("1,"):rep(300) .. "1##", "35#1:0:" .. ("1/2:"):rep(30) .. "1/2####",
  "os.exit()", "35#1:0##;os.exit()##", "35#1:0###x", "35#1:0###1,,2", "35#1:0###-1", "35#1:0###0",
  "35#1:0###" .. ("1,"):rep(300) .. "1" }) do
  assert(ns.decoder(mauvais) == nil, "rejeté : " .. mauvais:sub(1, 40))
  assert(ns.decoder(mauvais .. "#####") == nil, "rejeté avec le foyer et les quêtes d'avant : " .. mauvais:sub(1, 40))
end
-- Un état à cinq champs (celui de #5, sans foyer) est rejeté (#9) ; à huit (celui de #9, sans quêtes d'avant) aussi (#20).
assert(ns.decoder("35#1:0####") == nil and ns.decoder("35#1:0######") == nil and ns.decoder("35#1:0########"),
  "cinq et huit champs : rejeté ; dix : lu")

-- Les quêtes d'avant et les quêtes rendues avant l'entrée (#20) partent avec l'état : encodage puis décodage → identique.
local avecAvant = { niveau = 14, quetes = { [PATTES] = { finie = false, objectifs = {} }, [2002] = { finie = true, objectifs = {} } },
  avant = { [2002] = true }, rendues = { [1453] = true }, renduesAvant = { [783] = true, [95790] = true }, ecartees = {} }
corps = ns.encoder(avecAvant)
assert(corps:find("#2002#783,95790$"), "quêtes d'avant, puis rendues avant l'entrée, triées : " .. corps)
assert(pareil(ns.decoder(corps), avecAvant), "avec quêtes d'avant : identique (" .. corps .. ")")
-- Une quête d'avant qui n'est plus dans le journal ne part pas ; reçue, elle fait rejeter l'état.
assert(ns.encoder({ niveau = 2, quetes = {}, avant = { [9] = true } }) == "2#########", "quête d'avant hors du journal : ne part pas")
for _, mauvais in ipairs({ "35#1:0#######2#", "35#1:0#######x#", "35#1:0#######1,1#", "35#1:0########0", "35#1:0########1,,2" }) do
  assert(ns.decoder(mauvais) == nil, "rejeté : " .. mauvais)
end

-- Les questID sont bornés à 2147483647 (un entier 32 bits signé, comme le jeu).
assert(ns.decoder("35#2147483647:0#2147483647##2147483647:1:2147483647:V####2147483647#2147483647").quetes[2147483647],
  "2147483647 : accepté")
assert(ns.decoder("35#2147483648:0########") == nil and ns.decoder("35##2147483648#######") == nil and
  ns.decoder("35####2147483648:1:1:V#####") == nil and ns.decoder("35####1:1:2147483648:V#####") == nil and
  ns.decoder("35#########2147483648") == nil, "au-delà : rejeté")

-- Les quêtes écartées (#21) partent avec l'état, datées, avec qui a décidé, remises comprises : encodage puis décodage
-- → identique.
local avecEcartees = { niveau = 12, quetes = { [PATTES] = { finie = false, objectifs = {} } }, rendues = { [1453] = true },
  ecartees = { [783] = { ecartee = true, date = 1764000000, par = "Léo" }, [95790] = { ecartee = false, date = 1764000100, par = "Virgile" } },
  avant = {}, renduesAvant = {} }
corps = ns.encoder(avecEcartees)
assert(corps:find("#783:1:1764000000:Léo;95790:0:1764000100:Virgile#####$"), "écartées triées, puis le foyer (vide) : " .. corps)
assert(pareil(ns.decoder(corps), avecEcartees), "avec écartées : identique (" .. corps .. ")")
-- Mal formées : tout l'état est rejeté (statut 0 ou 1, date entière positive, « par » comme une zone, une quête une fois).
for _, f in ipairs({ "783", "783:1:1", "783:2:1:Léo", "783:1:0:Léo", "783:1:x:Léo", "783:1:1:", "783:1:1:a|b", "x:1:1:Léo",
  "783:1:1:Léo;783:0:2:Léo", "783:1:1:Léo;", "783:1:1:Léo:1" }) do
  assert(ns.decoder("12#####" .. f .. "#####") == nil, "écartée rejetée : " .. f)
end
-- Au-delà de 50 décisions, seules les 50 plus récentes partent (l'état reste lisible).
local beaucoup = { niveau = 5, quetes = {}, ecartees = {} }
for i = 1, 60 do beaucoup.ecartees[i] = { ecartee = true, date = 1000 + i, par = "Léo" } end
lu = assert(ns.decoder(ns.encoder(beaucoup)), "60 décisions : lisible")
local n = 0
for _ in pairs(lu.ecartees) do n = n + 1 end
assert(n == 50 and lu.ecartees[60] and not lu.ecartees[10], "les 50 plus récentes : " .. n)

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
-- Le foyer (#9) part avec l'état : auberge, heure de la liaison, heure où la pierre est prête → identique.
local avecFoyer = { niveau = 12, quetes = {}, rendues = {}, ecartees = {}, avant = {}, renduesAvant = {}, auberge = "Comté-de-l'Or", liaison = 1763990000,
  finRecharge = 1764002400 }
corps = ns.encoder(avecFoyer)
assert(corps == "12#####Comté-de-l'Or#1763990000#1764002400##", corps)
assert(pareil(ns.decoder(corps), avecFoyer), "avec foyer : identique")
-- Mal formé : tout l'état est rejeté (auberge comme une zone ; heures entières, positives, 32 bits).
for _, f in ipairs({ "a|b#1#1", ("x"):rep(49) .. "#1#1", "a;b##", "Or#x#", "Or#0#", "Or##-1", "Or##2147483648", "Or#1.5#" }) do
  assert(ns.decoder("12#####" .. f .. "##") == nil, "foyer rejeté : " .. f:sub(1, 20))
end
-- « partageable » (lu dans mon journal) ne part pas.
assert(ns.encoder({ niveau = 2, quetes = { [7] = { finie = false, objectifs = {}, partageable = true } } }) == "2#7:0########",
  "partageable ne part pas")

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
local sansZone = assert(ns.decoder("35#1001:0:5/8;659:0#1453#######"), "sans zone : accepté")
assert(sansZone.quetes[1001].zone == nil and sansZone.quetes[1001].objectifs[1].fait == 5, "…ses quêtes sans zone")
-- Une zone mal formée fait rejeter tout l'état : vide, trop longue, caractère de contrôle, « | » (codes du chat), un
-- séparateur du format ; une zone sans quête, une quête absente de l'état ou rangée deux fois, une zone répétée.
for _, z in ipairs({ "", ("x"):rep(49), "a|cffff0000b", "a\nb", "a\1b", "a\0b", "a\127b", "a#b", "a;b", "a:b", "a,b",
  "a/b", "a=b" }) do
  assert(ns.decoder("35#1001:0#1453#" .. z .. "=1001######") == nil, "zone rejetée : " .. z:sub(1, 20))
end
assert(ns.decoder("35#1001:0##" .. ("é"):rep(24) .. "=1001######"), "48 octets : acceptée")
for _, mauvais in ipairs({ "35#1001:0##Elwynn#", "35#1001:0##Elwynn=#", "35#1001:0##Elwynn=x#", "35#1001:0##Elwynn=2002#",
  "35#1001:0##A=1001;B=1001#", "35#1001:0;1002:0##A=1001;A=1002#", "35#1001:0##A=1001,1001#", "35#1001:0##A=1001;#",
  "35#1001:0##A=1001##" }) do
  assert(ns.decoder(mauvais .. "#####") == nil, "rejeté : " .. mauvais)
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
  annoncer = function(t) recus.annonces = t end,
  demande = function(de) recus.demande = de end, maintenant = function() return recus.t or 1000 end } end
local chezV = compagnieDe(V2)
for _, m in ipairs(morceaux) do ns.recevoirEtat(chezV, L2, m, ioRecu()) end
assert(pareil(chezV.db.etats[L2], gros), "l'état de Léo est recomposé et gardé comme dernier état connu")
assert(recus.maj and recus.maj > 0, "le suivi est redessiné")
-- Ses décisions sur les quêtes écartées (#21) rejoignent celles de la Compagnie, et celles qui changent sont annoncées.
recus.annonces = nil
for _, m in ipairs(ns.morceaux("id-1234567890", ns.encoder(avecEcartees), 9)) do ns.recevoirEtat(chezV, L2, m, ioRecu()) end
assert(chezV.db.ecartees[783].ecartee and chezV.db.ecartees[783].par == "Léo", "la décision de Léo est celle de la Compagnie")
assert(recus.annonces and #recus.annonces == 2 and recus.annonces[1].quete == 783, "annoncées dans le chat")
recus.annonces = nil
for _, m in ipairs(ns.morceaux("id-1234567890", ns.encoder(avecEcartees), 10)) do ns.recevoirEtat(chezV, L2, m, ioRecu()) end
assert(recus.annonces == nil, "reçues de nouveau : rien à annoncer")

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
-- Sans Compagnie, rien ne part.
local e3 = { db = {} }
ns.signaler(e3, true, ioEnvoi)
table.remove(programmes, 1).fn()
assert(#partis == 3, "sans Compagnie : rien")

print("Compagnie : états de la Compagnie OK")
