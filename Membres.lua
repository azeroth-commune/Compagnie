-- Compagnie, les membres : fonder, accepter, refuser, quitter, retirer. La logique seule, sans aucun appel à l'API du
-- jeu (vérifié par check.lua) ; Compagnie.lua lui passe ce que le jeu donne :
--   e      : l'état { db = CompagnieDB, proposition = celle reçue, fondation = la mienne en cours }
--   moi    : mon GUID
--   groupe : les personnages connectés de mon groupe du jeu, moi d'abord : { { guid, nom }, … } (donnés par le serveur)
--   io     : { envoyer = fn(texte) au groupe du jeu, dire = fn(texte) au joueur, proposer = fn(proposition), maj = fn() }
-- La Compagnie (donnée propre) : db.compagnie = { id, membres = { { guid, nom }, … } }, de 2 à 5 membres.
-- Messages d'add-on, envoyés au groupe du jeu (jamais chuchotés) : « verbe;id[;GUID,GUID…] »
--   P;id;liste  proposition, le fondateur d'abord     A;id  j'accepte     R;id[;deja]  je refuse (déjà membre)
--   F;id;liste  la Compagnie fondée                    Q;id  je quitte     X;id;GUID    je retire ce membre
-- L'expéditeur (de) est le GUID que le serveur donne pour son nom dans le groupe, jamais pris dans le message. Un message
-- d'un non-membre est ignoré, sauf une proposition qui me nomme, venue de son fondateur. Donnée reçue telle quelle
-- entre membres (CONTEXT-MAP) : le pire est une liste fausse.
local _, ns = ...
ns.MAX = 5

local function index(liste, guid)
  for i, x in ipairs(liste) do if x == guid or (type(x) == "table" and x.guid == guid) then return i end end
end
function ns.membre(c, guid) return c and index(c.membres, guid) end

local function nomDans(groupe, guid)
  local i = index(groupe, guid)
  return i and groupe[i].nom or "?"
end

-- Les membres d'une Compagnie, dans l'ordre de la liste, nommés d'après le groupe du jeu (tous y sont à la fondation).
local function membres(guids, groupe)
  local t = {}
  for i, g in ipairs(guids) do t[i] = { guid = g, nom = nomDans(groupe, g) } end
  return t
end

local function noms(c)
  local t = {}
  for i, m in ipairs(c.membres) do t[i] = m.nom end
  return table.concat(t, ", ")
end

-- Fonder depuis mon groupe du jeu : la proposition part vers les autres. nil, raison si c'est refusé.
function ns.fonder(e, moi, groupe, id, io)
  if e.db.compagnie then return nil, "Tu es déjà membre d'une Compagnie : quitte-la avant d'en fonder une autre." end
  if #groupe < 2 then return nil, "Fonder une Compagnie se fait depuis un groupe du jeu : forme d'abord un groupe avec tes compagnons." end
  if #groupe > ns.MAX then
    return nil, ("Une Compagnie a au plus %d membres : ton groupe compte %d personnages."):format(ns.MAX, #groupe)
  end
  local guids, reponses = {}, {}
  for i, p in ipairs(groupe) do
    guids[i] = p.guid
    if i > 1 then reponses[p.guid] = false end -- false : réponse attendue
  end
  e.fondation = { id = id, guids = guids, reponses = reponses }
  io.envoyer("P;" .. id .. ";" .. table.concat(guids, ","))
  return true
end

-- Fin de la fondation (tous ont répondu, ou le délai est écoulé) : le fondateur et ceux qui ont accepté.
function ns.cloturer(e, moi, groupe, io)
  local f = e.fondation
  if not f then return end
  e.fondation = nil
  local guids = { moi }
  for i = 2, #f.guids do if f.reponses[f.guids[i]] == "A" then guids[#guids + 1] = f.guids[i] end end
  if #guids < 2 or e.db.compagnie then return io.dire("Personne n'a accepté : pas de Compagnie.") end
  e.db.compagnie = { id = f.id, membres = membres(guids, groupe) }
  io.envoyer("F;" .. f.id .. ";" .. table.concat(guids, ","))
  io.dire("Compagnie fondée : " .. noms(e.db.compagnie) .. ".")
  io.maj()
end

-- Ma réponse à la proposition reçue. Déjà membre : rien à répondre (le refus est parti à la réception).
function ns.repondre(e, oui, io)
  local p = e.proposition
  if not p or p.deja or p.accepte then return end
  if oui then p.accepte = true else e.proposition = nil end
  io.envoyer((oui and "A;" or "R;") .. p.id)
end

-- Moins de deux membres : il n'y a plus de Compagnie.
local function oter(e, i)
  local c = e.db.compagnie
  table.remove(c.membres, i)
  if #c.membres < 2 then e.db.compagnie = nil end
end

function ns.quitter(e, io)
  local c = e.db.compagnie
  if not c then return end
  io.envoyer("Q;" .. c.id)
  e.db.compagnie = nil
  io.dire("Tu as quitté la Compagnie.")
  io.maj()
end

-- Retirer un autre membre (pas de chef : n'importe quel membre le peut).
function ns.retirer(e, moi, guid, io)
  local c = e.db.compagnie
  local i = ns.membre(c, guid)
  if not i or guid == moi then return false end
  io.envoyer("X;" .. c.id .. ";" .. guid)
  local nom = c.membres[i].nom
  oter(e, i)
  io.dire(nom .. " est retiré de la Compagnie." .. (e.db.compagnie and "" or " Tu restes seul : plus de Compagnie."))
  io.maj()
  return true
end

local function liste(texte)
  local t = {}
  for g in (texte or ""):gmatch("[^,]+") do t[#t + 1] = g end
  return t
end

function ns.recevoir(e, moi, groupe, de, texte, io)
  local verbe, id, arg = texte:match("^(%u);([^;]+);?(.*)$")
  if not verbe or de == moi then return end
  local c = e.db.compagnie
  if verbe == "P" then
    local guids = liste(arg)
    if guids[1] ~= de or not index(guids, moi) then return end -- seul le fondateur propose, à ceux qu'il nomme
    e.proposition = { id = id, de = de, nom = nomDans(groupe, de), guids = guids, deja = c ~= nil }
    if c then io.envoyer("R;" .. id .. ";deja") end
    io.proposer(e.proposition)
  elseif verbe == "A" or verbe == "R" then
    local f = e.fondation
    if not (f and f.id == id and f.reponses[de] == false) then return end
    f.reponses[de] = verbe
    if verbe == "R" then
      io.dire(nomDans(groupe, de) .. (arg == "deja" and " est déjà membre d'une Compagnie." or " refuse."))
    end
    for _, r in pairs(f.reponses) do if r == false then return end end
    ns.cloturer(e, moi, groupe, io)
  elseif verbe == "F" then
    local p, guids = e.proposition, liste(arg)
    if c or not (p and p.id == id and p.de == de and p.accepte) or not index(guids, moi) then return end
    e.proposition = nil
    e.db.compagnie = { id = id, membres = membres(guids, groupe) }
    io.dire("Compagnie fondée : " .. noms(e.db.compagnie) .. ".")
    io.maj()
  elseif verbe == "Q" or verbe == "X" then
    if not (c and c.id == id and ns.membre(c, de)) then return end -- un non-membre, ou une autre Compagnie
    local qui = verbe == "Q" and de or arg
    local i = ns.membre(c, qui)
    if not i then return end
    local nom, par = c.membres[i].nom, c.membres[ns.membre(c, de)].nom
    if qui == moi then
      e.db.compagnie = nil
      io.dire(par .. " t'a retiré de la Compagnie.")
    else
      oter(e, i)
      io.dire((verbe == "Q" and nom .. " a quitté la Compagnie." or par .. " a retiré " .. nom .. " de la Compagnie.")
        .. (e.db.compagnie and "" or " Tu restes seul : plus de Compagnie."))
    end
    io.maj()
  end
end
