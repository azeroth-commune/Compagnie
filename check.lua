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

print("Compagnie : calcul de la Compagnie OK")
