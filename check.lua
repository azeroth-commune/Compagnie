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

print("Compagnie : membres de la Compagnie OK")
