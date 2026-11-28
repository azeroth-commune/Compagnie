-- Compagnie, la couche du jeu : le groupe du jeu, les messages d'add-on, la proposition, les fenêtres et la commande.
-- La logique est pure, ailleurs : membres (Membres.lua), états (Etats.lua), calcul (Calcul.lua) ; ici, seulement ce que
-- le jeu donne et ce qu'il affiche.
-- Présent : un membre connecté dans mon groupe du jeu (donné par le serveur : GUID, UnitIsConnected), ou hors du groupe
-- un membre qui nous a écrit par chuchotement depuis moins de 2 min ; sinon absent. Rien n'est deviné.
-- Messages des membres (fonder, inviter, quitter, retirer) : au groupe du jeu seulement, donc ils n'atteignent que les
-- présents ; la liste des membres part aussi avec l'état (#23) : un absent apprend la plus récente à son retour.
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
local function prenom(guid)
  local c = e.db.compagnie
  local i = ns.membre(c, guid)
  return i and c.membres[i].nom:match("^(%S+)") or "?"
end

-- Ma version (Etats.lua, ns.noterVersion) : l'étiquette que le packager met dans le TOC (@project-version@) ; « dev »
-- depuis le dépôt, où le TOC garde le motif.
local metadonnee = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
e.version = metadonnee("Compagnie", "Version") or ""
if not e.version:match("^[%w%.%-]+$") then e.version = "dev" end
local function demandeEtat() return ("D;%s;%s"):format(e.db.compagnie.id, e.version) end

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
  proposer = function(p)
    StaticPopup_Show(p.deja and "COMPAGNIE_DEJA" or p.invitation and "COMPAGNIE_INVITATION" or "COMPAGNIE_PROPOSITION", p.nom)
  end,
  heure = function() return math.floor(GetServerTime()) end, -- la date de la liste des membres (#23)
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
    -- le fondateur clôt au plus tard DELAI + 5 s après sa proposition (l'invitation : l'état de qui invite part 3 s
    -- après l'acceptation) : passé ce temps, plus rien à attendre
    if id then C_Timer.After(DELAI + 10, function() ns.expirer(e, id, jeu) end) end
  end,
  OnCancel = function() ns.repondre(e, false, jeu) end, -- aussi au bout du délai
  timeout = DELAI, whileDead = true, hideOnEscape = true,
  noCancelOnReuse = true, -- une 2e proposition remplace la 1re : pas de refus envoyé pour la nouvelle
}
StaticPopupDialogs.COMPAGNIE_INVITATION = {} -- inviter (#23) : la même réponse que la fondation
for k, v in pairs(StaticPopupDialogs.COMPAGNIE_PROPOSITION) do StaticPopupDialogs.COMPAGNIE_INVITATION[k] = v end
StaticPopupDialogs.COMPAGNIE_INVITATION.text = "%s t'invite dans sa Compagnie : vous ferez l'aventure ensemble. En être membre ?"
StaticPopupDialogs.COMPAGNIE_DEJA = {
  text = "%s te propose une Compagnie, mais tu es déjà membre d'une Compagnie : quitte-la pour en rejoindre une autre. Ta réponse est partie : non.",
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

-- Combien j'ai, dans mes sacs, de l'objet d'un objectif (par son nom, ns.libelle), s'il s'échange ; nil sinon. Le jeu
-- borne le compte d'un objectif au total : le surplus qu'un autre membre peut recevoir ne se lit que dans les sacs.
-- ponytail: seulement un objet jamais lié (bindType 0) ; un objet de quête lié (4) ou lié quand ramassé (1) ne
-- s'échange pas, un « lié quand équipé » est écarté par prudence.
local function stockEchangeable(nom)
  if not nom or select(14, C_Item.GetItemInfo(nom)) ~= 0 then return nil end
  local n = C_Item.GetItemCount(nom)
  return type(n) == "number" and n > 0 and n or nil
end

-- Mes prérequis manquants pour la zone de la Compagnie (#27), calculés en direct (rendue : IsQuestFlaggedCompleted ; ma
-- race et ma classe) : choisir la zone du rendez-vous montre tout de suite ce qu'il faut faire avant de partir.
local function mesPrerequis()
  local zc = e.db.zoneCompagnie
  if not zc then return nil end
  local q = (AC:Lire("base des quêtes")) or {}
  return { zone = zc.zone, manquants = ns.prerequisManquants(zc.zone, q, C_QuestLog.IsQuestFlaggedCompleted,
    select(3, UnitRace("player")), select(3, UnitClass("player")), ns.ecarteesEffectives(e.db.ecartees, q)) }
end

-- Mes quêtes rendues de la zone de la Compagnie (#34), pour l'arbre des chaînes des autres : celles de l'arbre
-- (ns.quetesDeLaZone) que le jeu dit faites, vues par l'add-on ou d'avant mon entrée.
-- ponytail: toute la base parcourue à chaque lecture de mon état, comme mesPrerequis.
local function mesRenduesZone()
  local zc = e.db.zoneCompagnie
  if not zc then return nil end
  local t = {}
  for id in pairs(ns.quetesDeLaZone((AC:Lire("base des quêtes")) or {}, zc.zone)) do
    if C_QuestLog.IsQuestFlaggedCompleted(id) then t[id] = true end
  end
  return { zone = zc.zone, quetes = t }
end

-- La zone d'une quête (#13) : l'en-tête sous lequel le journal la range (en Classic, un nom de zone ; à vérifier en jeu
-- contre GetRealZoneText).
function monEtat()
  ns.purger(e.db, GetServerTime()) -- les vieilles remises ne partent plus (Etats.lua)
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
        objectifs[k] = { fait = fait, total = total, texte = gabarit(o.text, o.numFulfilled, o.numRequired),
          stock = o.type == "item" and stockEchangeable(ns.libelle(o.text)) or nil }
        toutFini = toutFini and (o.finished == true or fait >= total)
      end
      local finie = C_QuestLog.IsComplete(id)
      if type(finie) ~= "boolean" then finie = toutFini end
      local partageable = C_QuestLog.IsPushableQuest(id) == true
      quetes[id] = { finie = finie, objectifs = objectifs, zone = zone, partageable = partageable,
        personnelle = e.db.personnelles and e.db.personnelles[id], -- marquée personnelle à la main (#7)
        -- Où je l'ai prise (#6), pour qui doit aller la chercher : pas pour une quête d'avant (aucun écart).
        origine = not partageable and not (e.db.avant and e.db.avant[id]) and e.db.origines and e.db.origines[id] or nil }
      titres[id] = info.title
    end
  end
  for id in pairs(e.db.origines or {}) do -- rendue : son origine ne sert plus (#6)
    if not quetes[id] and C_QuestLog.IsQuestFlaggedCompleted(id) then e.db.origines[id] = nil end
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
  return { niveau = UnitLevel("player"), race = select(3, UnitRace("player")), classe = select(3, UnitClass("player")), -- #7
    quetes = quetes, rendues = rendues, renduesAvant = renduesAvant, avant = avant,
    ecartees = e.db.ecartees, -- les décisions de la Compagnie (#21), telles que je les connais
    zoneCompagnie = e.db.zoneCompagnie, -- la zone de la Compagnie (#24), telle que je la connais
    prerequis = mesPrerequis(), -- mes prérequis manquants pour cette zone (#27)
    renduesZone = mesRenduesZone(), -- mes quêtes rendues de cette zone (#34)
    liste = e.db.compagnie and { date = e.db.compagnie.date or 0, membres = e.db.compagnie.membres }, -- #23
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
  -- file pleine (débit tenu longtemps) : refusé, l'état repartira (Etats.lua) ; 60 : un état de 14 morceaux à 4 membres
  if #file >= 60 then return false end
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

local redessiner, annoncer, annoncerZone, changerListe -- plus bas
local envoi = {
  programmer = function(delai, fn) C_Timer.After(delai, fn) end,
  monEtat = monEtat,
  envoyerEtat = function(texte) return diffuser(texte) end,
  trop = function()
    jeu.dire("Ton état ne tient plus dans un envoi (journal plein, beaucoup de quêtes écartées) : les autres membres " ..
      "ne le reçoivent plus. Rends ou abandonne quelques quêtes.")
  end,
}
local reception = {
  -- Un état reçu : mes rendues suivent les quêtes des autres, mon état repart s'il a changé.
  maj = function() redessiner(); ns.signaler(e, false, envoi) end,
  annoncer = function(changees) annoncer(changees) end,
  zone = function(z) annoncerZone(z) end,
  liste = function(l) changerListe(l) end,
  demande = function() ns.signaler(e, true, envoi) end,
  programmer = function(delai, fn) C_Timer.After(delai, fn) end,
  envoyerVersion = function() if e.db.compagnie then diffuser(demandeEtat()) end end,
  incompatible = function(de, sa)
    local maj = " (client CurseForge : Compagnie en version Beta)."
    jeu.dire(sa and ("%s a Compagnie %s, toi %s : vos états ne se lisent plus. La plus ancienne se met à jour%s")
      :format(prenom(de), sa, e.version, maj)
      or ("%s a une version de Compagnie plus ancienne que la tienne : son état ne se lit plus tant qu'elle n'est pas "
      .. "mise à jour%s"):format(prenom(de), maj))
  end,
  maintenant = GetTime,
  heure = GetServerTime,
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

-- Des membres (GUID), nommés par leur prénom ; moi : « toi ».
local function noms(guids)
  local t = {}
  for i, g in ipairs(guids) do t[i] = g == moi() and "toi" or prenom(g) end
  return table.concat(t, ", ")
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

-- Les membres du calcul : mon journal et les derniers états connus, corrigés par le jeu pour mon groupe.
local function membresDuJeu()
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
  return liste, presents, unites
end
-- La base des quêtes du socle (souscrite au chargement) : { [id] = { nom, zone, suites, … } }, vide tant qu'elle manque.
local function base() return (AC:Lire("base des quêtes")) or {} end
-- Le calcul de la Compagnie.
-- Le texte d'un objectif qui manque (une quête que je n'ai pas : il ne part pas avec les états) : le jeu le donne aussi
-- pour une quête hors de mon journal (relevé du 28/11 : GetQuestObjectives(92517), quête de l'autre membre seulement →
-- « Bandit des hautes-terres : 0/10 |4…; »). Les objectifs à part sont ceux du dernier état connu : copiés, pas touchés.
local function nommer(calc)
  local function remplir(id, objectifs)
    local jeu, copie = nil, {}
    for i, o in ipairs(objectifs) do
      copie[i] = o
      if not o.texte then
        jeu = jeu or C_QuestLog.GetQuestObjectives(id) or {}
        local g = jeu[i]
        if g then copie[i] = { fait = o.fait, total = o.total, stock = o.stock, texte = gabarit(g.text, g.numFulfilled, g.numRequired) } end
      end
    end
    return copie
  end
  for id, q in pairs(calc.quetes) do q.objectifs = remplir(id, q.objectifs) end
  for _, a in ipairs(calc.aPart) do a.objectifs = remplir(a.quete, a.objectifs) end
end
local function calculer()
  local liste, presents, unites = membresDuJeu()
  local zc = e.db.zoneCompagnie
  local calc = ns.calculer(liste, GetServerTime(), e.db.ecartees, base(), zc and zc.zone, e.db.niveauxRequis)
  nommer(calc)
  return calc, presents, unites
end
local function titre(id)
  local q = titres[id] or C_QuestLog.GetTitleForQuestID(id)
  return q or (base()[id] or {}).nom or ("Quête " .. id)
end

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

-- La zone de la Compagnie (#24) : choisie par n'importe quel membre dans le menu de son bouton, en tête du suivi (les
-- zones de la base des quêtes, celles dont la Compagnie a le niveau d'entrée d'abord, les autres en grisé, choisissables).
-- Le choix, daté, part avec mon état ; le plus récent l'emporte (Etats.lua) et le chat le dit. Entrer dans une autre zone
-- de la base : une ligne dans le chat propose « /compagnie zone », une fois par zone et par session ; rien ne change seul.
-- Indépendante du filtre d'affichage par zone (#13), qui reste personnel.
local function nomZone(z) return C_Map.GetAreaInfo(z) or ("Zone " .. z) end
-- Une carte (uiMapID) et un endroit dessus (#6) : « , Forêt d'Elwynn (42, 65) », vide sans carte.
local function nomCarte(c) local i = C_Map.GetMapInfo(c) return i and i.name or ("carte " .. c) end
local function lieu(o)
  if not (o and o.carte) then return "" end
  return ", " .. nomCarte(o.carte) .. (o.x and o.y and (" (%d, %d)"):format(math.floor(o.x + 0.5), math.floor(o.y + 0.5)) or "")
end
local function choisirZone(z)
  e.db.zoneCompagnie = { zone = z, date = math.floor(GetServerTime()), par = prenom(moi()) }
  jeu.dire(("Tu as choisi %s pour la Compagnie."):format(nomZone(z)))
  ns.signaler(e, false, envoi)
  redessiner()
end
function annoncerZone(z) jeu.dire(("%s a choisi %s pour la Compagnie."):format(z.par, nomZone(z.zone))) end
local function zoneDe(nom) -- l'areaID d'une zone de la base, d'après son nom (GetRealZoneText), ou nil
  for _, z in ipairs(ns.zones(base(), 1)) do if nomZone(z.zone) == nom then return z.zone end end
end
local function choisirZoneEnCours()
  local z = e.db.compagnie and zoneDe(zoneEnCours())
  if not e.db.compagnie then return jeu.dire("Pas de Compagnie : fonde-la d'abord.") end
  if not z then return jeu.dire("Cette zone n'est pas dans la base des quêtes : choisis la zone dans le suivi.") end
  choisirZone(z)
end
local suggerees = {} -- [nom de zone] = true : proposée pendant cette session
local function suggererZone()
  local ici, zc = zoneEnCours(), e.db.zoneCompagnie
  if not (e.db.compagnie and ici) or suggerees[ici] then return end
  local z = zoneDe(ici)
  if not z or zc and zc.zone == z then return end
  suggerees[ici] = true
  jeu.dire(("Tu entres en %s, qui n'est pas la zone de la Compagnie%s : « /compagnie zone » la choisit."):format(ici,
    zc and " (" .. nomZone(zc.zone) .. ")" or ""))
end
local ouvrir -- plus bas : la fenêtre de la Compagnie (1 : l'onglet Chaînes)
local function menuZone(owner)
  local niveau, actuelle = calculer().niveau, e.db.zoneCompagnie and e.db.zoneCompagnie.zone
  MenuUtil.CreateContextMenu(owner, function(_, root)
    if actuelle then root:CreateButton("Voir les chaînes", function() ouvrir(1) end) end -- l'arbre des chaînes (#33)
    root:CreateTitle("Zone de la Compagnie")
    if root.SetScrollMode then root:SetScrollMode(400) end
    for _, z in ipairs(ns.zones(base(), niveau)) do
      local texte = ("%s (niv. %d)"):format(nomZone(z.zone), z.niveau)
      root:CreateRadio(z.ouverte and texte or "|cff808080" .. texte .. "|r", function() return actuelle == z.zone end,
        function() choisirZone(z.zone) end)
    end
  end)
end
-- Écartée pour de bon : par une décision, ou emportée avec la chaîne d'une quête écartée (#27).
local function ecartees() return ns.ecarteesEffectives(e.db.ecartees, base()) end
local function ecartee(id) return ecartees()[id] ~= nil end
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
-- Écarter est rare : un clic droit sur une quête (suivi, liste À faire) ouvre un menu, puis la confirmation.
-- Quête personnelle (#7), dans le même menu pour une quête de mon journal : la marquer à la main (sans Questie, la base
-- des quêtes ne dit pas tout : une quête de métier…), coché tant qu'elle l'est ; le marquage part avec mon état.
-- sansEcarter : ma quête marquée, à part : le menu ne propose que de la démarquer.
-- ponytail: CompagnieDB.personnelles n'est jamais purgé (quelques ids) ; reprise plus tard, la quête est encore marquée.
local function basculerPersonnelle(id)
  e.db.personnelles = e.db.personnelles or {}
  e.db.personnelles[id] = not e.db.personnelles[id] or nil
  ns.signaler(e, false, envoi)
  redessiner()
end
local function menuEcarter(owner, id, sansEcarter)
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(titre(id))
    if ecartee(id) then root:CreateButton("Remettre dans la Compagnie", function() decider(id, false) end) -- l'arbre (#33)
    elseif not sansEcarter then root:CreateButton("Écarter pour la Compagnie", function() proposerEcart(id) end) end
    if C_QuestLog.GetLogIndexForQuestID(id) then
      root:CreateCheckbox("Quête personnelle (à moi seul)", function() return e.db.personnelles and e.db.personnelles[id] end,
        function() basculerPersonnelle(id) end)
    end
  end)
end
local function bulleEcarter(owner, details) -- details : ce que dit la ligne en entier (prérequis manquant, #27)
  GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
  if details then
    GameTooltip:SetText(details, 1, 1, 1, 1, true)
    GameTooltip:AddLine("Clic droit : écarter pour la Compagnie", 0.6, 0.6, 0.6, true)
  else GameTooltip:SetText("Clic droit : écarter pour la Compagnie", 1, 1, 1, 1, true) end
  GameTooltip:Show()
end

-- L'acceptation automatique (#26) : à l'ouverture de la fenêtre d'une quête (QUEST_DETAIL : partage ou PNJ), acceptée si
-- un autre membre l'a dans son journal (dernier état connu, corrigé par le jeu pour mon groupe : un partage arrive avant
-- l'état de qui partage) et qu'elle n'est pas écartée ; une confirmation d'escorte (QUEST_ACCEPT_CONFIRM : qui l'a
-- lancée, titre), confirmée si un membre l'a lancée. Réglage CompagnieDB.accepteAuto, allumé par défaut (nil).
local function accepteAuto() return e.db.compagnie and e.db.accepteAuto ~= false end
local function accepterQuete()
  local id = GetQuestID()
  if not (accepteAuto() and type(id) == "number" and id > 0) or ecartee(id) then return end
  for _, m in ipairs((membresDuJeu())) do
    if m.nom ~= moi() and m.quetes and m.quetes[id] then return AcceptQuest() end
  end
end
local function confirmerEscorte(qui, titreEscorte)
  if not accepteAuto() then return end
  for id in pairs(ecartees()) do if titre(id) == titreEscorte then return end end
  for _, m in ipairs(e.db.compagnie.membres) do
    if m.guid ~= moi() and (m.nom == qui or m.nom:match("^(%S+)") == qui) then
      ConfirmAcceptQuest()
      return StaticPopup_Hide("QUEST_ACCEPT") -- la fenêtre du jeu, montrée juste avant (Blizzard écoute avant nous)
    end
  end
end

-- Les blocs du suivi, un par quête (titre, objectifs, état) : { texte, quete = id d'une quête de la Compagnie (le clic
-- droit propose de l'écarter) } ; l'en-tête « À part », les quêtes à part et le message sans quête : sans quete.
local function blocsSuivi(calc, presents)
  local ordre, blocs = {}, {}
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
    local lignes = { "|cffffd100" .. titre(id) .. "|r" }
    for i, o in ipairs(q.objectifs) do lignes[#lignes + 1] = ligneObjectif(i, o) end
    local attente = {}
    for _, guid in ipairs(q.enAttente) do
      if guid ~= moi() and not presents[guid] then attente[#attente + 1] = prenom(guid) end
    end
    if q.aRendre then lignes[#lignes + 1] = "  |cff59cc73À rendre|r"
    elseif #attente > 0 then lignes[#lignes + 1] = "  |cff999999En attente de " .. table.concat(attente, ", ") .. "|r" end
    blocs[#blocs + 1] = { texte = table.concat(lignes, "\n"), quete = id }
  end
  -- Les quêtes à part (#20 : quêtes d'avant ; #21 : écartée gardée), sous les quêtes de la Compagnie : nommées, avec
  -- l'avancement de qui l'a ; À rendre quand il l'a finie, sans attendre personne.
  local entete = false
  for _, a in ipairs(calc.aPart) do
    if not voir or a.zone == voir then
      if not entete then blocs[#blocs + 1], entete = { texte = (#blocs > 0 and "\n" or "") .. "|cff999999À part|r" }, true end
      local lignes = { "|cffc0c0c0" .. titre(a.quete) .. " (" .. prenom(a.membre) .. (a.ecartee and ", écartée" or "") .. ")|r" }
      for i, o in ipairs(a.objectifs) do lignes[#lignes + 1] = ligneObjectif(i, o) end
      if a.aRendre then lignes[#lignes + 1] = "  |cff59cc73À rendre|r" end
      -- Ma quête marquée personnelle (#7) : le clic droit propose de la démarquer.
      local marquee = a.membre == moi() and e.db.personnelles and e.db.personnelles[a.quete]
      blocs[#blocs + 1] = { texte = table.concat(lignes, "\n"), quete = marquee and a.quete or nil, sansEcarter = marquee }
    end
  end
  if #blocs == 0 then
    blocs[1] = { texte = voir and "|cff999999Aucune quête de la Compagnie dans cette zone.|r" or "|cff999999Aucune quête en cours.|r" }
  end
  return blocs
end

-- La liste À faire : mes écarts (ceux où c'est moi qui agis), un bouton chacun ; son libellé dit l'action et son état.
-- Partager : actif quand un membre qui n'a pas la quête est dans mon groupe du jeu (le jeu ne partage qu'au groupe).
-- Abandonner aussi (quête écartée, #21) : le clic du joueur, confirmé (les objets de la quête sont détruits), et lui
-- seul abandonne la quête (l'add-on n'abandonne jamais tout seul) ; s'il la garde, elle est à lui, à part.
-- Clic droit sur une ligne qui porte une quête pas encore écartée (Partager, Rendue en avance), même inactive : le menu
-- Écarter (#21).
-- Rendue en avance (#8) : un membre l'a rendue avant que je l'aie finie ; rien à cliquer (je la finis), sans dire qui.
-- Foyer différent (#9) : « Lie-toi à l'auberge de … » ; rien à cliquer (on se lie chez l'aubergiste).
-- Niveau insuffisant (#7) : « Au niveau 10 : Les Kobolds », la bulle dit « au niveau 10 pour toute la Compagnie », sans
-- dire qui ; rien à cliquer (pas de partage impossible).
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
local dernierPartage -- { quete, t = GetTime() } : mon dernier partage d'un clic (#7)
local function suivante(liste, unites)
  local libres = {}
  for _, x in ipairs(liste) do if not partagees[x.quete] then libres[#libres + 1] = x end end
  if #libres == 0 then partagees, libres = {}, liste end
  for _, x in ipairs(libres) do
    for _, guid in ipairs(x.manquants) do if unites[guid] then return x, #libres - 1, true end end
  end
  return libres[1], #libres - 1, false
end
-- Les deux listes près de la minicarte ne sont pas des fenêtres (CONTEXT-MAP, Fenêtre) : un cadre nu du socle, avec
-- l'en-tête du suivi des quêtes du jeu (son gabarit : titre doré, trait, bouton « – »). On les déplace par l'en-tête ; le
-- « – » les ferme, comme la croix d'une fenêtre (bulle : ce que ça fait).
local function entete(f, texte, bulle)
  local h = CreateFrame("Frame", nil, f, "ObjectiveTrackerContainerHeaderTemplate")
  h:SetPoint("TOPLEFT", 14, 0)
  h:SetWidth(262)
  h.Text:SetText(texte)
  local moins = h.MinimizeButton
  moins:SetScript("OnClick", function() f:Hide() end)
  moins:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(bulle, 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  moins:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f:DeplacePar(h)
  f.entete = h
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
      -- Une seule ligne, coupée par « … » : un long titre de quête débordait du bouton sur deux lignes (vu en jeu,
      -- 25/11/2026) ; le texte entier passe dans la bulle.
      b:GetFontString():SetWordWrap(false)
      -- Un bouton inactif n'a ni OnClick ni (par défaut) OnEnter, mais reçoit OnMouseUp : le clic droit passe par là.
      b:SetMotionScriptsWhileDisabled(true)
      b:SetScript("OnEnter", function(self)
        local entier = self:GetFontString():IsTruncated() and self:GetText() or nil
        if self.ecartable then bulleEcarter(self, self.details or entier)
        elseif entier then
          GameTooltip:SetOwner(self, "ANCHOR_LEFT")
          GameTooltip:SetText(entier, 1, 1, 1, 1, true)
          GameTooltip:Show()
        end
      end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
      b:HookScript("OnMouseUp", function(self, bouton)
        if bouton == "RightButton" and self.ecartable then menuEcarter(self, self.ecartable) end
      end)
      b:SetScript("OnClick", function(self)
        if self.x.type == "donner" then return self.unite and InitiateTrade(self.unite) end
        if self.x.type ~= "ecartee" and self.x.type ~= "partager" then return end
        if self.x.type == "ecartee" then
          local p = StaticPopup_Show("COMPAGNIE_ABANDON", titre(self.x.quete))
          if p then p.data = self.x.quete end
          return
        end
        local index = C_QuestLog.GetLogIndexForQuestID(self.quete)
        if not index then return end -- plus dans mon journal : rien à partager
        QuestLogPushQuest(index)
        dernierPartage = { quete = self.quete, t = GetTime() } -- un refus pour niveau insuffisant suivra peut-être (#7)
        partagees[self.quete] = true
        redessiner() -- le bouton passe à la suivante
      end)
      l.boutons[i] = b
    end
    b.x, b.ecartable, b.details = x, (x.type == "avance" or x.type == "prerequis" or x.type == "niveau" or x.type == "prendre"
      or x.type == "donner" or x.type == "recevoir") and x.quete or nil, nil
    if x.type == "prerequis" then
      local n = #x.chaine
      local quetes = n == 1 and "1 quête" or n .. " quêtes"
      b:SetText(("Avant %s : %s à %s"):format(titre(x.quete), quetes, nomZone(x.zone)))
      b.details = ("« %s » demande avant %s à %s, à commencer par « %s »%s. Manque à %s.%s"):format(titre(x.quete), quetes,
        nomZone(x.zone), titre(x.chaine[1]), x.donneur and x.donneur.nom and " (" .. x.donneur.nom .. ")" or "",
        x.tous and "toute la Compagnie" or noms(x.manquants),
        #x.aControler > 0 and " À contrôler : " .. noms(x.aControler) .. " (son état ne couvre pas cette zone)." or "")
      b:Disable()
    elseif x.type == "ecartee" then
      b:SetText("Abandonner aussi : " .. titre(x.quete))
      b:Enable()
    elseif x.type == "avance" then
      b:SetText("Rendue en avance : " .. titre(x.quete))
      b:Disable()
    elseif x.type == "niveau" then
      b:SetText(("Au niveau %d : %s"):format(x.niveau, titre(x.quete))) -- comme « Partager : … » ; la phrase, dans la bulle
      b.details = ("« %s » : au niveau %d pour toute la Compagnie."):format(titre(x.quete), x.niveau)
      b:Disable()
    elseif x.type == "prendre" then
      local o = x.objet
      if x.donneur and x.donneur.nom then
        b:SetText("Va voir " .. x.donneur.nom .. (x.donneur.carte and ", " .. nomCarte(x.donneur.carte) or ""))
        b.details = ("« %s » ne se partage pas : va voir %s%s."):format(titre(x.quete), x.donneur.nom, lieu(x.donneur))
      elseif o then
        local nom = o.nom and "« " .. o.nom .. " »" or "l'objet qui la lance"
        b:SetText("Trouve " .. (o.nom or "l'objet de " .. titre(x.quete)))
        b.details = ("« %s » part d'un objet, %s%s."):format(titre(x.quete), nom,
          o.ramasse and " : un membre l'a ramassé" .. lieu(o.ramasse)
          or o.pnjs and " : lâché par " .. table.concat(o.pnjs, ", ") or o.objets and " : trouvé dans " .. table.concat(o.objets, ", ") or "")
      else
        b:SetText("À prendre soi-même : " .. titre(x.quete))
        b.details = ("« %s » ne se partage pas : chacun va la prendre."):format(titre(x.quete))
      end
      b:Disable()
    elseif x.type == "donner" or x.type == "recevoir" then
      local objet = ns.libelle(x.texte) or "objets"
      if x.type == "donner" then
        b.unite = unites[x.a] -- l'échange ne s'ouvre qu'avec un membre de mon groupe, connecté
        b:SetText(("Donne %d %s à %s"):format(x.nombre, objet, prenom(x.a)))
        b.details = ("La Compagnie a assez de %s pour « %s » : donne-en %d à %s%s."):format(objet, titre(x.quete), x.nombre,
          prenom(x.a), b.unite and " (clic : ouvrir l'échange)" or "")
        b:SetEnabled(b.unite ~= nil)
      else
        b:SetText(("%s te donne %d %s"):format(prenom(x.de), x.nombre, objet))
        b.details = ("La Compagnie a assez de %s pour « %s » : %s t'en donne %d."):format(objet, titre(x.quete),
          prenom(x.de), x.nombre)
        b:Disable()
      end
    elseif x.type == "foyer" then
      local voyelle = x.auberge:find("^[AEIOUYaeiouy]") or x.auberge:sub(1, 2) == "É"
      b:SetText("Lie-toi à l'auberge " .. (voyelle and "d'" or "de ") .. x.auberge)
      b:Disable()
    else
      local q, reste, auGroupe = suivante(x.liste, unites)
      b.quete, b.ecartable = q.quete, q.quete
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
  b:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", f:GetLeft() + 14, f:GetTop() - 62)
end
local function duree(s)
  local m = math.ceil(s / 60)
  return m < 60 and m .. " min" or ("%d h %02d"):format(math.floor(m / 60), m % 60)
end

-- Les lignes du suivi (CompagnieSuiviLigne1…), une par bloc, empilées dans le contenu qui défile ; rend leur hauteur.
-- Clic droit sur une quête de la Compagnie : le menu Écarter. La molette passe au cadre qui défile ; le glisser déplace
-- le suivi, comme son en-tête.
local lignesSuivi = {}
local function placerLignes(blocs)
  local f, y = CompagnieSuiviFrame, 0
  for i, b in ipairs(blocs) do
    local l = lignesSuivi[i]
    if not l then
      l = CreateFrame("Button", "CompagnieSuiviLigne" .. i, CompagnieSuiviContenu)
      l:SetWidth(244)
      l.texte = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      l.texte:SetPoint("TOPLEFT")
      l.texte:SetWidth(244)
      l.texte:SetJustifyH("LEFT")
      l:RegisterForClicks("RightButtonUp")
      f:DeplacePar(l) -- place retenue (socle)
      l:SetScript("OnClick", function(self) if self.quete then menuEcarter(self, self.quete, self.sansEcarter) end end)
      l:SetScript("OnEnter", function(self)
        if self.sansEcarter then
          GameTooltip:SetOwner(self, "ANCHOR_LEFT")
          GameTooltip:SetText("Clic droit : quête personnelle", 1, 1, 1, 1, true)
          GameTooltip:Show()
        elseif self.quete then bulleEcarter(self) end
      end)
      l:SetScript("OnLeave", function() GameTooltip:Hide() end)
      lignesSuivi[i] = l
    end
    l.quete, l.sansEcarter = b.quete, b.sansEcarter
    l.texte:SetText(b.texte)
    local h = math.max(1, l.texte:GetStringHeight())
    l:SetHeight(h)
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", 0, -y)
    l:Show()
    y = y + h
  end
  for i = #blocs + 1, #lignesSuivi do lignesSuivi[i]:Hide() end
  return y
end

local function dessinerSuivi(calc, presents, unites)
  local f = CompagnieSuiviFrame
  if not (f and f:IsShown() and e.db.compagnie) then return end
  if not calc then calc, presents, unites = calculer() end
  local hAFaire = remplirAFaire(CompagnieSuiviAFaire, mesEcarts(calc), unites)
  local h = placerLignes(blocsSuivi(calc, presents))
  local zc = e.db.zoneCompagnie
  CompagnieZoneBouton:SetText(not zc and "Choisir la zone de la Compagnie" or "Zone : " .. nomZone(zc.zone) ..
    (#calc.aControler > 0 and " (" .. noms(calc.aControler) .. " à contrôler)" or ""))
  CompagnieSuiviZone:SetText(libelleZone())
  CompagnieSuiviZone:SetWidth(CompagnieSuiviZone:GetFontString():GetStringWidth() + 22)
  CompagnieSuiviContenu:SetHeight(math.max(1, h))
  f:SetHeight(math.min(156 + hAFaire + h, UIParent:GetHeight() * 0.6))
  placerPierre()
  if CompagniePierre then CompagniePierre:SetText(calc.pierre > 0 and "Foyer dans " .. duree(calc.pierre) or "Rentrer au foyer") end
end

-- La petite liste À faire, mode Compagnie éteint : montrée quand j'ai quelque chose à faire. Son « – » la ferme jusqu'à
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
    -- Hauteur qui suit ses lignes ; à gauche de la minicarte (le suivi du jeu est dessous), ou là où le joueur l'a mise.
    f = AC.Fenetre("CompagnieAFaireFrame", nil, 290, 80,
      { cadre = false, place = { "TOPRIGHT", Minimap, "TOPLEFT", -12, -20 } })
    f:SetFrameStrata("LOW")
    entete(f, "À faire", "Masquer jusqu'au prochain changement")
    listeAFaire(f, "CompagniePetiteListe", -36)
    f:HookScript("OnHide", function(self)
      if not masquageInterne and not self:IsShown() then fermeeSur = signature(mesEcarts(calculer())) end
    end)
  end
  fermeeSur = nil
  f:Show()
  f:SetHeight(40 + remplirAFaire(CompagniePetiteListe, ecarts, unites))
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
    b = CreateFrame("Frame", "CompagnieBandeau", QuestFrame, "TooltipBackdropTemplate") -- enfant : caché avec la fenêtre
    b:SetPoint("TOPLEFT", QuestFrame, "BOTTOMLEFT", 0, -4)
    b:SetPoint("TOPRIGHT", QuestFrame, "BOTTOMRIGHT", 0, -4)
    b:SetHeight(30)
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
    -- Hauteur qui suit son contenu (dessinerSuivi) ; sous la minicarte, ou là où le joueur l'a mis.
    local f = AC.Fenetre("CompagnieSuiviFrame", nil, 290, 160,
      { cadre = false, place = { "TOPRIGHT", UIParent, "TOPRIGHT", -40, -260 } })
    f:SetFrameStrata("LOW")
    -- Un suivi reste à l'écran : Échap ne le ferme pas (cadre nu) ; son « – » éteint le mode Compagnie.
    entete(f, "Compagnie", "Éteindre le mode Compagnie (le suivi du jeu revient)")
    -- En tête : la zone de la Compagnie (#24), son bouton ouvre le menu des zones ; dessous, la pierre (placerPierre).
    local zc = CreateFrame("Button", "CompagnieZoneBouton", f, "UIPanelButtonTemplate")
    zc:SetSize(262, 22)
    zc:SetPoint("TOPLEFT", 14, -36)
    zc:SetScript("OnClick", menuZone)
    titreDePartie(f, "À faire", -92)
    local aFaire = listeAFaire(f, "CompagnieSuiviAFaire", -112)
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
    local liste = CreateFrame("Frame", "CompagnieSuiviZones", f, "TooltipBackdropTemplate")
    liste:SetPoint("TOPLEFT", z, "BOTTOMLEFT", -4, -2)
    liste:SetWidth(250)
    liste:SetFrameStrata("MEDIUM") -- au-dessus des quêtes qui défilent (le suivi est en LOW)
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
          l:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD") -- le survol des menus du jeu
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
    defil.scrollBarHideable = true -- sans cadre, la barre ne se montre que s'il y a à faire défiler
    defil.ScrollBar:Hide() -- posé après son OnLoad, qui l'a montrée : cachée d'office, comme UIPanelInputScrollFrame_OnLoad
    defil:SetPoint("TOPLEFT", z, "BOTTOMLEFT", 0, -4)
    defil:SetPoint("BOTTOMRIGHT", -32, 12)
    local contenu = CreateFrame("Frame", "CompagnieSuiviContenu", defil)
    contenu:SetSize(244, 1)
    defil:SetScrollChild(contenu)
    -- Fermée par son « – » (pas quand l'interface entière est cachée, Alt-Z : elle reste « montrée ») : mode éteint.
    f:HookScript("OnShow", placerPierre)
    hooksecurefunc(f, "StopMovingOrSizing", placerPierre) -- fin d'un déplacement, par l'en-tête ou une ligne
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
  redessiner() -- la fenêtre, et les plaques
end

---------------------------------------------------------------------------------------------------
-- La fenêtre de la Compagnie, en trois onglets : Chaînes (#33 : l'arbre des chaînes, une fenêtre à part, grande),
-- Membres (présent ou absent, « Retirer » sur les autres ; « Fonder » ou « Quitter ») et Écartées (#21 : les quêtes
-- écartées, qui l'a décidé, « Remettre »), les deux vues de CompagnieFrame ; le mode Compagnie, son état sur son bouton.
local tableau, vide, boutonFonder, boutonQuitter, boutonMode, tableauEcartees, videEcartees, panneaux
-- Inviter (#23) : la proposition part au groupe du jeu ; sans réponse au bout du délai, l'invitation tombe.
local function inviter(guid)
  local g = groupe()
  local ok, raison = ns.inviter(e, moi(), g, guid, jeu)
  if not ok then return jeu.dire(raison) end
  local nom = g[ns.membre({ membres = g }, guid)].nom
  jeu.dire("Invitation envoyée à " .. nom .. " : il a une minute pour répondre.")
  C_Timer.After(DELAI + 5, function()
    if e.invitations and e.invitations[guid] then
      e.invitations[guid] = nil
      jeu.dire(nom .. " n'a pas répondu à l'invitation.")
      redessiner()
    end
  end)
  redessiner()
end
local COLONNES = {
  { key = "nom", title = "Membre", w = 180, extensible = true, get = function(m) return m.nom end },
  { key = "presence", title = "Présence", w = 80, get = function(m) return m.presence end,
    fmt = function(v) return (v == "présent" and "|cff59cc73" or "|cff999999") .. v .. "|r" end },
  -- Retirer un membre ; Inviter un joueur du groupe qui n'est pas membre (#23), « Invité… » en attendant sa réponse.
  { key = "retirer", w = 80, button = function(m)
      if m.invitable then return e.invitations and e.invitations[m.guid] and "Invité…" or "Inviter" end
      if m.guid ~= moi() then return "Retirer" end
    end,
    click = function(m) if m.invitable then inviter(m.guid) else ns.retirer(e, moi(), m.guid, jeu) end end },
}
local COLONNES_ECARTEES = {
  { key = "titre", title = "Quête écartée", w = 180, extensible = true, get = function(l) return l.titre end },
  { key = "par", title = "Par", w = 80, get = function(l) return l.par end },
  { key = "remettre", w = 80, button = function() return "Remettre" end, click = function(l) decider(l.quete, false) end },
}

function dessiner()
  local c, presents, lignes = e.db.compagnie, presence(), {}
  presents[moi()] = true
  for i, m in ipairs(c and c.membres or {}) do
    lignes[i] = { guid = m.guid, nom = m.nom, presence = presents[m.guid] and "présent" or "absent" }
  end
  for _, p in ipairs(c and #c.membres < ns.MAX and groupe() or {}) do -- les joueurs du groupe à inviter (#23)
    if not ns.membre(c, p.guid) then lignes[#lignes + 1] = { guid = p.guid, nom = p.nom, presence = "dans le groupe", invitable = true } end
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

local function bouton(f, texte, fn, largeur, nom)
  local b = CreateFrame("Button", nom, f, "UIPanelButtonTemplate")
  b:SetSize(largeur or 100, 22)
  b:SetPoint("BOTTOMLEFT", 14, 12)
  b:SetText(texte)
  b:SetScript("OnClick", fn)
  return b
end

-- Les onglets du bas, les mêmes sur les deux fenêtres (modèle : ns.onglets de Handshake) : chaque fenêtre retient sa
-- taille ; l'onglet de l'autre fenêtre l'ouvre à la même place, et celle-ci se ferme.
local function onglets(f)
  f.Tabs = {}
  for i, nom in ipairs({ "Chaînes", "Membres", "Écartées" }) do
    local t = CreateFrame("Button", f:GetName() .. "Tab" .. i, f, "PanelTabButtonTemplate")
    t:SetID(i)
    t:SetText(nom)
    t:SetScript("OnClick", function() ouvrir(i) end)
    f.Tabs[i] = t
  end
  f.Tabs[1]:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 10, 2)
  PanelTemplates_SetNumTabs(f, 3)
end

local function fenetreMembres()
  if CompagnieFrame then return CompagnieFrame end
  local f = AC.Fenetre("CompagnieFrame", "Compagnie", 400, 230)
  panneaux = {}
  for i = 1, 2 do panneaux[i] = CreateFrame("Frame", nil, f); panneaux[i]:SetAllPoints() end
  local largeur
  tableau, largeur = AC.Tableau(panneaux[1], COLONNES, { name = "membres", bottom = 44 })
  f:SetWidth(largeur + 50)
  vide = panneaux[1]:CreateFontString("CompagnieVide", "OVERLAY", "GameFontHighlight")
  vide:SetPoint("TOPLEFT", 14, -70)
  vide:SetPoint("TOPRIGHT", -14, -70)
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
  videEcartees:SetPoint("TOPRIGHT", -14, -70)
  videEcartees:SetJustifyH("LEFT")
  videEcartees:SetText("Aucune quête écartée. Pour écarter une quête : clic droit sur elle dans le suivi, la liste " ..
    "À faire ou l'onglet Chaînes.")
  onglets(f)
  return f
end

-- L'onglet Chaînes (#33, #34) : l'arbre des chaînes de la zone de la Compagnie (ns.arbreDesChaines), dessiné par l'Arbre
-- du socle ; chaque case : nom, niveau, couleur d'état (faite grisée, disponible cerclée, verrouillée terne, écartée
-- barrée), la marque d'une quête inégale ; bulle : donneur et endroit (base des quêtes), niveau requis, zone d'un début
-- hors zone, qui l'a faite ou prise, ce qui la bloque pour qui, à contrôler ; clic droit : le menu du suivi. Une chaîne
-- faite ou écartée tient en une ligne : clic = déplier ; clic sur une de ses quêtes, dépliée = replier. Sans zone
-- choisie, le message le dit (pas de toile vide).
local dessinerChaines -- plus bas
local arbreChaines, zoneDessinee, aControler, deplies = nil, nil, {}, {} -- deplies : les chaînes repliées que j'ai dépliées (local, jamais envoyé)
local COULEURS = { faite = { 0.35, 0.80, 0.45 }, aRendre = { 0.35, 0.80, 0.45 }, enCours = { 0.35, 0.60, 1.00 },
  disponible = { 1.00, 0.82, 0.00 }, verrouillee = { 0.40, 0.40, 0.40 }, niveau = { 0.90, 0.30, 0.30 },
  ecartee = { 0.45, 0.45, 0.45 } }
local ALPHA = { faite = 0.5, verrouillee = 0.65, ecartee = 0.6 }
local LIBELLES = { faite = "Faite", aRendre = "À rendre", disponible = "Disponible", verrouillee = "Verrouillée", ecartee = "Écartée" }
local function etatCase(n)
  if n.repliee then return (n.etat == "ecartee" and "Écartée" or "Faite par tous") .. " · clic : déplier" end
  if n.horsZone then return "Hors zone : " .. nomZone(n.horsZone) .. (n.etat == "faite" and " · faite" or "") end
  local t = LIBELLES[n.etat] or n.etat == "niveau" and ("niveau %d requis"):format(n.requis) or nil
  if n.etat == "enCours" then -- l'avancement commun ; « En cours » sans objectif (aller parler à quelqu'un)
    local c = {}
    for i, o in ipairs(n.objectifs or {}) do c[i] = o.fait .. "/" .. o.total end
    t = #c > 0 and table.concat(c, ", ") or "En cours"
  end
  -- un niveau inconnu (la base met -1 aux quêtes qui suivent le niveau du joueur) ne s'écrit pas
  local niv = (n.niveau or 0) > 0 and ("Niv. %d"):format(n.niveau) or nil
  return niv and t and (niv .. " · " .. t) or niv or t or ""
end
local function bulleCase(c)
  local n, q = c.n, base()[c.n.quete] or {}
  GameTooltip:SetOwner(c, "ANCHOR_RIGHT")
  if n.repliee then
    GameTooltip:SetText(c.nom:GetText(), 1, 1, 1)
    GameTooltip:AddLine("Clic : déplier la chaîne", 0.6, 0.6, 0.6)
    return GameTooltip:Show()
  end
  GameTooltip:SetText(titre(n.quete), 1, 1, 1)
  if q.niveau then
    GameTooltip:AddLine(("Niveau %d%s"):format(q.niveau, q.niveau_requis and (", requis %d"):format(q.niveau_requis) or ""), 0.8, 0.8, 0.8)
  end
  if q.donneur and q.donneur.nom then GameTooltip:AddLine(q.donneur.nom .. lieu(q.donneur), 0.8, 0.8, 0.8) end
  if n.horsZone then
    local ch = ns.chaine(base(), n.quete, e.db.zoneCompagnie and e.db.zoneCompagnie.zone)
    GameTooltip:AddLine(("Début hors de la zone : %s, %d quête%s à commencer par « %s »."):format(nomZone(n.horsZone), #ch,
      #ch > 1 and "s" or "", titre(ch[1])), 1, 0.82, 0, true)
  end
  local ig = n.inegale -- qui l'a faite ou prise (#34)
  if ig and #ig.faites > 0 then GameTooltip:AddLine("Faite par " .. noms(ig.faites) .. ".", 1, 0.5, 0.15, true) end
  if ig and #ig.prises > 0 then GameTooltip:AddLine("Prise par " .. noms(ig.prises) .. ".", 1, 0.5, 0.15, true) end
  for _, b in ipairs(n.bloque or {}) do
    local function liste(ids, sep)
      local t = {}
      for i, p in ipairs(ids or {}) do t[i] = "« " .. titre(p) .. " »" end
      return table.concat(t, sep)
    end
    local tous, un = liste(b.prerequis, " et "), liste(b.un, " ou ")
    local quoi = tous .. (tous ~= "" and un ~= "" and ", puis " or "") .. (un ~= "" and ((b.un[2] and "l'une de " or "") .. un) or "")
    GameTooltip:AddLine(("Bloquée pour %s : %s."):format(noms({ b.membre }), b.niveau and "niveau " .. b.niveau
      or "d'abord " .. quoi), 0.9, 0.3, 0.3, true)
  end
  if #aControler > 0 then
    GameTooltip:AddLine("À contrôler : " .. noms(aControler) .. " (son état ne couvre pas cette zone).", 0.6, 0.6, 0.6, true)
  end
  if n.repliable then GameTooltip:AddLine("Clic : replier la chaîne", 0.6, 0.6, 0.6) end
  GameTooltip:AddLine("Clic droit : écarter ou remettre, quête personnelle", 0.6, 0.6, 0.6)
  GameTooltip:Show()
end
local function caseChaine(n, c)
  if not c then
    c = CreateFrame("Button", nil, arbreChaines.toile, "InsetFrameTemplate")
    c:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    c.accent = c:CreateTexture(nil, "ARTWORK")
    c.accent:SetPoint("TOPLEFT", 1, -1)
    c.accent:SetPoint("BOTTOMLEFT", 1, 1)
    c.accent:SetWidth(3)
    c.nom = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.nom:SetPoint("TOPLEFT", 10, -7)
    c.nom:SetPoint("RIGHT", -8, 0)
    c.nom:SetJustifyH("LEFT")
    c.nom:SetWordWrap(false)
    c.sous = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    c.sous:SetPoint("TOPLEFT", 10, -23)
    c.sous:SetPoint("RIGHT", -8, 0)
    c.sous:SetJustifyH("LEFT")
    c.sous:SetWordWrap(false)
    c.barre = c:CreateTexture(nil, "OVERLAY") -- écartée : le nom barré
    c.barre:SetColorTexture(0.9, 0.3, 0.3, 0.9)
    c.barre:SetHeight(1)
    c.barre:SetPoint("LEFT", c.nom, "LEFT", 0, 0)
    c.cercle = CreateFrame("Frame", nil, c, "BackdropTemplate") -- disponible : cerclée
    c.cercle:SetAllPoints()
    c.cercle:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    c.cercle:SetBackdropBorderColor(1, 0.82, 0, 0.9)
    c.marque = c:CreateTexture(nil, "OVERLAY") -- inégale : une pastille, la bulle dit qui
    c.marque:SetSize(8, 8)
    c.marque:SetPoint("TOPRIGHT", -5, -5)
    c.marque:SetColorTexture(1, 0.5, 0.15)
    c:SetScript("OnClick", function(self, b)
      local n = self.n
      if b == "RightButton" then return not n.repliee and menuEcarter(self, n.quete) end
      if n.repliee or n.repliable then deplies[n.band] = n.repliee or nil; dessinerChaines() end
    end)
    c:SetScript("OnEnter", bulleCase)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  c.n = n
  local k = COULEURS[n.etat] or COULEURS.verrouillee -- un état inconnu : terne (COULEURS.neutre n'existe pas)
  c.accent:SetColorTexture(k[1], k[2], k[3], 0.9)
  c.nom:SetText(n.repliee and ("%s%s — %d quête%s"):format(n.etat == "faite" and "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t " or "",
    titre(n.quete), n.n, n.n > 1 and "s" or "") or titre(n.quete))
  c.sous:SetText(etatCase(n))
  c.barre:SetShown(n.etat == "ecartee")
  c.barre:SetWidth(math.min(c.nom:GetStringWidth(), 170))
  c.cercle:SetShown(n.etat == "disponible")
  c.marque:SetShown(n.inegale ~= nil)
  c:SetAlpha(ALPHA[n.etat] or 1)
  return c
end

local dernier -- le dernier arbre calculé : redessiné tel quel pendant un redimensionnement (memes = true)
function dessinerChaines(memes)
  local f = CompagnieChainesFrame
  if not (f and f:IsShown()) then return end
  local zc = e.db.zoneCompagnie
  f.title:SetText(zc and "Compagnie · " .. nomZone(zc.zone) or "Compagnie")
  local a = memes and dernier
    or arbreChaines and e.db.compagnie and zc and ns.arbreDesChaines(membresDuJeu(), e.db.ecartees, base(), zc.zone, deplies)
  dernier = a or nil
  local msg = not arbreChaines and "L'onglet Chaînes demande une version plus récente d'Azeroth Commune (l'Arbre) : mets le socle à jour."
    or not e.db.compagnie and "Pas de Compagnie : fonde-la dans l'onglet Membres."
    or not zc and "Choisis la zone de la Compagnie dans le suivi."
    or #a.cases == 0 and "Aucune quête de " .. nomZone(zc.zone) .. " dans la base des quêtes." or nil
  CompagnieChainesMessage:SetText(msg or "")
  CompagnieChainesMessage:SetShown(msg ~= nil)
  if arbreChaines then arbreChaines.zone:SetShown(msg == nil) end
  if msg then return end
  aControler = a.aControler
  for _, b in ipairs(a.bandes) do
    if b.seules then b.title = "Quêtes seules"
    elseif b.personnelle then b.title, b.color = "Personnelle · " .. prenom(b.personnelle), { 0.64, 0.21, 0.93 }
    else b.title, b.color = not b.repliee and titre(b.premiere) or nil, { 0.60, 0.60, 0.62 } end -- repliée : sa ligne le dit
  end
  -- Une zone a de longues chaînes : rétrécie pour tenir en largeur (l'Arbre), on ne lirait plus rien. Une zone
  -- nouvellement dessinée s'ouvre à taille réelle, en haut à gauche (glisser le fond pour la parcourir, molette pour
  -- zoomer) ; ensuite, l'échelle choisie par le joueur est gardée d'un dessin à l'autre, fenêtre agrandie comprise.
  -- ponytail: la largeur du dessin recalculée comme l'Arbre (AzerothCommune.Arbre, Dessiner) ; à suivre s'il change.
  local g, v, avail = AC.PlacerArbre(a.cases, a.liens, a.bandes), arbreChaines.vue, arbreChaines.zone:GetWidth()
  if avail >= 100 then
    local d = g.dims
    local ecart = g.cols > 1 and math.max(d.largeur + 44, (avail - d.largeur - 2 * d.marge) / (g.cols - 1)) or 0
    local echelle = zoneDessinee == zc.zone and v.fit * v.zoom or 1
    if zoneDessinee ~= zc.zone then zoneDessinee, v.x, v.y = zc.zone, 0, 0 end
    v.zoom = echelle / math.min(1, avail / (d.largeur + ecart * (g.cols - 1) + 2 * d.marge))
  end
  arbreChaines:Dessiner(g)
end

local function fenetreChaines()
  if CompagnieChainesFrame then return CompagnieChainesFrame end
  local f = AC.Fenetre("CompagnieChainesFrame", "Compagnie", 720, 420)
  local m = f:CreateFontString("CompagnieChainesMessage", "OVERLAY", "GameFontHighlight")
  m:SetPoint("TOPLEFT", 20, -70)
  m:SetPoint("TOPRIGHT", -20, -70)
  m:SetJustifyH("LEFT")
  if AC.Arbre then
    arbreChaines = AC.Arbre(f, { case = caseChaine })
    arbreChaines.zone:SetPoint("TOPLEFT", 12, -28)
    arbreChaines.zone:SetPoint("BOTTOMRIGHT", -12, 12)
  end
  onglets(f)
  -- La largeur de la zone n'est connue qu'affichée : redessiné juste après (et agrandie : les étages s'étalent).
  f:HookScript("OnShow", function() C_Timer.After(0, dessinerChaines) end)
  f:HookScript("OnSizeChanged", function() dessinerChaines(true) end)
  return f
end

-- Ouvrir la fenêtre de la Compagnie sur l'onglet vue (1 Chaînes, 2 Membres, 3 Écartées) ; sans vue : Chaînes, ou Membres
-- sans Compagnie (Fonder). L'autre fenêtre, ouverte, cède sa place.
function ouvrir(vue)
  vue = vue or (e.db.compagnie and 1 or 2)
  local f = vue == 1 and fenetreChaines() or fenetreMembres()
  local autre = vue == 1 and CompagnieFrame or CompagnieChainesFrame
  if autre and autre:IsShown() then
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", autre:GetLeft(), autre:GetTop())
    autre:Hide()
  end
  f:Show()
  PanelTemplates_SetTab(f, vue)
  if vue == 1 then return dessinerChaines() end
  for k, p in ipairs(panneaux) do p:SetShown(k == vue - 1) end
  dessiner()
end

-- Les plaques des monstres (nameplates), mode Compagnie allumé : à droite de la barre de vie d'un monstre à tuer pour une
-- quête de la Compagnie, ou à part (la quête d'un membre, que je l'aie ou non), le nombre qui reste à tuer ; le plus
-- grand reste parmi ses objectifs (une mise à mort compte pour toutes les quêtes à la fois). Le monstre est reconnu à
-- son nom, celui de l'objectif (ns.libelle). ponytail: rien pour un objet à ramasser sur lui (« Patte de loup ») : le
-- jeu ne dit pas qui le lâche ; la base des quêtes le pourrait (QuestieDB).
local aTuer = {} -- [nom du monstre] = reste
local function compterATuer(objectifs)
  for _, o in ipairs(objectifs) do
    local n = ns.libelle(o.texte)
    if n and o.total > o.fait then aTuer[n] = math.max(aTuer[n] or 0, o.total - o.fait) end
  end
end
local function plaque(unite)
  local p = unite and C_NamePlate.GetNamePlateForUnit(unite)
  if not p or p:IsForbidden() then return end
  -- Pas en instance : Questie s'y coupe aussi sur Forever (unités restreintes par le jeu).
  local n = not IsInInstance() and not UnitIsPlayer(unite) and aTuer[UnitName(unite)]
  if not p.compagnie then
    if not n then return end
    p.compagnie = p:CreateFontString(nil, "OVERLAY", "GameFontNormalOutline")
  end
  local barre = p.UnitFrame and p.UnitFrame.HealthBarsContainer -- l'UnitFrame change d'une unité à l'autre
  p.compagnie:ClearAllPoints()
  if barre then p.compagnie:SetPoint("LEFT", barre, "RIGHT", 4, 0) else p.compagnie:SetPoint("BOTTOM", p, "TOP") end
  p.compagnie:SetText(n or "")
end
local function majPlaques()
  aTuer = {}
  if modeActif() then
    local calc = calculer()
    for _, q in pairs(calc.quetes) do compterATuer(q.objectifs) end
    for _, a in ipairs(calc.aPart) do if not a.ecartee then compterATuer(a.objectifs) end end
  end
  for _, p in ipairs(C_NamePlate.GetNamePlates() or {}) do plaque(p.unitToken or p.namePlateUnitToken) end
end

function redessiner()
  if CompagnieFrame and CompagnieFrame:IsShown() then dessiner() end
  dessinerChaines()
  majPlaques()
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

-- La liste des membres a changé par l'état d'un membre (#23, Etats.lua) : j'entre (invité), je n'y suis plus, ou
-- d'autres sont entrés ou partis.
function changerListe(l)
  if l.entre then
    jeu.entrer()
    local t = {}
    for i, m in ipairs(e.db.compagnie.membres) do t[i] = m.nom end
    jeu.dire("Tu entres dans la Compagnie : " .. table.concat(t, ", ") .. ".")
  elseif l.sorti then jeu.dire("Tu n'es plus membre de la Compagnie.")
  else
    for _, nom in ipairs(l.ajoutes) do jeu.dire(nom .. " est entré dans la Compagnie.") end
    for _, nom in ipairs(l.retires) do jeu.dire(nom .. " n'est plus dans la Compagnie.") end
  end
  ns.majCompagnie()
end

-- La Compagnie a changé : le mode suit, et mon état part (forcé : de nouveaux membres ne l'ont pas).
function ns.majCompagnie()
  if not e.db.compagnie then -- plus de Compagnie : derniers états, écartées, quêtes d'avant et remises vues oubliés
    e.db.etats, e.db.ecartees, e.db.avant, e.db.renduesVues, e.db.zoneCompagnie = nil, nil, nil, nil, nil
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
  diffuser(demandeEtat(), true)
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
        poster(demandeEtat(), "WHISPER", AC.Destinataire(m.nom))
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
-- abandonner(id) : « ecarter » (l'abandon l'écarte), « avant » (ma quête d'avant : seulement oubliée) ou nil (rien).
local function effetAbandon(id)
  if not (e.db.compagnie and type(id) == "number" and id > 0) or ecartee(id) then return end
  if e.db.avant and e.db.avant[id] and not calculer().quetes[id] then return "avant" end
  return "ecarter"
end
local aAbandonner, abandonsAccroches
local function accrocherAbandons()
  if abandonsAccroches or not C_QuestLog.AbandonQuest then return end -- ponytail: le simulateur n'a pas ces fonctions
  abandonsAccroches = true
  hooksecurefunc(C_QuestLog, "SetAbandonQuest", function() aAbandonner = C_QuestLog.GetAbandonQuest() end)
  hooksecurefunc(C_QuestLog, "AbandonQuest", function()
    local id = aAbandonner
    aAbandonner = nil
    local effet = effetAbandon(id)
    if effet == "avant" then
      e.db.avant[id] = nil
      return redessinerBientot()
    end
    if effet then decider(id, true) end
  end)
end

-- Le bandeau d'abandon (#25) : au-dessus de la fenêtre d'abandon du jeu (ABANDON_QUEST, avec ou sans objets de quête),
-- quand l'abandon écarterait la quête : « Abandonner « X » l'écarte pour la Compagnie », et la suite que la base des
-- quêtes connaît (« et coupe sa suite : Y, Z »). Accroché à l'affichage de la fenêtre (StaticPopup_Show), posé dessus
-- (enfant : caché avec elle) et hors d'elle : la fenêtre du jeu et ses boutons ne sont jamais touchés.
local function bandeauAbandon(which, nom)
  local b = CompagnieBandeauAbandon
  local _, fenetre = StaticPopup_Visible(which)
  if which ~= "ABANDON_QUEST" and which ~= "ABANDON_QUEST_WITH_ITEMS" then
    if b and fenetre and b:GetParent() == fenetre then b:Hide() end -- la même fenêtre resservie pour autre chose
    return
  end
  local id = C_QuestLog.GetAbandonQuest and C_QuestLog.GetAbandonQuest()
  if not (fenetre and effetAbandon(id) == "ecarter") then if b then b:Hide() end return end
  if not b then
    b = CreateFrame("Frame", "CompagnieBandeauAbandon", fenetre, "TooltipBackdropTemplate")
    b.texte = b:CreateFontString("CompagnieBandeauAbandonTexte", "OVERLAY", "GameFontNormal")
    b.texte:SetPoint("TOPLEFT", 10, -8)
    b.texte:SetJustifyH("LEFT")
  end
  b:SetParent(fenetre)
  b:ClearAllPoints()
  b:SetPoint("BOTTOMLEFT", fenetre, "TOPLEFT", 0, 4)
  b:SetPoint("BOTTOMRIGHT", fenetre, "TOPRIGHT", 0, 4)
  local q, noms, race, classe = base(), {}, select(3, UnitRace("player")), select(3, UnitClass("player"))
  for _, s in ipairs(ns.suite(q, id)) do
    if ns.peutPrendre(q[s], race, classe) then -- pas les lettres des autres classes
      if #noms == 3 then noms[4] = "…" break end
      noms[#noms + 1] = (q[s] or {}).nom or titre(s)
    end
  end
  b.texte:SetWidth(fenetre:GetWidth() - 20)
  local texte = ("Abandonner « %s » l'écarte pour la Compagnie%s."):format(type(nom) == "string" and nom or titre(id),
    #noms > 0 and " et coupe sa suite : " .. table.concat(noms, ", ") or "")
  b.texte:SetText((texte:gsub("…%.$", "…")))
  b:SetHeight(b.texte:GetStringHeight() + 16)
  b:Show()
end
hooksecurefunc("StaticPopup_Show", bandeauAbandon)

---------------------------------------------------------------------------------------------------
-- Messages d'add-on. Au groupe du jeu : d'un expéditeur que le serveur y nomme (son GUID vient du groupe) ; en
-- chuchotement : d'un membre, reconnu à son nom « Prénom Nom » donné par le serveur, et seulement pour les états.
-- Un partage refusé pour niveau insuffisant (#7) : le jeu dit seulement « Léo a un niveau trop bas… »
-- (ERR_QUEST_PUSH_LOW_LEVEL_S) ; la quête est mon dernier partage (moins de 10 s), et le niveau requis est au moins celui
-- de Léo (son dernier état connu) + 1 : appris dans CompagnieDB.niveauxRequis, il fait l'écart niveau insuffisant même
-- sans la base des quêtes. Seul le prénom compte (le jeu peut le donner sans le nom).
local function motif(gabarit) -- un texte du jeu à un « %s », en motif Lua qui capture le nom
  return gabarit and "^" .. gabarit:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("%%%%s", "(.+)") .. "$"
end
local function partageRefuse(texte)
  local m = motif(ERR_QUEST_PUSH_LOW_LEVEL_S)
  local nom = m and dernierPartage and GetTime() - dernierPartage.t < 10 and texte:match(m)
  if not nom then return end
  nom = nom:match("^(%S+)")
  for _, x in ipairs((membresDuJeu())) do
    if x.nom ~= moi() and x.niveau and prenom(x.nom) == nom then
      local id = dernierPartage.quete
      e.db.niveauxRequis = e.db.niveauxRequis or {}
      e.db.niveauxRequis[id] = math.max(e.db.niveauxRequis[id] or 0, x.niveau + 1)
      return redessiner()
    end
  end
end

-- Quête à prendre soi-même (#6) : où j'ai pris une quête, pour qui devra aller la chercher (envoyé avec mon état s'il
-- elle ne se partage pas). Ma position : uiMapID, x et y en % entiers ; {} sans carte (instance).
local function ici()
  local carte = C_Map.GetBestMapForUnit("player")
  local p = carte and C_Map.GetPlayerMapPosition(carte, "player")
  local x, y
  if p then x, y = p:GetXY() end
  if not (x and y) then return {} end
  return { carte = carte, x = math.floor(x * 100 + 0.5), y = math.floor(y * 100 + 0.5) }
end
local fenetreQuete -- { id, origine } : la fenêtre de quête ouverte (QUEST_DETAIL), notée si je l'accepte
local function noterOrigine(id, o)
  e.db.origines = e.db.origines or {}
  e.db.origines[id] = o
end
-- Le PNJ à l'acceptation, ou rien pour une quête lancée par un objet (la base dit lequel) : l'origine est alors l'endroit
-- où je l'ai ramassé. ponytail: le ramassage d'un membre de mon groupe compte aussi (le message de butin ne se lit pas
-- sans la langue du client) : l'endroit est le même, à quelques pas.
local function ramasse(message)
  local item = tonumber(message:match("|Hitem:(%d+)"))
  if not item then return end
  for id, q in pairs(base()) do
    if q.objet == item and not (e.db.origines and e.db.origines[id]) then
      local o = ici()
      if o.carte then noterOrigine(id, o) end
      return
    end
  end
end

local MONJOURNAL = { QUEST_LOG_UPDATE = true, QUEST_TURNED_IN = true, PLAYER_LEVEL_UP = true, UNIT_QUEST_LOG_CHANGED = true,
  BAG_UPDATE_COOLDOWN = true, HEARTHSTONE_BOUND = true, BAG_UPDATE_DELAYED = true } -- les sacs : le stock échangeable
local cadre = CreateFrame("Frame", "CompagnieMessages")
for _, ev in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE", "QUEST_LOG_UPDATE",
  "QUEST_ACCEPTED", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP", "UNIT_QUEST_LOG_CHANGED", "PLAYER_REGEN_ENABLED", "ZONE_CHANGED_NEW_AREA",
  "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_DETAIL", "QUEST_GREETING", "QUEST_FINISHED", "BAG_UPDATE_COOLDOWN",
  "HEARTHSTONE_BOUND", "BAG_UPDATE_DELAYED", "QUEST_ACCEPT_CONFIRM", "CHAT_MSG_SYSTEM", "CHAT_MSG_LOOT", "NAME_PLATE_UNIT_ADDED" }) do cadre:RegisterEvent(ev) end
cadre:SetScript("OnEvent", function(_, ev, a1, texte, canal, expediteur)
  if ev == "ADDON_LOADED" then
    if a1 == "Compagnie" then
      CompagnieDB = CompagnieDB or {}
      e.db, e.moi = CompagnieDB, moi()
      connectes, chuchotes = {}, {} -- la présence repart de zéro (en jeu, un /reload efface tout l'état Lua)
      accrocherAbandons()
      AC:Souscrire("base des quêtes") -- la suite d'une quête (#25), les zones et les prérequis (#24, #27)
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
    if ev == "ZONE_CHANGED_NEW_AREA" then suggererZone() end
  elseif ev == "PLAYER_REGEN_ENABLED" then
    if differe and ObjectiveTrackerFrame then appliquerSuiviDuJeu(ObjectiveTrackerFrame) end
    placerPierre()
  elseif ev == "QUEST_PROGRESS" or ev == "QUEST_COMPLETE" then
    remise = GetQuestID()
    majBandeau()
  elseif ev == "QUEST_DETAIL" or ev == "QUEST_GREETING" or ev == "QUEST_FINISHED" then
    remise = nil
    majBandeau()
    if ev == "QUEST_DETAIL" then
      local o = ici()
      o.nom = UnitExists("npc") and UnitName("npc") or nil
      fenetreQuete = { id = GetQuestID(), origine = o }
      accepterQuete()
    end
  elseif ev == "NAME_PLATE_UNIT_ADDED" then
    plaque(a1)
  elseif ev == "CHAT_MSG_LOOT" then
    if type(a1) == "string" then ramasse(a1) end
  elseif ev == "CHAT_MSG_SYSTEM" then
    if e.db.compagnie and type(a1) == "string" then partageRefuse(a1) end
  elseif ev == "QUEST_ACCEPT_CONFIRM" then
    confirmerEscorte(a1, texte)
  elseif ev == "QUEST_ACCEPTED" then
    -- Forever : (questID) ; d'autres clients Classic : (index, questID).
    local id = type(texte) == "number" and texte or a1
    if e.db.avant and id then e.db.avant[id] = nil end -- reprise après l'entrée : une quête de la Compagnie
    local f = fenetreQuete
    if f and f.id == id and f.origine.nom and not (base()[id] or {}).objet then noterOrigine(id, f.origine) end
    -- Reprendre une quête que j'avais écartée, c'est la remettre (#21) : datée et annoncée.
    local d = id and e.db.compagnie and e.db.ecartees and e.db.ecartees[id]
    if d and d.ecartee and d.par == prenom(moi()) then decider(id, false) end
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

-- Les réglages (page de Compagnie dans les réglages fusionnés, faite une fois à l'entrée en jeu) : l'acceptation
-- automatique (#26).
local function reglages(page, ancre)
  local cb = CreateFrame("CheckButton", "CompagnieAccepteAuto", page, "UICheckButtonTemplate")
  cb:SetSize(26, 26)
  cb:SetPoint("TOPLEFT", ancre, "BOTTOMLEFT", 0, -14)
  local t = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  t:SetPoint("LEFT", cb, "RIGHT", 4, 0)
  t:SetText("Accepter tout seul une quête qu'un autre membre a déjà (partage, PNJ, escorte)")
  cb:SetChecked(e.db.accepteAuto ~= false)
  cb:SetScript("OnClick", function(self) e.db.accepteAuto = self:GetChecked() and true or false end)
end
AC.Regrouper({ nom = "Compagnie", dossier = "Compagnie", icone = "Interface\\Icons\\INV_Misc_Note_01", ouvrir = function() ouvrir() end,
  reglages = reglages })

SLASH_COMPAGNIE1 = "/compagnie"
SlashCmdList.COMPAGNIE = function(msg)
  local cmd = (msg or ""):match("^%s*(%S*)"):lower()
  if cmd == "fonder" then return fonder() end
  if cmd == "quitter" then return ns.quitter(e, jeu) end
  if cmd == "suivi" then return basculerMode() end
  if cmd == "zone" then return choisirZoneEnCours() end
  ouvrir()
end
