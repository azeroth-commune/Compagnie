-- Compagnie, les membres : fonder, inviter, accepter, refuser, quitter, retirer. La logique seule, sans aucun appel à l'API du
-- jeu (vérifié par check.lua) ; Compagnie.lua lui passe ce que le jeu donne :
--   e      : l'état { db = CompagnieDB, proposition = celle reçue (fondation, ou invitation : invitation = true),
--            fondation = la mienne en cours, invitations = { [GUID invité] = idCompagnie } (les miennes en cours) }
--   moi    : mon GUID
--   groupe : les personnages connectés de mon groupe du jeu, moi d'abord : { { guid, nom }, … } (donnés par le serveur)
--   io     : { envoyer = fn(texte) au groupe du jeu, dire = fn(texte) au joueur, proposer = fn(proposition), maj = fn(),
--              entrer = fn() : je deviens membre (fondation), mes quêtes d'avant sont notées (#20),
--              heure = fn() -> heure serveur (la date de la liste) }
-- La Compagnie (donnée propre) : db.compagnie = { id, date, membres = { { guid, nom }, … } }, de 2 à 5 membres ; date :
-- l'heure serveur du dernier changement de la liste (fondée, quelqu'un entre, quitte ou est retiré). La liste part avec
-- l'état (Etats.lua) : un absent apprend la plus récente à son retour, et un invité y entre (#23).
-- Messages d'add-on, envoyés au groupe du jeu (jamais chuchotés) : « verbe;id[;GUID,GUID…] »
--   P;id;liste  proposition, le fondateur d'abord     A;id  j'accepte
--   R;id[;deja|occupe]  je refuse (déjà membre, ou une fondation en cours pour moi)
--   F;id;liste  la Compagnie fondée                    Q;id  je quitte     X;id;GUID    je retire ce membre
--   I;id;GUID   j'invite ce joueur du groupe dans la Compagnie id (#23) ; il répond A;id ou R;id[;deja|occupe] ; accepté,
--               il entre chez moi, et chez lui avec mon état qui porte la nouvelle liste (Etats.lua)
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

-- Déjà engagé : membre d'une Compagnie (« deja »), ou une fondation en cours pour moi, la mienne ou celle que j'ai
-- acceptée jusqu'à son F (« occupe »). Un personnage engagé ne fonde pas, n'accepte pas et refuse d'office une proposition
-- reçue : il n'est jamais compté dans deux Compagnies, même quand deux fondateurs se croisent (chacun refuse celle de
-- l'autre).
local function engage(e)
  if e.db.compagnie then return "deja" end
  if e.fondation or (e.proposition and e.proposition.accepte) then return "occupe" end
end

-- Fonder depuis mon groupe du jeu : la proposition part vers les autres. nil, raison si c'est refusé.
function ns.fonder(e, moi, groupe, id, io)
  if e.db.compagnie then return nil, "Tu es déjà membre d'une Compagnie : quitte-la avant d'en fonder une autre." end
  if e.fondation then return nil, "Ta proposition est déjà partie : attends les réponses." end
  if engage(e) then
    return nil, ("Tu as accepté la proposition de %s : attends qu'elle soit fondée."):format(e.proposition.nom)
  end
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

-- Fin de la fondation (tous ont répondu, ou le délai est écoulé) : le fondateur et ceux qui ont accepté. Pendant sa
-- fondation, le fondateur ne devient membre de rien (il n'accepte pas, il refuse d'office) : rien d'autre à vérifier.
function ns.cloturer(e, moi, groupe, io)
  local f = e.fondation
  if not f then return end
  e.fondation = nil
  local guids = { moi }
  for i = 2, #f.guids do if f.reponses[f.guids[i]] == "A" then guids[#guids + 1] = f.guids[i] end end
  if #guids < 2 then return io.dire("Personne n'a accepté : pas de Compagnie.") end
  e.db.compagnie = { id = f.id, date = io.heure(), membres = membres(guids, groupe) }
  io.entrer()
  io.envoyer("F;" .. f.id .. ";" .. table.concat(guids, ","))
  io.dire("Compagnie fondée : " .. noms(e.db.compagnie) .. ".")
  io.maj()
end

-- Ma réponse à la proposition reçue. Déjà membre à la réception : rien à répondre (le refus est parti). Devenu membre,
-- ou fondateur, depuis la réception : « Accepter » répond non.
function ns.repondre(e, oui, io)
  local p = e.proposition
  if not p or p.deja or p.accepte then return end
  local r = oui and engage(e)
  if r then
    e.proposition = nil
    io.envoyer("R;" .. p.id .. ";" .. r)
    return io.dire((r == "deja" and "Tu es déjà membre d'une Compagnie" or "Ta propre proposition est en cours")
      .. " : ta réponse à " .. p.nom .. " est non.")
  end
  if oui then p.accepte = true else e.proposition = nil end
  io.envoyer((oui and "A;" or "R;") .. p.id)
end

-- Une proposition acceptée sans F au bout du délai (le fondateur est parti sans clore), ou une invitation acceptée
-- sans l'état qui me fait entrer : elle n'engage plus.
function ns.expirer(e, id, io)
  local p = e.proposition
  if not (p and p.id == id and p.accepte) then return end
  e.proposition = nil
  io.dire(p.invitation and "L'invitation de " .. p.nom .. " n'a pas abouti." or "La Compagnie proposée par " .. p.nom .. " n'a pas été fondée.")
end

-- Inviter un joueur de mon groupe du jeu dans ma Compagnie (#23) ; nil, raison si c'est refusé. Mêmes gardes que la
-- fondation : 5 membres au plus (revu à l'acceptation), une seule Compagnie par personnage (il refuse d'office).
function ns.inviter(e, moi, groupe, guid, io)
  local c = e.db.compagnie
  if not c then return nil, "Pas de Compagnie : fonde-la d'abord." end
  if #c.membres >= ns.MAX then return nil, ("La Compagnie a déjà %d membres : c'est le plus."):format(ns.MAX) end
  if ns.membre(c, guid) then return nil, nomDans(groupe, guid) .. " est déjà membre de la Compagnie." end
  if guid == moi or not index(groupe, guid) then return nil, "Inviter se fait depuis un groupe du jeu : invite-le d'abord dans ton groupe." end
  e.invitations = e.invitations or {}
  e.invitations[guid] = c.id
  io.envoyer("I;" .. c.id .. ";" .. guid)
  return true
end

-- La réponse d'un invité : accepté, il entre (si la Compagnie a encore de la place) ; la nouvelle liste part avec mon
-- état (io.maj : la Compagnie a changé).
local function reponseInvite(e, groupe, de, verbe, arg, io)
  local c, nom = e.db.compagnie, nomDans(groupe, de)
  e.invitations[de] = nil
  if verbe == "R" then
    return io.dire(nom .. (arg == "deja" and " est déjà membre d'une Compagnie." or arg == "occupe"
      and " a une fondation en cours." or " refuse d'entrer dans la Compagnie."))
  end
  if #c.membres >= ns.MAX then return io.dire(("La Compagnie a déjà %d membres : %s n'entre pas."):format(ns.MAX, nom)) end
  c.membres[#c.membres + 1] = { guid = de, nom = nom }
  c.date = io.heure()
  io.dire(nom .. " entre dans la Compagnie.")
  io.maj()
end

-- Moins de deux membres : il n'y a plus de Compagnie.
local function oter(e, i, io)
  local c = e.db.compagnie
  table.remove(c.membres, i)
  c.date = io.heure()
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
  oter(e, i, io)
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
    local nom = nomDans(groupe, de)
    if engage(e) == "occupe" then -- la fondation en cours n'est pas remplacée
      io.envoyer("R;" .. id .. ";occupe")
      return io.dire(nom .. " te propose de fonder une Compagnie : refusé d'office, " .. (e.fondation
        and "ta propre proposition est en cours." or "tu as déjà accepté celle de " .. e.proposition.nom .. "."))
    end
    e.proposition = { id = id, de = de, nom = nom, guids = guids, deja = c ~= nil }
    if c then io.envoyer("R;" .. id .. ";deja") end
    io.proposer(e.proposition)
  elseif verbe == "I" then
    if arg ~= moi then return end -- une invitation pour un autre
    local nom = nomDans(groupe, de)
    if engage(e) == "occupe" then
      io.envoyer("R;" .. id .. ";occupe")
      return io.dire(nom .. " t'invite dans sa Compagnie : refusé d'office, " .. (e.fondation
        and "ta propre proposition est en cours." or "tu as déjà accepté celle de " .. e.proposition.nom .. "."))
    end
    e.proposition = { id = id, de = de, nom = nom, invitation = true, deja = c ~= nil }
    if c then io.envoyer("R;" .. id .. ";deja") end
    io.proposer(e.proposition)
  elseif verbe == "A" or verbe == "R" then
    if c and c.id == id and e.invitations and e.invitations[de] == id then return reponseInvite(e, groupe, de, verbe, arg, io) end
    local f = e.fondation
    if not (f and f.id == id and f.reponses[de] == false) then return end
    f.reponses[de] = verbe
    if verbe == "R" then
      io.dire(nomDans(groupe, de) .. (arg == "deja" and " est déjà membre d'une Compagnie."
        or arg == "occupe" and " a déjà une fondation en cours." or " refuse."))
    end
    for _, r in pairs(f.reponses) do if r == false then return end end
    ns.cloturer(e, moi, groupe, io)
  elseif verbe == "F" then
    local p, guids = e.proposition, liste(arg)
    if c or not (p and p.id == id and p.de == de and p.accepte) or not index(guids, moi) then return end
    e.proposition = nil
    e.db.compagnie = { id = id, date = io.heure(), membres = membres(guids, groupe) }
    io.entrer()
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
      oter(e, i, io)
      io.dire((verbe == "Q" and nom .. " a quitté la Compagnie." or par .. " a retiré " .. nom .. " de la Compagnie.")
        .. (e.db.compagnie and "" or " Tu restes seul : plus de Compagnie."))
    end
    io.maj()
  end
end
