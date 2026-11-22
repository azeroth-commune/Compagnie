-- Compagnie, les états des membres : encodage, réception, dernier état connu, envoi regroupé. La logique seule, sans
-- aucun appel à l'API du jeu (vérifié par check.lua) ; Compagnie.lua lit mon journal en direct et transporte les messages.
-- Un état : { niveau = 35, quetes = { [idQuête] = { finie = false, objectifs = { { fait = 2, total = 10 }, … } } },
--             rendues = { [idQuête] = true } }
-- Le texte des objectifs ne part jamais (il porte un code de grammaire du jeu, « |4…; ») : seulement les nombres, dans
-- l'ordre des objectifs ; chacun retrouve le texte dans son propre journal (Calcul.lua le prend chez qui l'a).
-- Corps encodé : « niveau#quête;quête…#rendue,rendue… », une quête « id:finie(0|1)[:fait/total…] », ids triés.
-- Messages d'add-on (préfixe Compagnie) : « E;idCompagnie;envoi/i/n;morceau » (un état en n morceaux bornés à 255
-- octets) et « D;idCompagnie » (demande d'état). L'expéditeur (de) est le GUID que Compagnie.lua tient du serveur.
-- Donnée reçue entre membres (CONTEXT-MAP) : servie telle quelle, mais lue strictement (un champ mal formé et tout l'état
-- est rejeté ; rien n'est jamais exécuté ni interprété) et bornée (taille, nombre de morceaux, débit par expéditeur).
local _, ns = ...
local MAX_QUETES, MAX_OBJECTIFS, MAX_RENDUES, MAX_MORCEAUX, DEBIT = 60, 20, 300, 10, 60 -- DEBIT : messages / minute
ns.DELAI_ENVOI = 3 -- secondes : une rafale d'événements part en un seul envoi

-- Les morceaux de s séparés par sep (un caractère), vides compris.
local function couper(s, sep)
  local t, i = {}, 1
  while true do
    local j = s:find(sep, i, true)
    t[#t + 1] = s:sub(i, (j or 0) - 1)
    if not j then return t end
    i = j + 1
  end
end
local function entier(s, max)
  local n = s:match("^%d%d?%d?%d?%d?%d?%d?%d?%d?%d?$") and tonumber(s)
  return n and n <= max and n or nil
end
local function trier(t)
  local ids = {}
  for id in pairs(t or {}) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids
end

function ns.encoder(etat)
  local quetes, rendues = {}, {}
  for _, id in ipairs(trier(etat.quetes)) do
    local q, t = etat.quetes[id], { id, etat.quetes[id].finie and 1 or 0 }
    for _, o in ipairs(q.objectifs or {}) do t[#t + 1] = o.fait .. "/" .. o.total end
    quetes[#quetes + 1] = table.concat(t, ":")
  end
  for _, id in ipairs(trier(etat.rendues)) do rendues[#rendues + 1] = id end
  return (etat.niveau or 0) .. "#" .. table.concat(quetes, ";") .. "#" .. table.concat(rendues, ",")
end

-- L'état, ou nil au moindre champ mal formé.
function ns.decoder(corps)
  local f = couper(corps, "#")
  local niveau = #f == 3 and entier(f[1], 200)
  if not niveau or niveau < 1 then return end
  local etat = { niveau = niveau, quetes = {}, rendues = {} }
  local liste = f[2] == "" and {} or couper(f[2], ";")
  if #liste > MAX_QUETES then return end
  for _, q in ipairs(liste) do
    local c = couper(q, ":")
    local id = entier(c[1], 9999999999)
    if not id or id < 1 or etat.quetes[id] or (c[2] ~= "0" and c[2] ~= "1") or #c - 2 > MAX_OBJECTIFS then return end
    local objectifs = {}
    for k = 3, #c do
      local a, b = c[k]:match("^(%d+)/(%d+)$")
      a, b = a and entier(a, 99999), b and entier(b, 99999)
      if not (a and b) or a > b then return end
      objectifs[k - 2] = { fait = a, total = b }
    end
    etat.quetes[id] = { finie = c[2] == "1", objectifs = objectifs }
  end
  liste = f[3] == "" and {} or couper(f[3], ",")
  if #liste > MAX_RENDUES then return end
  for _, r in ipairs(liste) do
    local id = entier(r, 9999999999)
    if not id or id < 1 then return end
    etat.rendues[id] = true
  end
  return etat
end

-- Les messages d'un envoi (numéro 1-99) : chacun tient dans les 255 octets d'un message d'add-on.
function ns.morceaux(id, corps, envoi)
  local taille = 255 - #("E;" .. id .. ";99/10/10;")
  local n, t = math.max(1, math.ceil(#corps / taille)), {}
  if n > MAX_MORCEAUX then return t end -- ponytail: un journal plein tient en ~5 morceaux ; au-delà, rien ne part
  for i = 1, n do t[i] = ("E;%s;%d/%d/%d;%s"):format(id, envoi, i, n, corps:sub((i - 1) * taille + 1, i * taille)) end
  return t
end

-- Un message E ou D reçu de de (GUID). e = { db = CompagnieDB, moi = mon GUID } ; io = { maj = fn(), demande = fn(de),
-- maintenant = fn() -> secondes }. Rend true si le message est un message d'état (traité ou ignoré).
function ns.recevoirEtat(e, de, texte, io)
  local verbe, id, reste = texte:match("^([ED]);([^;]+);?(.*)$")
  if not verbe then return false end
  local c = e.db.compagnie
  if de == e.moi or not (c and c.id == id and ns.membre(c, de)) then return true end -- un non-membre : ignoré
  e.debit = e.debit or {}
  local d, t = e.debit[de], io.maintenant()
  if not d or t - d.debut >= 60 then d = { debut = t, n = 0 }; e.debit[de] = d end
  d.n = d.n + 1
  if d.n > DEBIT then return true end
  if verbe == "D" then io.demande(de); return true end
  local envoi, i, n, morceau = reste:match("^(%d%d?)/(%d%d?)/(%d%d?);(.*)$")
  envoi, i, n = tonumber(envoi), tonumber(i), tonumber(n)
  if not envoi or envoi < 1 or n < 1 or n > MAX_MORCEAUX or i < 1 or i > n then return true end
  e.tampons = e.tampons or {}
  local b = e.tampons[de]
  if i == 1 then b = { envoi = envoi, n = n }; e.tampons[de] = b end
  if not (b and b.envoi == envoi and b.n == n and #b == i - 1) then e.tampons[de] = nil; return true end
  b[i] = morceau
  if i < n then return true end
  e.tampons[de] = nil
  local etat = ns.decoder(table.concat(b))
  if not etat then return true end
  e.db.etats = e.db.etats or {}
  e.db.etats[de] = etat -- le dernier état connu : une donnée propre, sauvegardée
  io.maj()
  return true
end

-- Les membres pour ns.calculer, dans l'ordre de la Compagnie : moi avec mon état lu en direct, les autres avec leur
-- dernier état connu (un membre jamais entendu : sans quête ni niveau, donc jamais à rendre sans lui) ; nom = le GUID.
-- presents = { [GUID] = true } ; les autres sont absents. Les états d'anciens membres sont oubliés.
function ns.membresDuCalcul(db, moi, monEtat, presents)
  local c, liste = db.compagnie, {}
  if not c then db.etats = nil; return liste end
  for guid in pairs(db.etats or {}) do if not ns.membre(c, guid) then db.etats[guid] = nil end end
  for i, m in ipairs(c.membres) do
    local etat = m.guid == moi and monEtat or (db.etats and db.etats[m.guid]) or { quetes = {} }
    liste[i] = { nom = m.guid, niveau = etat.niveau, quetes = etat.quetes, rendues = etat.rendues,
      absent = m.guid ~= moi and not presents[m.guid] }
  end
  return liste
end

-- L'état d'un membre présent dans mon groupe, corrigé par le jeu (surQuete(id) = IsUnitOnQuest : true, false ou nil
-- quand le jeu ne sait pas) sur les quêtes ids : une copie, l'état gardé n'est pas touché.
function ns.corriger(etat, ids, surQuete)
  local quetes = {}
  for id, q in pairs(etat.quetes or {}) do quetes[id] = q end
  for _, id in ipairs(ids) do
    local sur = surQuete(id)
    if sur == false then quetes[id] = nil
    elseif sur == true and not quetes[id] then quetes[id] = { finie = false, objectifs = {} } end
  end
  return { nom = etat.nom, niveau = etat.niveau, quetes = quetes, rendues = etat.rendues, absent = etat.absent }
end

-- Un changement de mon état (force : une demande d'état, il part même inchangé). Une rafale d'événements ne programme
-- qu'un envoi, ns.DELAI_ENVOI plus tard, avec l'état lu à ce moment ; un état inchangé ne repart pas.
-- io = { programmer = fn(délai, fn), monEtat = fn() -> état, envoyerEtat = fn(message) }.
function ns.signaler(e, force, io)
  e.force = e.force or force
  if e.prevu then return end
  e.prevu = true
  io.programmer(ns.DELAI_ENVOI, function()
    e.prevu = false
    local c = e.db.compagnie
    if not c then return end
    local corps = ns.encoder(io.monEtat())
    if corps == e.dernier and not e.force then return end
    e.force, e.dernier, e.envoi = false, corps, (e.envoi or 0) % 99 + 1
    for _, m in ipairs(ns.morceaux(c.id, corps, e.envoi)) do io.envoyerEtat(m) end
  end)
end
