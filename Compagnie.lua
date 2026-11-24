-- Compagnie, la couche du jeu : le groupe du jeu, les messages d'add-on, la proposition, les fenêtres et la commande.
-- La logique est pure, ailleurs : membres (Membres.lua), états (Etats.lua), calcul (Calcul.lua) ; ici, seulement ce que
-- le jeu donne et ce qu'il affiche.
-- Présent : un membre connecté dans mon groupe du jeu (donné par le serveur : GUID, UnitIsConnected), ou hors du groupe
-- un membre qui nous a écrit par chuchotement depuis moins de 2 min ; sinon absent. Rien n'est deviné.
-- Messages des membres (fonder, quitter, retirer) : au groupe du jeu seulement, donc ils n'atteignent que les présents.
-- ponytail: un absent ne l'apprend pas à son retour ; l'état pourra porter la liste des membres.
-- États (Etats.lua) : au groupe du jeu quand un membre y est, en chuchotement d'add-on aux membres connectés hors du
-- groupe. Connecté : il nous a écrit par chuchotement. À la connexion, une demande d'état est chuchotée une fois à chaque
-- membre hors du groupe, puis à chaque membre hors du groupe resté muet une minute (toutes les 30 s au plus) ; pour un
-- absent, le serveur répond « Aucun joueur nommé … » : ce message est caché du chat et le membre noté hors ligne (plus
-- de chuchotement jusqu'à son prochain message). Un membre du groupe déconnecté est noté hors ligne aussi.
-- Mon journal est relu en direct par l'API, jamais sauvegardé ; le dernier état connu des autres est dans CompagnieDB.
local _, ns = ...
local AC = AzerothCommune
local PREFIXE, DELAI = "Compagnie", 60 -- délai de réponse à une proposition, en secondes
local e = { db = {} } -- l'état de Membres.lua et d'Etats.lua ; db devient CompagnieDB au chargement
-- connectes[GUID] = GetTime() de son dernier chuchotement, ou false (hors ligne) ; chuchotes[nom en minuscules] = GetTime()
-- de mon dernier chuchotement vers lui. Rien n'est sauvegardé : un /reload repart de zéro.
local connectes, chuchotes = {}, {}
local PEREMPTION, SILENCE, VEILLE = 120, 60, 30 -- secondes : présent si entendu depuis moins de PEREMPTION ; redemandé
-- après SILENCE ; la veille passe toutes les VEILLE secondes

local function moi() return UnitGUID("player") end

-- Les personnages connectés de mon groupe du jeu, moi d'abord : GUID et « Prénom Nom » donnés par le serveur.
local function groupe()
  local t = { { guid = moi(), nom = AC.Personnage().nom } }
  local raid = IsInRaid()
  for i = 1, GetNumGroupMembers() do
    local u = (raid and "raid" or "party") .. i
    local g = UnitGUID(u)
    if g and g ~= t[1].guid and UnitIsConnected(u) then
      local prenom, nom = UnitName(u)
      t[#t + 1] = { guid = g, nom = (nom and nom ~= "") and (prenom .. " " .. nom) or prenom }
    end
  end
  return t
end

local dessiner, monEtat -- plus bas
local jeu = {
  envoyer = function(texte)
    if IsInGroup() then C_ChatInfo.SendAddonMessage(PREFIXE, texte, IsInRaid() and "RAID" or "PARTY") end
  end,
  dire = function(texte) print("|cffa78ffcCompagnie :|r " .. texte) end,
  proposer = function(p) StaticPopup_Show(p.deja and "COMPAGNIE_DEJA" or "COMPAGNIE_PROPOSITION", p.nom) end,
  maj = function() ns.majCompagnie() end, -- la Compagnie a changé (fondée, quittée, un membre retiré)
  -- J'entre dans la Compagnie (#20) : ce qui est dans mon journal devient mes quêtes d'avant ; seules les remises vues
  -- à partir d'ici comptent pour une quête en avance (CompagnieDB.renduesVues, noté à QUEST_TURNED_IN).
  entrer = function()
    local avant = {}
    for id in pairs(monEtat().quetes) do avant[id] = true end
    e.db.avant, e.db.renduesVues = avant, {}
  end,
}

StaticPopupDialogs.COMPAGNIE_PROPOSITION = {
  text = "%s te propose de fonder une Compagnie avec ce groupe : vous ferez l'aventure ensemble. En être membre ?",
  button1 = "Accepter", button2 = "Refuser",
  OnAccept = function()
    local id = e.proposition and e.proposition.id
    ns.repondre(e, true, jeu)
    -- le fondateur clôt au plus tard DELAI + 5 s après sa proposition : passé ce temps, plus de F à attendre
    if id then C_Timer.After(DELAI + 10, function() ns.expirer(e, id, jeu) end) end
  end,
  OnCancel = function() ns.repondre(e, false, jeu) end, -- aussi au bout du délai
  timeout = DELAI, whileDead = true, hideOnEscape = true,
  noCancelOnReuse = true, -- une 2e proposition remplace la 1re : pas de refus envoyé pour la nouvelle
}
StaticPopupDialogs.COMPAGNIE_DEJA = {
  text = "%s te propose de fonder une Compagnie, mais tu es déjà membre d'une Compagnie : quitte-la pour en rejoindre une autre. Ta réponse est partie : non.",
  button1 = OKAY or "OK", timeout = DELAI, whileDead = true, hideOnEscape = true,
}

local function fonder()
  local g, id = groupe(), ("%s-%d"):format(moi(), GetServerTime())
  local ok, raison = ns.fonder(e, moi(), g, id, jeu)
  if not ok then return jeu.dire(raison) end
  local autres = {}
  for i = 2, #g do autres[#autres + 1] = g[i].nom end
  jeu.dire("Proposition envoyée à " .. table.concat(autres, ", ") .. " : chacun a une minute pour répondre.")
  C_Timer.After(DELAI + 5, function()
    if e.fondation and e.fondation.id == id then ns.cloturer(e, moi(), g, jeu) end
  end)
end

---------------------------------------------------------------------------------------------------
-- Présence : les membres connectés de mon groupe du jeu (et leur unité, pour IsUnitOnQuest), et ceux qui nous ont écrit
-- par chuchotement depuis moins de PEREMPTION. Un membre du groupe déconnecté n'est pas présent, et noté hors ligne.
local function frais(g) local t = connectes[g] return type(t) == "number" and GetTime() - t < PEREMPTION end
local function presence()
  local presents, unites, raid = {}, {}, IsInRaid()
  for g in pairs(connectes) do if frais(g) then presents[g] = true end end
  for i = 1, GetNumGroupMembers() do
    local u = (raid and "raid" or "party") .. i
    local g = UnitGUID(u)
    if g and UnitIsConnected(u) then presents[g], unites[g] = true, u
    elseif g then presents[g], connectes[g] = nil, false end
  end
  return presents, unites
end

---------------------------------------------------------------------------------------------------
-- Mon état, lu en direct dans mon journal (relevé du 22/11, issue #4) : info.isComplete vaut toujours nil sur Forever,
-- « finie » se lit par C_QuestLog.IsComplete ; une quête peut n'avoir aucun objectif ; le texte d'un objectif porte le
-- compte et un code de grammaire (« Raptor flagellant : 2/10 |4personnage tué:personnages tués; ») : il ne part jamais,
-- il sert à l'affichage, le compte remplacé par celui de la Compagnie.
local COMPTE = "\1" -- la place du compte dans le texte d'un objectif
local PIERRE = 6948 -- la pierre de foyer
local titres = {} -- [idQuête] = titre, vu dans mon journal pendant la session

-- Le texte du jeu, son compte exact « fait/total » remplacé par COMPTE (ni comparé, ni découpé ailleurs) ; sans compte
-- (« Sauvetage de Kernobee »), tel quel.
-- Compte exact introuvable (texte en retard, nombres illisibles) : tout « n/m » est retiré, l'affichage ne montre jamais
-- que le compte commun.
local function gabarit(texte, fait, total)
  if type(texte) ~= "string" then return nil end
  if type(fait) == "number" and type(total) == "number" then
    local a, b = texte:find(fait .. "/" .. total, 1, true)
    if a then return texte:sub(1, a - 1) .. COMPTE .. texte:sub(b + 1) end
  end
  return (texte:gsub("%s*%d+/%d+", ""):gsub("%s*:%s*$", ""))
end

local function entier(v, max) return math.min(max, math.max(0, math.floor(tonumber(v) or 0))) end

-- La zone d'une quête (#13) : l'en-tête sous lequel le journal la range (en Classic, un nom de zone ; à vérifier en jeu
-- contre GetRealZoneText).
function monEtat()
  local quetes, rendues, zone = {}, {}, nil
  for i = 1, 200 do
    local info = C_QuestLog.GetInfo(i)
    if not info then break end
    local id = info.questID
    if info.isHeader then zone = type(info.title) == "string" and info.title or nil
    elseif type(id) == "number" and id > 0 then
      local objectifs, toutFini = {}, true
      for k, o in ipairs(C_QuestLog.GetQuestObjectives(id) or {}) do
        local total = entier(o.numRequired, 99999)
        local fait = math.min(total, entier(o.numFulfilled, 99999))
        objectifs[k] = { fait = fait, total = total, texte = gabarit(o.text, o.numFulfilled, o.numRequired) }
        toutFini = toutFini and (o.finished == true or fait >= total)
      end
      local finie = C_QuestLog.IsComplete(id)
      if type(finie) ~= "boolean" then finie = toutFini end
      quetes[id] = { finie = finie, objectifs = objectifs, zone = zone, partageable = C_QuestLog.IsPushableQuest(id) == true }
      titres[id] = info.title
    end
  end
  -- Rendues : parmi les quêtes des autres membres, celles que j'ai déjà rendues (pas tout l'historique : il ne tient
  -- pas dans un message). Une remise que l'add-on n'a pas vue depuis mon entrée (#20) est d'avant : elle ne fait pas de
  -- quête en avance.
  local renduesAvant, vues = {}, e.db.renduesVues or {}
  for _, etat in pairs(e.db.etats or {}) do
    for id in pairs(etat.quetes or {}) do
      if not quetes[id] and C_QuestLog.IsQuestFlaggedCompleted(id) then
        if vues[id] then rendues[id] = true else renduesAvant[id] = true end
      end
    end
  end
  local avant = {}
  for id in pairs(e.db.avant or {}) do if quetes[id] then avant[id] = true end end
  -- Le foyer (#9) : l'auberge liée (GetBindLocation) ; l'heure de la liaison seulement si je l'ai vue se faire
  -- (HEARTHSTONE_BOUND, CompagnieDB.foyer), sinon inconnue ; l'heure serveur où ma pierre de foyer sera prête
  -- (C_Container.GetItemCooldown : en secondes de GetTime, converties), arrondie à la minute pour que l'état ne change
  -- pas à chaque lecture.
  local auberge, f = GetBindLocation(), e.db.foyer
  local debut, recharge = C_Container.GetItemCooldown(PIERRE)
  local reste = (debut or 0) > 0 and (recharge or 0) > 1.5 and debut + recharge - GetTime() or 0 -- 1.5 s : temps global
  return { niveau = UnitLevel("player"), quetes = quetes, rendues = rendues, renduesAvant = renduesAvant, avant = avant,
    ecartees = e.db.ecartees, -- les décisions de la Compagnie (#21), telles que je les connais
    auberge = auberge ~= "" and auberge or nil, liaison = f and f.auberge == auberge and f.date or nil,
    finRecharge = reste > 0 and math.ceil((GetServerTime() + reste) / 60) * 60 or nil }
end

---------------------------------------------------------------------------------------------------
-- Transport des états : au groupe du jeu si un membre y est, en chuchotement aux membres connectés hors du groupe.
-- Débit : 10 messages d'un coup au plus, puis un par seconde (la limite des messages d'add-on du client).
local file, jetons, vu, vidage = {}, 10, nil, false
local function vider()
  local t = GetTime()
  jetons = math.min(10, jetons + (t - (vu or t)))
  vu, vidage = t, false
  while #file > 0 and jetons >= 1 do
    local m = table.remove(file, 1)
    jetons = jetons - 1
    if m.cible then chuchotes[m.cible:lower()] = t end
    C_ChatInfo.SendAddonMessage(PREFIXE, m.texte, m.canal, m.cible)
  end
  if #file > 0 then vidage = true; C_Timer.After(1, vider) end
end
local function poster(texte, canal, cible)
  if #file >= 50 then return false end -- file pleine (débit tenu longtemps) : refusé, l'état repartira (Etats.lua)
  file[#file + 1] = { texte = texte, canal = canal, cible = cible }
  if not vidage then vider() end
  return true
end

-- texte aux membres : au groupe du jeu si l'un d'eux y est, en chuchotement à ceux qui nous ont écrit ; tous = aussi ceux
-- qu'on ne sait pas connectés (la demande d'état de la connexion). Rend false si la file d'envoi en a refusé un.
local function diffuser(texte, tous)
  local c = e.db.compagnie
  if not c then return end
  local _, unites = presence()
  local auGroupe, ok = false, true
  for _, m in ipairs(c.membres) do
    if m.guid ~= moi() then
      if unites[m.guid] then auGroupe = true
      elseif (tous and connectes[m.guid] ~= false) or connectes[m.guid] then
        ok = poster(texte, "WHISPER", AC.Destinataire(m.nom)) and ok
      end
    end
  end
  if auGroupe then ok = poster(texte, IsInRaid() and "RAID" or "PARTY") and ok end
  return ok
end

local redessiner, annoncer -- plus bas
local envoi = {
  programmer = function(delai, fn) C_Timer.After(delai, fn) end,
  monEtat = monEtat,
  envoyerEtat = function(texte) return diffuser(texte) end,
}
local reception = {
  -- Un état reçu : mes rendues suivent les quêtes des autres, mon état repart s'il a changé.
  maj = function() redessiner(); ns.signaler(e, false, envoi) end,
  annoncer = function(changees) annoncer(changees) end,
  demande = function() ns.signaler(e, true, envoi) end,
  maintenant = GetTime,
}

-- Le serveur répond « Aucun joueur nommé … » à un chuchotement vers un absent : caché du chat, le membre est noté hors
-- ligne. Seulement pour un nom chuchoté depuis moins de 10 s, comparé au message exact du jeu (comme le fait le chat).
local function horsLigne(_, _, msg)
  if type(msg) ~= "string" or type(ERR_CHAT_PLAYER_NOT_FOUND_S) ~= "string" then return false end
  local bas, c = msg:lower(), e.db.compagnie
  for nom, t in pairs(chuchotes) do
    if GetTime() - t < 10 and bas == ERR_CHAT_PLAYER_NOT_FOUND_S:format(nom):lower() then
      for _, m in ipairs(c and c.membres or {}) do
        if AC.Destinataire(m.nom):lower() == nom and connectes[m.guid] ~= false then connectes[m.guid] = false; redessiner() end
      end
      return true
    end
  end
  return false
end
local filtrer = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
if filtrer then filtrer("CHAT_MSG_SYSTEM", horsLigne) end

---------------------------------------------------------------------------------------------------
-- Le suivi du mode Compagnie : une fenêtre du socle en deux parties, À faire en haut, les quêtes de la Compagnie en
-- dessous, avec leur avancement commun. Personne n'est nommé, sauf un absent qui manque (« En attente de Léo ») : jamais
-- qui est en retard ni en avance. Mode éteint, une petite liste À faire reste à l'écran tant qu'il y a quelque chose à faire.
local masquageInterne = false
local function modeActif() return e.db.compagnie ~= nil and e.db.modeCompagnie ~= false end
local appliquerMode -- plus bas

local function prenom(guid)
  local c = e.db.compagnie
  local i = ns.membre(c, guid)
  return i and c.membres[i].nom:match("^(%S+)") or "?"
end

local function ligneObjectif(i, o)
  local compte = o.fait .. "/" .. o.total
  local t = o.texte
  if t and t:find(COMPTE, 1, true) then t = t:gsub(COMPTE, compte)
  elseif t then t = o.total > 1 and (t .. " : " .. compte) or t
  else t = "Objectif " .. i .. " : " .. compte end
  return (o.fait >= o.total and "|cff59cc73" or "|cffdddddd") .. "  - " .. t .. "|r"
end

-- Le filtre par zone (#13) : CompagnieDB.zoneSuivi = nil (la zone en cours, GetRealZoneText, suivie sur
-- ZONE_CHANGED_NEW_AREA), true (toutes les zones) ou le nom d'une zone ; gardé par personnage. Il ne change que
-- l'affichage : le calcul, les envois et les derniers états connus n'en savent rien. Une quête sans zone connue n'est
-- que dans « Toutes les zones ».
local zonesCompagnie, comptes = {}, {} -- au dernier dessin : les zones où la Compagnie a des quêtes (triées) et leur nombre
local function zoneEnCours() local z = GetRealZoneText() return z ~= "" and z or nil end
local function zoneAffichee() -- nil : toutes (zone en cours inconnue, pendant un chargement : toutes aussi)
  local z = e.db.zoneSuivi
  if z == nil then return zoneEnCours() end
  return z ~= true and z or nil
end
local function libelleZone()
  local z = e.db.zoneSuivi
  if z == nil then return "Zone en cours (" .. (zoneEnCours() or "?") .. ")" end
  return z == true and "Toutes les zones" or z
end
-- Les choix de la liste des zones : zone en cours, zones de la Compagnie (sauf celle où l'on est), toutes les zones.
local function choixDeZone()
  local ici = zoneEnCours()
  local choix = { { t = "Zone en cours (" .. (ici or "?") .. ")", n = ici and comptes[ici] or 0 } }
  for _, z in ipairs(zonesCompagnie) do if z ~= ici then choix[#choix + 1] = { v = z, t = z, n = comptes[z] } end end
  choix[#choix + 1] = { v = true, t = "Toutes les zones", n = comptes[true] or 0 }
  return choix
end

-- Le calcul de la Compagnie depuis mon journal et les derniers états connus (corrigés par le jeu pour mon groupe).
local function calculer()
  local presents, unites = presence()
  local liste = ns.membresDuCalcul(e.db, moi(), monEtat(), presents)
  local ids = {}
  for _, m in ipairs(liste) do for id in pairs(m.quetes or {}) do ids[#ids + 1] = id end end
  for i, m in ipairs(liste) do
    local u = m.nom ~= moi() and unites[m.nom]
    if u then
      local visible = UnitIsVisible(u)
      liste[i] = ns.corriger(m, ids, function(id)
        local sur = C_QuestLog.IsUnitOnQuest(u, id)
        if sur == false and not visible then return nil end -- trop loin : le jeu ne sait pas
        return sur
      end)
    end
  end
  return ns.calculer(liste, GetServerTime(), e.db.ecartees), presents, unites
end
local function titre(id) return titres[id] or C_QuestLog.GetTitleForQuestID(id) or ("Quête " .. id) end

-- Les quêtes écartées (#21) : « la Compagnie ne fait pas celle-là », décidé par n'importe quel membre (« Écarter », ou
-- abandonner dans le jeu) ; « Remettre » l'annule. La décision, datée, part avec mon état ; la plus récente l'emporte
-- (Etats.lua) et le chat dit qui a écarté ou remis quoi.
local function phrase(qui, d, id)
  return ("%s %s « %s »%s."):format(qui, d.ecartee and "écarté" or "remis", titre(id),
    d.ecartee and " pour la Compagnie" or " dans la Compagnie")
end
local function decider(id, ecartee)
  ns.decider(e.db, id, ecartee, prenom(moi()), math.floor(GetServerTime())) -- un entier : le format refuse le reste
  jeu.dire(phrase("Tu as", { ecartee = ecartee }, id))
  ns.signaler(e, false, envoi)
  redessiner()
end
function annoncer(changees)
  for _, d in ipairs(changees) do jeu.dire(phrase(d.par .. " a", d, d.quete)) end
end
StaticPopupDialogs.COMPAGNIE_ECARTER = {
  text = "Écarter « %s » ? La Compagnie ne la fera pas : elle sort du suivi de tous. « Remettre » dans la fenêtre de la " ..
    "Compagnie, onglet Écartées.",
  button1 = "Écarter", button2 = CANCEL or "Annuler",
  OnAccept = function(_, id) decider(id, true) end,
  timeout = 0, whileDead = true, hideOnEscape = true,
}
local function proposerEcart(id)
  local p = StaticPopup_Show("COMPAGNIE_ECARTER", titre(id))
  if p then p.data = id end
end

-- Le texte des quêtes de la Compagnie.
local function texteSuivi(calc, presents)
  local ordre, lignes = {}, {}
  local voir = zoneAffichee()
  comptes = { [true] = 0 }
  for id, q in pairs(calc.quetes) do
    comptes[true] = comptes[true] + 1
    if q.zone then comptes[q.zone] = (comptes[q.zone] or 0) + 1 end
    if not voir or q.zone == voir then ordre[#ordre + 1] = id end
  end
  zonesCompagnie = {}
  for z in pairs(comptes) do if z ~= true then zonesCompagnie[#zonesCompagnie + 1] = z end end
  table.sort(zonesCompagnie)
  table.sort(ordre, function(a, b) return titre(a) < titre(b) end)
  for _, id in ipairs(ordre) do
    local q = calc.quetes[id]
    lignes[#lignes + 1] = "|cffffd100|Hcompagnie:" .. id .. "|h" .. titre(id) .. "|h|r" -- un clic : « Écarter » (#21)
    for i, o in ipairs(q.objectifs) do lignes[#lignes + 1] = ligneObjectif(i, o) end
    local attente = {}
    for _, guid in ipairs(q.enAttente) do
      if guid ~= moi() and not presents[guid] then attente[#attente + 1] = prenom(guid) end
    end
    if q.aRendre then lignes[#lignes + 1] = "  |cff59cc73À rendre|r"
    elseif #attente > 0 then lignes[#lignes + 1] = "  |cff999999En attente de " .. table.concat(attente, ", ") .. "|r" end
  end
  -- Les quêtes à part (#20 : quêtes d'avant), sous les quêtes de la Compagnie : nommées, avec l'avancement de qui l'a ;
  -- À rendre quand il l'a finie, sans attendre personne.
  local entete = false
  for _, a in ipairs(calc.aPart) do
    if not voir or a.zone == voir then
      if not entete then lignes[#lignes + 1], entete = (#lignes > 0 and "\n" or "") .. "|cff999999À part|r", true end
      lignes[#lignes + 1] = "|cffc0c0c0" .. titre(a.quete) .. " (" .. prenom(a.membre) .. ")|r"
      for i, o in ipairs(a.objectifs) do lignes[#lignes + 1] = ligneObjectif(i, o) end
      if a.aRendre then lignes[#lignes + 1] = "  |cff59cc73À rendre|r" end
    end
  end
  if #lignes > 0 then return table.concat(lignes, "\n") end
  return voir and "|cff999999Aucune quête de la Compagnie dans cette zone.|r" or "|cff999999Aucune quête en cours.|r"
end

-- La liste À faire : mes écarts (ceux où c'est moi qui agis), un bouton chacun ; son libellé dit l'action et son état.
-- Partager : actif quand un membre qui n'a pas la quête est dans mon groupe du jeu (le jeu ne partage qu'au groupe).
-- Abandonner aussi (quête écartée, #21) : le clic du joueur, confirmé (les objets de la quête sont détruits), et lui
-- seul abandonne la quête (l'add-on n'abandonne jamais tout seul) ; s'il la garde, elle est à lui, à part.
-- Partager : un clic droit écarte la quête (#21).
-- Rendue en avance (#8) : un membre l'a rendue avant que je l'aie finie ; rien à cliquer (je la finis), sans dire qui.
-- Foyer différent (#9) : « Lie-toi à l'auberge de … » ; rien à cliquer (on se lie chez l'aubergiste).
local function abandonner(id)
  local avant = C_QuestLog.GetSelectedQuest()
  C_QuestLog.SetSelectedQuest(id)
  C_QuestLog.SetAbandonQuest()
  C_QuestLog.AbandonQuest()
  if avant then C_QuestLog.SetSelectedQuest(avant) end
end
StaticPopupDialogs.COMPAGNIE_ABANDON = {
  text = "Abandonner « %s », comme la Compagnie ? Ses objets de quête seront détruits.",
  button1 = "Abandonner", button2 = CANCEL or "Annuler",
  OnAccept = function(_, id) abandonner(id) end,
  timeout = 0, whileDead = true, hideOnEscape = true,
}
-- Mes écarts, ceux où c'est moi qui agis. Les quêtes à partager tiennent dans un seul bouton (#22), à la place de la
-- première : { type = "partager", liste = { écart, … } }.
local function mesEcarts(calc)
  local t, partager = {}, nil
  for _, x in ipairs(calc.aFaire) do
    if x.membre ~= moi() then -- celui d'un autre
    elseif x.type ~= "partager" then t[#t + 1] = x
    elseif partager then table.insert(partager.liste, x)
    else partager = { type = "partager", liste = { x } }; t[#t + 1] = partager end
  end
  return t
end
-- Partager, la suivante à chaque clic (#22) : le jeu ne partage que dans un clic (OneForAll, bloqué depuis un minuteur
-- sur Forever). La suivante : la première pas encore partagée de ce tour dont un membre qui ne l'a pas est dans mon
-- groupe (sinon la première pas encore partagée) ; tout est parti : un nouveau tour. Une quête que les autres ont prise
-- entre-temps n'est plus dans la liste : sautée. Rend l'écart, combien d'autres restent dans ce tour, et si le partage
-- peut atteindre quelqu'un (le jeu ne partage qu'au groupe).
local partagees = {} -- [idQuête] = true : partagée d'un clic pendant ce tour ; rien n'est sauvegardé
local function suivante(liste, unites)
  local libres = {}
  for _, x in ipairs(liste) do if not partagees[x.quete] then libres[#libres + 1] = x end end
  if #libres == 0 then partagees, libres = {}, liste end
  for _, x in ipairs(libres) do
    for _, guid in ipairs(x.manquants) do if unites[guid] then return x, #libres - 1, true end end
  end
  return libres[1], #libres - 1, false
end
-- Une liste de boutons dans parent (le suivi, ou la petite liste), en haut à y ; rend sa hauteur.
local function listeAFaire(parent, nom, y)
  local l = CreateFrame("Frame", nom, parent)
  l:SetPoint("TOPLEFT", 14, y)
  l:SetSize(262, 16)
  l.vide = l:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  l.vide:SetPoint("TOPLEFT")
  l.vide:SetText("Rien à faire.")
  l.boutons = {}
  return l
end
local function remplirAFaire(l, ecarts, unites)
  for i, x in ipairs(ecarts) do
    local b = l.boutons[i]
    if not b then
      b = CreateFrame("Button", l:GetName() .. i, l, "UIPanelButtonTemplate")
      b:SetSize(262, 22)
      b:SetPoint("TOPLEFT", 0, -(i - 1) * 24)
      b:GetFontString():SetPoint("LEFT", 8, 0)
      b:GetFontString():SetPoint("RIGHT", -8, 0)
      b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
      b:SetScript("OnEnter", function(self)
        if self.x.type ~= "partager" then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Clic droit : écarter cette quête pour la Compagnie", 1, 1, 1, true)
        GameTooltip:Show()
      end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
      b:SetScript("OnClick", function(self, bouton)
        if self.x.type == "avance" or self.x.type == "foyer" then return end
        if bouton == "RightButton" then
          if self.x.type == "partager" then proposerEcart(self.quete) end
          return
        end
        if self.x.type == "ecartee" then
          local p = StaticPopup_Show("COMPAGNIE_ABANDON", titre(self.x.quete))
          if p then p.data = self.x.quete end
          return
        end
        QuestLogPushQuest(C_QuestLog.GetLogIndexForQuestID(self.quete))
        partagees[self.quete] = true
        redessiner() -- le bouton passe à la suivante
      end)
      l.boutons[i] = b
    end
    b.x = x
    if x.type == "ecartee" then
      b:SetText("Abandonner aussi : " .. titre(x.quete))
      b:Enable()
    elseif x.type == "avance" then
      b:SetText("Rendue en avance : " .. titre(x.quete))
      b:Disable()
    elseif x.type == "foyer" then
      local voyelle = x.auberge:find("^[AEIOUYaeiouy]") or x.auberge:sub(1, 2) == "É"
      b:SetText("Lie-toi à l'auberge " .. (voyelle and "d'" or "de ") .. x.auberge)
      b:Disable()
    else
      local q, reste, auGroupe = suivante(x.liste, unites)
      b.quete = q.quete
      b:SetText((auGroupe and "Partager : " or "Partager en groupe : ") .. titre(q.quete) .. (reste > 0 and " (+" .. reste .. ")" or ""))
      b:SetEnabled(auGroupe)
    end
    b:Show()
  end
  for i = #ecarts + 1, #l.boutons do l.boutons[i]:Hide() end
  l.vide:SetShown(#ecarts == 0)
  l:SetHeight(#ecarts == 0 and 16 or #ecarts * 24)
  return l:GetHeight()
end

-- La pierre de la Compagnie (#9), en tête du suivi : un bouton qui utilise ma pierre de foyer, son libellé dit l'état de
-- la pierre de la Compagnie (« Foyer dans 40 min », sans dire à cause de qui ; « Rentrer au foyer » quand toutes sont
-- prêtes). Le clic utilise ma pierre même si la Compagnie n'est pas prête : l'add-on avertit, il ne bloque pas.
-- Bouton sécurisé (utiliser un objet) : enfant ou ancré au suivi, il rendrait le suivi intouchable en combat (plus de
-- hauteur mise à jour) ; il est donc enfant de UIParent, créé et posé sur le suivi hors combat.
-- ponytail: en combat il ne suit pas le suivi (déplacé, fermé) ; replacé à la sortie du combat.
local function placerPierre()
  local f, b = CompagnieSuiviFrame, CompagniePierre
  if not f or InCombatLockdown() then return end
  if not b then
    b = CreateFrame("Button", "CompagniePierre", UIParent, "UIPanelButtonTemplate,SecureActionButtonTemplate")
    b:SetSize(262, 22)
    b:SetFrameStrata("MEDIUM") -- au-dessus du suivi (LOW)
    b:SetAttribute("type", "item")
    b:SetAttribute("item", "item:" .. PIERRE)
    b:RegisterForClicks("AnyDown", "AnyUp")
    b:SetAttribute("useOnKeyDown", GetCVarBool("ActionButtonUseKeyDown"))
  end
  b:SetShown(f:IsShown())
  if not f:IsShown() then return end
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", f:GetLeft() + 14, f:GetTop() - 40)
end
local function duree(s)
  local m = math.ceil(s / 60)
  return m < 60 and m .. " min" or ("%d h %02d"):format(math.floor(m / 60), m % 60)
end

local function dessinerSuivi(calc, presents, unites)
  local f = CompagnieSuiviFrame
  if not (f and f:IsShown() and e.db.compagnie) then return end
  if not calc then calc, presents, unites = calculer() end
  local hAFaire = remplirAFaire(CompagnieSuiviAFaire, mesEcarts(calc), unites)
  CompagnieSuiviQuetes:SetText(texteSuivi(calc, presents))
  CompagnieSuiviZone:SetText(libelleZone())
  CompagnieSuiviZone:SetWidth(CompagnieSuiviZone:GetFontString():GetStringWidth() + 22)
  local h = CompagnieSuiviQuetes:GetStringHeight()
  CompagnieSuiviQuetes:GetParent():SetHeight(math.max(1, h))
  f:SetHeight(math.min(134 + hAFaire + h, UIParent:GetHeight() * 0.6))
  placerPierre()
  if CompagniePierre then CompagniePierre:SetText(calc.pierre > 0 and "Foyer dans " .. duree(calc.pierre) or "Rentrer au foyer") end
end

-- La petite liste À faire, mode Compagnie éteint : montrée quand j'ai quelque chose à faire. Sa croix la ferme jusqu'à
-- ce que la liste change (un nouvel écart, ou un écart résorbé).
local fermeeSur
local function signature(ecarts)
  local t = {}
  for i, x in ipairs(ecarts) do
    local ids = {}
    for k, p in ipairs(x.liste or {}) do ids[k] = p.quete end
    t[i] = x.type .. (x.quete or x.auberge or table.concat(ids, "+"))
  end
  return table.concat(t, ",")
end
local function dessinerPetiteListe()
  local f = CompagnieAFaireFrame
  if not e.db.compagnie or modeActif() then
    if f then masquageInterne = true; f:Hide(); masquageInterne = false end
    return
  end
  local calc, _, unites = calculer()
  local ecarts = mesEcarts(calc)
  if #ecarts == 0 or signature(ecarts) == fermeeSur then
    if f then masquageInterne = true; f:Hide(); masquageInterne = false end
    return
  end
  if not f then
    f = AC.Fenetre("CompagnieAFaireFrame", "À faire", 290, 80)
    for i, n in ipairs(UISpecialFrames) do if n == "CompagnieAFaireFrame" then table.remove(UISpecialFrames, i) break end end
    f:ClearAllPoints()
    f:SetPoint("TOPRIGHT", Minimap, "TOPLEFT", -12, -20) -- à gauche de la minicarte : le suivi du jeu est dessous
    f:SetFrameStrata("LOW")
    listeAFaire(f, "CompagniePetiteListe", -40)
    f:HookScript("OnHide", function(self)
      if not masquageInterne and not self:IsShown() then fermeeSur = signature(mesEcarts(calculer())) end
    end)
  end
  fermeeSur = nil
  f:Show()
  f:SetHeight(52 + remplirAFaire(CompagniePetiteListe, ecarts, unites))
end

-- La fenêtre de remise (#8) : quand je vais rendre une quête (QUEST_PROGRESS, QUEST_COMPLETE) dont l'avancement commun
-- n'est pas complet, un bandeau collé sous la fenêtre du jeu le dit (« La Compagnie n'a pas fini : 5/8 »). La fenêtre
-- du jeu et son bouton ne sont jamais touchés (ni masqués, ni désactivés, ni recouverts) : on peut rendre quand même.
local remise -- l'idQuête de la fenêtre de remise ouverte (GetQuestID), ou nil
local function majBandeau()
  local b = CompagnieBandeau
  local q = remise and e.db.compagnie and calculer().quetes[remise]
  if not q or q.aRendre then if b then b:Hide() end return end
  if not b then
    b = CreateFrame("Frame", "CompagnieBandeau", QuestFrame, "BackdropTemplate") -- enfant : caché avec la fenêtre
    b:SetPoint("TOPLEFT", QuestFrame, "BOTTOMLEFT", 0, -4)
    b:SetPoint("TOPRIGHT", QuestFrame, "BOTTOMRIGHT", 0, -4)
    b:SetHeight(30)
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    b:SetBackdropColor(0.25, 0.05, 0.05, 0.95)
    b:SetBackdropBorderColor(1, 0.3, 0.2, 0.8)
    b.texte = b:CreateFontString("CompagnieBandeauTexte", "OVERLAY", "GameFontNormal")
    b.texte:SetPoint("LEFT", 10, 0)
    b.texte:SetPoint("RIGHT", -10, 0)
  end
  local comptes = {}
  for _, o in ipairs(q.objectifs) do comptes[#comptes + 1] = o.fait .. "/" .. o.total end
  b.texte:SetText("La Compagnie n'a pas fini" .. (#comptes > 0 and " : " .. table.concat(comptes, ", ") or "."))
  b:Show()
end

local function titreDePartie(f, texte, y)
  local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  t:SetPoint("TOPLEFT", 14, y)
  t:SetText(texte)
  return t
end

local function ouvrirSuivi()
  if not CompagnieSuiviFrame then
    local f = AC.Fenetre("CompagnieSuiviFrame", "Compagnie", 290, 160)
    -- Un suivi reste à l'écran : Échap ne le ferme pas (la croix éteint le mode Compagnie).
    for i, n in ipairs(UISpecialFrames) do if n == "CompagnieSuiviFrame" then table.remove(UISpecialFrames, i) break end end
    f:ClearAllPoints()
    f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -40, -260) -- sous la minicarte
    f:SetFrameStrata("LOW")
    titreDePartie(f, "À faire", -70) -- au-dessus : la pierre de la Compagnie (placerPierre)
    local aFaire = listeAFaire(f, "CompagnieSuiviAFaire", -90)
    -- Le filtre par zone : le titre de la partie Quêtes est la zone affichée ; un clic ouvre juste dessous la liste des
    -- zones de la Compagnie (avec leur nombre de quêtes), un clic en choisit une et la liste se ferme.
    local z = CreateFrame("Button", "CompagnieSuiviZone", f)
    z:SetPoint("TOPLEFT", aFaire, "BOTTOMLEFT", 0, -8)
    z:SetHeight(20)
    z:SetNormalFontObject("GameFontNormal")
    z:SetHighlightFontObject("GameFontHighlight")
    z:SetText(" ")
    z:GetFontString():ClearAllPoints()
    z:GetFontString():SetPoint("LEFT")
    local fleche = z:CreateTexture(nil, "OVERLAY")
    fleche:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    fleche:SetSize(14, 14)
    fleche:SetRotation(-math.pi / 2) -- la flèche « > » tournée vers le bas
    fleche:SetPoint("LEFT", z:GetFontString(), "RIGHT", 4, 0)
    local liste = CreateFrame("Frame", "CompagnieSuiviZones", f, "BackdropTemplate")
    liste:SetPoint("TOPLEFT", z, "BOTTOMLEFT", -4, -2)
    liste:SetWidth(250)
    liste:SetFrameStrata("MEDIUM") -- au-dessus des quêtes qui défilent (le suivi est en LOW)
    liste:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    liste:SetBackdropColor(0.04, 0.04, 0.06, 1)
    liste:SetBackdropBorderColor(0.66, 0.56, 1.00, 0.5)
    liste:EnableMouse(true)
    liste:Hide()
    liste.lignes = {}
    local function remplir()
      local choix = choixDeZone()
      for i, c in ipairs(choix) do
        local l = liste.lignes[i]
        if not l then
          l = CreateFrame("Button", "CompagnieSuiviZonesLigne" .. i, liste)
          l:SetHeight(18)
          l:SetPoint("TOPLEFT", 6, -4 - (i - 1) * 18)
          l:SetPoint("RIGHT", -6, 0)
          l:SetNormalFontObject("GameFontHighlightSmall")
          l:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
          l:GetHighlightTexture():SetVertexColor(0.66, 0.56, 1.00, 0.2)
          l:SetText(" ")
          l:GetFontString():ClearAllPoints()
          l:GetFontString():SetPoint("LEFT", 14, 0)
          l:GetFontString():SetPoint("RIGHT", -28, 0)
          l:GetFontString():SetJustifyH("LEFT")
          l.n = l:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
          l.n:SetPoint("RIGHT")
          l.coche = l:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
          l.coche:SetPoint("LEFT")
          l.coche:SetText("•")
          l:SetScript("OnClick", function(self)
            e.db.zoneSuivi = self.v
            liste:Hide()
            dessinerSuivi()
          end)
          liste.lignes[i] = l
        end
        l.v = c.v
        l:SetText(c.t)
        l.n:SetText(c.n or 0)
        l.coche:SetShown(c.v == e.db.zoneSuivi)
        l:Show()
      end
      for i = #choix + 1, #liste.lignes do liste.lignes[i]:Hide() end
      liste:SetHeight(#choix * 18 + 8)
    end
    z:SetScript("OnClick", function()
      if liste:IsShown() then liste:Hide() else remplir(); liste:Show() end
    end)
    -- Beaucoup de quêtes : la fenêtre s'arrête à 60 % de l'écran et les quêtes défilent (molette).
    local defil = CreateFrame("ScrollFrame", "CompagnieSuiviDefil", f, "UIPanelScrollFrameTemplate")
    defil:SetPoint("TOPLEFT", z, "BOTTOMLEFT", 0, -4)
    defil:SetPoint("BOTTOMRIGHT", -32, 12)
    local contenu = CreateFrame("Frame", "CompagnieSuiviContenu", defil)
    contenu:SetSize(244, 1)
    defil:SetScrollChild(contenu)
    -- Le titre d'une quête de la Compagnie est un lien : un clic propose de l'écarter (#21), confirmé.
    contenu:SetHyperlinksEnabled(true)
    contenu:SetScript("OnHyperlinkClick", function(_, lien)
      local id = tonumber(tostring(lien):match("^compagnie:(%d+)$"))
      if id then proposerEcart(id) end
    end)
    contenu:SetScript("OnHyperlinkEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
      GameTooltip:SetText("Clic : écarter cette quête pour la Compagnie", 1, 1, 1, true)
      GameTooltip:Show()
    end)
    contenu:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
    local q = contenu:CreateFontString("CompagnieSuiviQuetes", "OVERLAY", "GameFontHighlightSmall")
    q:SetPoint("TOPLEFT")
    q:SetWidth(244)
    q:SetJustifyH("LEFT")
    -- Fermée par sa croix (pas quand l'interface entière est cachée, Alt-Z : elle reste « montrée ») : mode éteint.
    f:HookScript("OnShow", placerPierre)
    f:HookScript("OnDragStop", placerPierre)
    f:HookScript("OnHide", function(self)
      placerPierre()
      if masquageInterne or self:IsShown() then return end
      e.db.modeCompagnie = false
      appliquerMode()
      jeu.dire("Mode Compagnie éteint : le suivi du jeu revient. « /compagnie suivi » le rallume.")
    end)
  end
  CompagnieSuiviFrame:Show()
  dessinerSuivi()
end

-- Le suivi des quêtes du jeu, masqué en mode Compagnie (même méthode que Be a Good Pal — Minimaliste : le jeu le
-- remontre de lui-même, il est recaché aussitôt) ; rétabli comme le jeu le veut quand on éteint (voulu : ce que le jeu
-- a demandé en dernier, Show ou Hide, hors nos propres Hide).
-- En combat, ni Hide ni Show : ils relancent la mise en page des cadres gérés (ObjectiveTrackerFrame est un cadre géré
-- du bord droit, placé avec les cadres de boss sécurisés), donc seulement la transparence ; l'état voulu est appliqué à
-- la sortie du combat (PLAYER_REGEN_ENABLED).
local suiviCache, voulu, interne, accroche, differe = false, false, false, false, false
local function cacher(f) interne = true; f:Hide(); interne = false end
local function appliquerSuiviDuJeu(f)
  if InCombatLockdown() then
    differe = true
    f:SetAlpha(suiviCache and 0 or 1)
    return
  end
  differe = false
  f:SetAlpha(1)
  if suiviCache then if f:IsShown() then cacher(f) end
  elseif voulu and not f:IsShown() then f:Show() end
end
local function masquerSuiviDuJeu(oui)
  local f = ObjectiveTrackerFrame
  if not f then return end
  if not accroche then -- rien n'est écrit sur le cadre du jeu (il serait « taché »)
    accroche, voulu = true, f:IsShown()
    hooksecurefunc(f, "Show", function(self) voulu = true; if suiviCache then appliquerSuiviDuJeu(self) end end)
    hooksecurefunc(f, "SetShown", function(self, v)
      voulu = v and true or false
      if v and suiviCache then appliquerSuiviDuJeu(self) end
    end)
    hooksecurefunc(f, "Hide", function() if not interne then voulu = false end end)
  end
  if oui ~= suiviCache then
    suiviCache = oui
    appliquerSuiviDuJeu(f)
  end
end

-- Le suivi de Questie est-il actif ? Lu seulement : aucune option de Questie n'est jamais écrite.
local function suiviQuestieActif()
  local q = type(Questie) == "table" and type(Questie.db) == "table" and Questie.db.profile
  if type(q) == "table" and q.trackerEnabled == true then return true end
  local f = type(Questie_BaseFrame) == "table" and Questie_BaseFrame
  return f and f.IsShown and f:IsShown() or false
end

function appliquerMode()
  local actif = modeActif()
  masquerSuiviDuJeu(actif)
  if actif then
    ouvrirSuivi()
    if not e.db.questieSuggere and suiviQuestieActif() then
      e.db.questieSuggere = true -- une seule fois
      jeu.dire("Le suivi de Questie est actif : le mode Compagnie a le sien. Pour éviter le doublon, coupe-le dans les " ..
        "options de Questie (Compagnie n'y touche pas). Ce conseil ne reviendra pas.")
    end
  elseif CompagnieSuiviFrame then
    masquageInterne = true
    CompagnieSuiviFrame:Hide()
    masquageInterne = false
  end
  dessinerPetiteListe()
end

local function basculerMode()
  e.db.modeCompagnie = not modeActif()
  if e.db.modeCompagnie and not e.db.compagnie then
    jeu.dire("Le mode Compagnie s'allume dans une Compagnie : fonde-la d'abord.")
  end
  appliquerMode()
  if CompagnieFrame and CompagnieFrame:IsShown() then dessiner() end
end

---------------------------------------------------------------------------------------------------
-- La fenêtre, en deux onglets : Membres (présent ou absent, « Retirer » sur les autres ; « Fonder » ou « Quitter ») et
-- Écartées (#21 : les quêtes écartées, qui l'a décidé, « Remettre ») ; le mode Compagnie, son état sur son bouton.
local tableau, vide, boutonFonder, boutonQuitter, boutonMode, tableauEcartees, videEcartees, panneaux
local COLONNES = {
  { key = "nom", title = "Membre", w = 180, get = function(m) return m.nom end },
  { key = "presence", title = "Présence", w = 80, get = function(m) return m.presence end,
    fmt = function(v) return (v == "présent" and "|cff59cc73" or "|cff999999") .. v .. "|r" end },
  { key = "retirer", w = 80, button = function(m) if m.guid ~= moi() then return "Retirer" end end,
    click = function(m) ns.retirer(e, moi(), m.guid, jeu) end },
}
local COLONNES_ECARTEES = {
  { key = "titre", title = "Quête écartée", w = 180, get = function(l) return l.titre end },
  { key = "par", title = "Par", w = 80, get = function(l) return l.par end },
  { key = "remettre", w = 80, button = function() return "Remettre" end, click = function(l) decider(l.quete, false) end },
}

function dessiner()
  local c, presents, lignes = e.db.compagnie, presence(), {}
  presents[moi()] = true
  for i, m in ipairs(c and c.membres or {}) do
    lignes[i] = { guid = m.guid, nom = m.nom, presence = presents[m.guid] and "présent" or "absent" }
  end
  tableau:SetData(lignes)
  vide:SetShown(not c)
  boutonFonder:SetShown(not c)
  boutonQuitter:SetShown(c ~= nil)
  boutonMode:SetShown(c ~= nil)
  boutonMode:SetText("Mode Compagnie : " .. (modeActif() and "oui" or "non"))
  local ecartees = {}
  for id, d in pairs(e.db.ecartees or {}) do
    if d.ecartee then ecartees[#ecartees + 1] = { quete = id, titre = titre(id), par = d.par } end
  end
  table.sort(ecartees, function(a, b) return a.titre < b.titre end)
  tableauEcartees:SetData(ecartees)
  videEcartees:SetShown(#ecartees == 0)
end

local function onglet(i)
  for k, p in ipairs(panneaux) do p:SetShown(k == i) end
  PanelTemplates_SetTab(CompagnieFrame, i)
end

local function bouton(f, texte, fn, largeur, nom)
  local b = CreateFrame("Button", nom, f, "UIPanelButtonTemplate")
  b:SetSize(largeur or 100, 22)
  b:SetPoint("BOTTOMLEFT", 14, 12)
  b:SetText(texte)
  b:SetScript("OnClick", fn)
  return b
end

local function ouvrir()
  if not CompagnieFrame then
    local f = AC.Fenetre("CompagnieFrame", "Compagnie", 400, 230)
    panneaux = {}
    for i = 1, 2 do panneaux[i] = CreateFrame("Frame", nil, f); panneaux[i]:SetAllPoints() end
    local largeur
    tableau, largeur = AC.Tableau(panneaux[1], COLONNES, { name = "membres", bottom = 44 })
    f:SetWidth(largeur + 50)
    vide = panneaux[1]:CreateFontString("CompagnieVide", "OVERLAY", "GameFontHighlight")
    vide:SetPoint("TOPLEFT", 14, -70)
    vide:SetWidth(largeur)
    vide:SetJustifyH("LEFT")
    vide:SetText("Pas de Compagnie. Dans un groupe du jeu, « Fonder » la propose à chaque personnage du groupe ; " ..
      "elle a de 2 à 5 membres.")
    boutonFonder = bouton(panneaux[1], "Fonder", fonder)
    boutonQuitter = bouton(panneaux[1], "Quitter", function() ns.quitter(e, jeu) end)
    boutonMode = bouton(f, "Mode Compagnie", basculerMode, 170, "CompagnieModeBouton")
    boutonMode:ClearAllPoints()
    boutonMode:SetPoint("BOTTOMRIGHT", -14, 12)
    tableauEcartees = AC.Tableau(panneaux[2], COLONNES_ECARTEES, { name = "ecartees", bottom = 44 })
    videEcartees = panneaux[2]:CreateFontString("CompagnieEcarteesVide", "OVERLAY", "GameFontHighlight")
    videEcartees:SetPoint("TOPLEFT", 14, -70)
    videEcartees:SetWidth(largeur)
    videEcartees:SetJustifyH("LEFT")
    videEcartees:SetText("Aucune quête écartée. Pour écarter une quête : clic sur son titre dans le suivi, ou clic " ..
      "droit sur « Partager ».")
    f.Tabs = {}
    for i, nom in ipairs({ "Membres", "Écartées" }) do
      local t = CreateFrame("Button", "CompagnieFrameTab" .. i, f, "PanelTabButtonTemplate")
      t:SetID(i)
      t:SetText(nom)
      t:SetScript("OnClick", function() onglet(i) end)
      f.Tabs[i] = t
    end
    f.Tabs[1]:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 10, 2)
    PanelTemplates_SetNumTabs(f, 2)
    onglet(1)
  end
  CompagnieFrame:Show()
  dessiner()
end

function redessiner()
  if CompagnieFrame and CompagnieFrame:IsShown() then dessiner() end
  dessinerSuivi()
  dessinerPetiteListe()
  if remise then majBandeau() end
end
-- Mon journal change par rafales (QUEST_LOG_UPDATE) : le suivi est redessiné une fois par rafale.
local dessinPrevu = false
local function redessinerBientot()
  if dessinPrevu then return end
  dessinPrevu = true
  C_Timer.After(0.5, function() dessinPrevu = false; redessiner() end)
end

-- La Compagnie a changé : le mode suit, et mon état part (forcé : de nouveaux membres ne l'ont pas).
function ns.majCompagnie()
  if not e.db.compagnie then -- plus de Compagnie : derniers états, écartées, quêtes d'avant et remises vues oubliés
    e.db.etats, e.db.ecartees, e.db.avant, e.db.renduesVues = nil, nil, nil, nil
  end
  appliquerMode()
  redessiner()
  ns.signaler(e, true, envoi)
end

-- À la connexion : demander l'état de chacun (au groupe, et chuchoté une fois à chaque membre hors du groupe) et
-- envoyer le mien.
local function connexion()
  appliquerMode() -- le suivi de Questie se crée un peu après l'entrée en jeu
  local c = e.db.compagnie
  if not c then return end
  diffuser("D;" .. c.id, true)
  ns.signaler(e, true, envoi)
end

-- La veille, toutes les VEILLE secondes : un membre hors du groupe resté muet SILENCE secondes reçoit une demande d'état
-- (sa réponse le garde présent ; absent, le serveur répond « Aucun joueur nommé » et il est noté hors ligne) ; la
-- présence est redessinée (un membre muet depuis PEREMPTION devient absent).
local veille = false
local function veiller()
  local c, t = e.db.compagnie, GetTime()
  if c then
    local _, unites = presence()
    for _, m in ipairs(c.membres) do
      local vu = connectes[m.guid]
      if m.guid ~= moi() and not unites[m.guid] and type(vu) == "number" and t - vu >= SILENCE then
        poster("D;" .. c.id, "WHISPER", AC.Destinataire(m.nom))
      end
    end
    redessiner()
  end
  C_Timer.After(VEILLE, veiller)
end

-- Mes abandons (#21) : abandonner une quête dans le jeu l'écarte pour la Compagnie (« la Compagnie ne fait pas
-- celle-là »). Vu au clic du joueur (le jeu appelle C_QuestLog.SetAbandonQuest puis AbandonQuest), rien n'est deviné.
-- Déjà écartée (« Abandonner aussi ») : rien de plus ; ma quête d'avant (#20), à moi seul : seulement oubliée.
-- Accroché une fois, au chargement (ADDON_LOADED).
local aAbandonner, abandonsAccroches
local function accrocherAbandons()
  if abandonsAccroches or not C_QuestLog.AbandonQuest then return end -- ponytail: le simulateur n'a pas ces fonctions
  abandonsAccroches = true
  hooksecurefunc(C_QuestLog, "SetAbandonQuest", function() aAbandonner = C_QuestLog.GetAbandonQuest() end)
  hooksecurefunc(C_QuestLog, "AbandonQuest", function()
    local id = aAbandonner
    aAbandonner = nil
    if not (e.db.compagnie and type(id) == "number" and id > 0) then return end
    local d = e.db.ecartees and e.db.ecartees[id]
    if d and d.ecartee then return end
    if e.db.avant and e.db.avant[id] and not calculer().quetes[id] then
      e.db.avant[id] = nil
      return redessinerBientot()
    end
    decider(id, true)
  end)
end

---------------------------------------------------------------------------------------------------
-- Messages d'add-on. Au groupe du jeu : d'un expéditeur que le serveur y nomme (son GUID vient du groupe) ; en
-- chuchotement : d'un membre, reconnu à son nom « Prénom Nom » donné par le serveur, et seulement pour les états.
local MONJOURNAL = { QUEST_LOG_UPDATE = true, QUEST_TURNED_IN = true, PLAYER_LEVEL_UP = true, UNIT_QUEST_LOG_CHANGED = true,
  BAG_UPDATE_COOLDOWN = true, HEARTHSTONE_BOUND = true }
local cadre = CreateFrame("Frame", "CompagnieMessages")
for _, ev in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE", "QUEST_LOG_UPDATE",
  "QUEST_ACCEPTED", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP", "UNIT_QUEST_LOG_CHANGED", "PLAYER_REGEN_ENABLED", "ZONE_CHANGED_NEW_AREA",
  "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_DETAIL", "QUEST_GREETING", "QUEST_FINISHED", "BAG_UPDATE_COOLDOWN",
  "HEARTHSTONE_BOUND" }) do cadre:RegisterEvent(ev) end
cadre:SetScript("OnEvent", function(_, ev, a1, texte, canal, expediteur)
  if ev == "ADDON_LOADED" then
    if a1 == "Compagnie" then
      CompagnieDB = CompagnieDB or {}
      e.db, e.moi = CompagnieDB, moi()
      connectes, chuchotes = {}, {} -- la présence repart de zéro (en jeu, un /reload efface tout l'état Lua)
      accrocherAbandons()
      -- Pas de fenêtre ici : à ADDON_LOADED, les add-ons chargés après nous (Diagnostic, qui donne sa loupe aux
      -- fenêtres du socle) ne le sont pas encore. PLAYER_ENTERING_WORLD applique le mode.
      if not veille then veille = true; C_Timer.After(VEILLE, veiller) end
    end
  elseif ev == "PLAYER_ENTERING_WORLD" then
    e.moi = moi()
    appliquerMode()
    if a1 or texte then C_Timer.After(3, connexion) end -- connexion ou /reload, pas un écran de chargement
  elseif ev == "GROUP_ROSTER_UPDATE" or ev == "ZONE_CHANGED_NEW_AREA" then
    redessiner()
  elseif ev == "PLAYER_REGEN_ENABLED" then
    if differe and ObjectiveTrackerFrame then appliquerSuiviDuJeu(ObjectiveTrackerFrame) end
    placerPierre()
  elseif ev == "QUEST_PROGRESS" or ev == "QUEST_COMPLETE" then
    remise = GetQuestID()
    majBandeau()
  elseif ev == "QUEST_DETAIL" or ev == "QUEST_GREETING" or ev == "QUEST_FINISHED" then
    remise = nil
    majBandeau()
  elseif ev == "QUEST_ACCEPTED" then
    -- Forever : (questID) ; d'autres clients Classic : (index, questID).
    local id = type(texte) == "number" and texte or a1
    if e.db.avant and id then e.db.avant[id] = nil end -- reprise après l'entrée : une quête de la Compagnie
  elseif MONJOURNAL[ev] then
    -- Ma liaison (#9) : notée avec l'heure serveur, vue par le jeu (rien n'est deviné d'une liaison faite add-on éteint).
    if ev == "HEARTHSTONE_BOUND" then e.db.foyer = { auberge = GetBindLocation(), date = GetServerTime() } end
    -- Une remise vue depuis mon entrée (#20) : elle peut faire une quête en avance chez les autres.
    if ev == "QUEST_TURNED_IN" and e.db.compagnie and type(a1) == "number" then
      e.db.renduesVues = e.db.renduesVues or {}
      e.db.renduesVues[a1] = true
    end
    if e.db.compagnie then ns.signaler(e, false, envoi); redessinerBientot() end
  elseif a1 == PREFIXE and type(texte) == "string" and type(expediteur) == "string" then
    local nom = AC.Destinataire(expediteur)
    if canal == "PARTY" or canal == "RAID" then
      local g = groupe()
      for _, p in ipairs(g) do
        if p.nom == nom then
          if ns.recevoirEtat(e, p.guid, texte, reception) then return end
          return ns.recevoir(e, moi(), g, p.guid, texte, jeu)
        end
      end
    elseif canal == "WHISPER" then
      local c = e.db.compagnie
      for _, m in ipairs(c and c.membres or {}) do
        if m.nom == nom and m.guid ~= moi() then
          local nouveau = not frais(m.guid)
          connectes[m.guid] = GetTime()
          if nouveau then -- il vient de se montrer connecté : il n'a peut-être pas mon état
            redessiner()
            ns.signaler(e, true, envoi)
          end
          return ns.recevoirEtat(e, m.guid, texte, reception)
        end
      end
    end
  end
end)
C_ChatInfo.RegisterAddonMessagePrefix(PREFIXE)

AC.Regrouper({ nom = "Compagnie", dossier = "Compagnie", icone = "Interface\\Icons\\INV_Misc_Note_01", ouvrir = ouvrir })

SLASH_COMPAGNIE1 = "/compagnie"
SlashCmdList.COMPAGNIE = function(msg)
  local cmd = (msg or ""):match("^%s*(%S*)"):lower()
  if cmd == "fonder" then return fonder() end
  if cmd == "quitter" then return ns.quitter(e, jeu) end
  if cmd == "suivi" then return basculerMode() end
  ouvrir()
end
