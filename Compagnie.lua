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

local dessiner
local jeu = {
  envoyer = function(texte)
    if IsInGroup() then C_ChatInfo.SendAddonMessage(PREFIXE, texte, IsInRaid() and "RAID" or "PARTY") end
  end,
  dire = function(texte) print("|cffa78ffcCompagnie :|r " .. texte) end,
  proposer = function(p) StaticPopup_Show(p.deja and "COMPAGNIE_DEJA" or "COMPAGNIE_PROPOSITION", p.nom) end,
  maj = function() ns.majCompagnie() end, -- la Compagnie a changé (fondée, quittée, un membre retiré)
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
local function monEtat()
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
      quetes[id] = { finie = finie, objectifs = objectifs, zone = zone }
      titres[id] = info.title
    end
  end
  -- Rendues : parmi les quêtes des autres membres, celles que j'ai déjà rendues (pas tout l'historique : il ne tient
  -- pas dans un message).
  for _, etat in pairs(e.db.etats or {}) do
    for id in pairs(etat.quetes or {}) do
      if not quetes[id] and C_QuestLog.IsQuestFlaggedCompleted(id) then rendues[id] = true end
    end
  end
  return { niveau = UnitLevel("player"), quetes = quetes, rendues = rendues }
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

local redessiner -- plus bas
local envoi = {
  programmer = function(delai, fn) C_Timer.After(delai, fn) end,
  monEtat = monEtat,
  envoyerEtat = function(texte) return diffuser(texte) end,
}
local reception = {
  maj = function() redessiner() end,
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
-- Le suivi du mode Compagnie : une fenêtre du socle en deux parties, À faire en haut (vide jusqu'à la tranche
-- suivante), les quêtes de la Compagnie en dessous, avec leur avancement commun. Personne n'est nommé, sauf un absent qui
-- manque (« En attente de Léo ») : jamais qui est en retard ni en avance.
local masquageInterne = false
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

-- Le texte des quêtes de la Compagnie, calculé depuis mon journal et les derniers états connus.
local function texteSuivi()
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
  local calc, ordre, lignes = ns.calculer(liste), {}, {}
  local function titre(id) return titres[id] or C_QuestLog.GetTitleForQuestID(id) or ("Quête " .. id) end
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
    lignes[#lignes + 1] = "|cffffd100" .. titre(id) .. "|r"
    for i, o in ipairs(q.objectifs) do lignes[#lignes + 1] = ligneObjectif(i, o) end
    local attente = {}
    for _, guid in ipairs(q.enAttente) do
      if guid ~= moi() and not presents[guid] then attente[#attente + 1] = prenom(guid) end
    end
    if q.aRendre then lignes[#lignes + 1] = "  |cff59cc73À rendre|r"
    elseif #attente > 0 then lignes[#lignes + 1] = "  |cff999999En attente de " .. table.concat(attente, ", ") .. "|r" end
  end
  if #lignes > 0 then return table.concat(lignes, "\n") end
  return voir and "|cff999999Aucune quête de la Compagnie dans cette zone.|r" or "|cff999999Aucune quête en cours.|r"
end

local function dessinerSuivi()
  local f = CompagnieSuiviFrame
  if not (f and f:IsShown() and e.db.compagnie) then return end
  CompagnieSuiviQuetes:SetText(texteSuivi())
  CompagnieSuiviZone:SetText(libelleZone())
  CompagnieSuiviZone:SetWidth(CompagnieSuiviZone:GetFontString():GetStringWidth() + 22)
  local h = CompagnieSuiviQuetes:GetStringHeight()
  CompagnieSuiviQuetes:GetParent():SetHeight(math.max(1, h))
  f:SetHeight(math.min(110 + h, UIParent:GetHeight() * 0.6))
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
    titreDePartie(f, "À faire", -40)
    -- Le filtre par zone : le titre de la partie Quêtes est la zone affichée ; un clic ouvre juste dessous la liste des
    -- zones de la Compagnie (avec leur nombre de quêtes), un clic en choisit une et la liste se ferme.
    local z = CreateFrame("Button", "CompagnieSuiviZone", f)
    z:SetPoint("TOPLEFT", 14, -68)
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
    defil:SetPoint("TOPLEFT", 14, -92)
    defil:SetPoint("BOTTOMRIGHT", -32, 12)
    local contenu = CreateFrame("Frame", nil, defil)
    contenu:SetSize(244, 1)
    defil:SetScrollChild(contenu)
    local q = contenu:CreateFontString("CompagnieSuiviQuetes", "OVERLAY", "GameFontHighlightSmall")
    q:SetPoint("TOPLEFT")
    q:SetWidth(244)
    q:SetJustifyH("LEFT")
    -- Fermée par sa croix (pas quand l'interface entière est cachée, Alt-Z : elle reste « montrée ») : mode éteint.
    f:HookScript("OnHide", function(self)
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

local function modeActif() return e.db.compagnie ~= nil and e.db.modeCompagnie ~= false end
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
-- La fenêtre : la liste des membres, présent ou absent, « Retirer » sur les autres ; « Fonder » ou « Quitter » ; le mode
-- Compagnie, son état sur son bouton.
local tableau, vide, boutonFonder, boutonQuitter, boutonMode
local COLONNES = {
  { key = "nom", title = "Membre", w = 180, get = function(m) return m.nom end },
  { key = "presence", title = "Présence", w = 80, get = function(m) return m.presence end,
    fmt = function(v) return (v == "présent" and "|cff59cc73" or "|cff999999") .. v .. "|r" end },
  { key = "retirer", w = 80, button = function(m) if m.guid ~= moi() then return "Retirer" end end,
    click = function(m) ns.retirer(e, moi(), m.guid, jeu) end },
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
    local largeur
    tableau, largeur = AC.Tableau(f, COLONNES, { name = "membres", bottom = 44 })
    f:SetWidth(largeur + 50)
    vide = f:CreateFontString("CompagnieVide", "OVERLAY", "GameFontHighlight")
    vide:SetPoint("TOPLEFT", 14, -70)
    vide:SetWidth(largeur)
    vide:SetJustifyH("LEFT")
    vide:SetText("Pas de Compagnie. Dans un groupe du jeu, « Fonder » la propose à chaque personnage du groupe ; " ..
      "elle a de 2 à 5 membres.")
    boutonFonder = bouton(f, "Fonder", fonder)
    boutonQuitter = bouton(f, "Quitter", function() ns.quitter(e, jeu) end)
    boutonMode = bouton(f, "Mode Compagnie", basculerMode, 170, "CompagnieModeBouton")
    boutonMode:ClearAllPoints()
    boutonMode:SetPoint("BOTTOMRIGHT", -14, 12)
  end
  CompagnieFrame:Show()
  dessiner()
end

function redessiner()
  if CompagnieFrame and CompagnieFrame:IsShown() then dessiner() end
  dessinerSuivi()
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
  if not e.db.compagnie then e.db.etats = nil end -- plus de Compagnie : les derniers états connus sont oubliés
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

---------------------------------------------------------------------------------------------------
-- Messages d'add-on. Au groupe du jeu : d'un expéditeur que le serveur y nomme (son GUID vient du groupe) ; en
-- chuchotement : d'un membre, reconnu à son nom « Prénom Nom » donné par le serveur, et seulement pour les états.
local MONJOURNAL = { QUEST_LOG_UPDATE = true, QUEST_TURNED_IN = true, PLAYER_LEVEL_UP = true, UNIT_QUEST_LOG_CHANGED = true }
local cadre = CreateFrame("Frame", "CompagnieMessages")
for _, ev in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE", "QUEST_LOG_UPDATE",
  "QUEST_TURNED_IN", "PLAYER_LEVEL_UP", "UNIT_QUEST_LOG_CHANGED", "PLAYER_REGEN_ENABLED", "ZONE_CHANGED_NEW_AREA" }) do cadre:RegisterEvent(ev) end
cadre:SetScript("OnEvent", function(_, ev, a1, texte, canal, expediteur)
  if ev == "ADDON_LOADED" then
    if a1 == "Compagnie" then
      CompagnieDB = CompagnieDB or {}
      e.db, e.moi = CompagnieDB, moi()
      connectes, chuchotes = {}, {} -- la présence repart de zéro (en jeu, un /reload efface tout l'état Lua)
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
  elseif MONJOURNAL[ev] then
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
