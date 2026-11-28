-- Tests d'intégration dans wow-ui-sim (tools/sim.sh test Compagnie) : Compagnie chargé avec le socle Azeroth Commune.
-- Le groupe du jeu est simulé en bouchonnant les appels du jeu (Léo dans party1) ; les messages d'add-on envoyés sont
-- retenus, ceux de Léo arrivent par l'événement CHAT_MSG_ADDON du cadre CompagnieMessages.
local LEO, MIRA = "Player-1-0000ABCD", "Player-1-0000BCDE"
-- Les champs d'un état ajoutés après le 10e, vides : APRES_ZONE, ceux après la zone de la Compagnie (#27 : mes
-- prérequis manquants ; #23 : la liste des membres ; #6 : les origines) ; FIN, tous (#24 : la zone, puis APRES_ZONE).
local APRES_ZONE = "####"
local FIN = "#" .. APRES_ZONE
-- La fin de mon état, tel qu'il part dans une Compagnie (motif) : zone et prérequis vides, la liste des membres, puis
-- les rendues de la zone (#34) et les origines (#6), vides.
local MIEN = "###%d+=[^#]+##$"

local function moi() return { guid = UnitGUID("player"), nom = AzerothCommune.Personnage().nom } end

-- La base des quêtes du socle est fausse pendant tous les tests (les ids des tests, 1001…, sont de vraies quêtes de la
-- réserve, avec leurs chaînes) : vide, sauf le temps d'un avecBase.
local baseTest, lireDuSocle = {}, AzerothCommune.Lire
AzerothCommune.Lire = function(self, t, ...)
    if t == "base des quêtes" then return baseTest, { provenance = "source externe" } end
    return lireDuSocle(self, t, ...)
end

-- Les lignes affichées de la liste des membres, dans l'ordre : { nom, presence, retirer = bouton ou nil } ; sans les
-- joueurs du groupe à inviter (#23 : le simulateur met le joueur dans un groupe de 5), sauf avecGroupe.
local function lignes(avecGroupe)
    local t = {}
    local function parcourir(f)
        for _, c in ipairs({ f:GetChildren() }) do
            if c.item and c:IsVisible() then t[#t + 1] = c end -- l'onglet affiché
            parcourir(c)
        end
    end
    parcourir(CompagnieFrame)
    table.sort(t, function(a, b) return a:GetTop() > b:GetTop() end)
    local l = {}
    for _, r in ipairs(t) do
        local b = r.cells[3]
        local x = { nom = r.cells[1]:GetText(), presence = r.cells[2]:GetText(), retirer = b:IsShown() and b or nil }
        if avecGroupe or not (x.presence or ""):find("groupe", 1, true) then l[#l + 1] = x end
    end
    return l
end

-- Ce que Compagnie écrit dans le chat pendant f.
local function dits(f)
    local t, garde = {}, print
    print = function(...) t[#t + 1] = table.concat({ ... }, " ") end
    local ok, err = pcall(f)
    print = garde
    if not ok then error(err, 0) end
    return table.concat(t, "\n")
end

-- Mon groupe du jeu le temps de f(envoyes) : autres = { { guid, prénom, nom [, horsLigne = true] [, loin = true] }, … }, {} : hors d'un groupe
-- (le simulateur met le joueur dans un groupe de 5) ; raid : un raid. envoyes : les messages d'add-on partis.
local function avecGroupe(autres, raid, f)
    local g = { GetNumGroupMembers = GetNumGroupMembers, IsInRaid = IsInRaid, IsInGroup = IsInGroup, UnitGUID = UnitGUID,
        UnitName = UnitName, UnitIsConnected = UnitIsConnected, UnitIsVisible = UnitIsVisible, envoi = C_ChatInfo.SendAddonMessage }
    local envoyes = {}
    local function autre(u)
        local i = tonumber(u:match("^party(%d)$") or u:match("^raid(%d+)$"))
        return i and (autres[i] or {}), i
    end
    GetNumGroupMembers = function() return #autres > 0 and #autres + 1 or 0 end
    IsInRaid = function() return raid end
    IsInGroup = function() return #autres > 0 end
    UnitGUID = function(u) local a = autre(u) if a then return a[1] end return g.UnitGUID(u) end
    UnitName = function(u) local a = autre(u) if a then return a[2], a[3] end return g.UnitName(u) end
    UnitIsConnected = function(u) local a = autre(u) if a then return a[1] ~= nil and not a.horsLigne end return g.UnitIsConnected(u) end
    UnitIsVisible = function(u) local a = autre(u) if a then return a[1] ~= nil and not a.horsLigne and not a.loin end return g.UnitIsVisible(u) end
    C_ChatInfo.SendAddonMessage = function(prefixe, texte, canal, cible)
        envoyes[#envoyes + 1] = { prefixe = prefixe, texte = texte, canal = canal, cible = cible }
    end
    local ok, err = pcall(f, envoyes)
    GetNumGroupMembers, IsInRaid, IsInGroup, UnitGUID, UnitName, UnitIsConnected, UnitIsVisible =
        g.GetNumGroupMembers, g.IsInRaid, g.IsInGroup, g.UnitGUID, g.UnitName, g.UnitIsConnected, g.UnitIsVisible
    C_ChatInfo.SendAddonMessage = g.envoi
    if not ok then error(err, 0) end
end
-- Léo (connecté) seul avec moi dans mon groupe du jeu.
local function avecLeo(f) avecGroupe({ { LEO, "Léo", "Lame" } }, false, f) end

-- Un message d'add-on reçu au groupe du jeu, de Léo par défaut.
local function recu(texte, de)
    CompagnieMessages:GetScript("OnEvent")(CompagnieMessages, "CHAT_MSG_ADDON", "Compagnie", texte, "PARTY", de or "Léo Lame")
end

local function fabriquer(...)
    CompagnieDB.compagnie = { id = "essai", membres = { moi(), ... } }
end
-- La fenêtre de la Compagnie sur l'onglet Membres (2) ou Écartées (3) : /compagnie l'ouvre sur Chaînes (#33).
local function membres(vue)
    SlashCmdList.COMPAGNIE("")
    local f = CompagnieChainesFrame and CompagnieChainesFrame:IsShown() and "CompagnieChainesFrame" or "CompagnieFrame"
    _G[f .. "Tab" .. (vue or 2)]:Click()
end

test("Compagnie se charge : /compagnie, regroupé avec le socle, la Compagnie par personnage", function()
    assertEquals("/compagnie", SLASH_COMPAGNIE1)
    assertType("function", SlashCmdList.COMPAGNIE)
    assertType("table", CompagnieDB)
    local regroupe
    for _, r in ipairs(AzerothCommune.regroupes) do if r.nom == "Compagnie" then regroupe = r end end
    assertNotNil(regroupe, "Compagnie regroupé")
    assertEquals("Compagnie", regroupe.dossier)
    local meta = C_AddOns.GetAddOnMetadata
    assertEquals("AzerothCommune", meta("Compagnie", "Dependencies"))
    assertEquals("CompagnieDB", meta("Compagnie", "SavedVariablesPerCharacter"))
    assertTrue((meta("Compagnie", "X-AzerothCommune") or ""):find("Arbre", 1, true) ~= nil, "la version du socle qui a l'Arbre (#33)")
    assertType("function", AzerothCommune.Arbre) -- le socle chargé l'a
end)

test("la commande répond : sans Compagnie, la fenêtre le dit et propose de fonder", function()
    CompagnieDB.compagnie = nil
    SlashCmdList.COMPAGNIE("")
    assertTrue(CompagnieFrame:IsShown())
    assertEquals(0, #lignes())
    assertTrue(CompagnieVide:IsShown())
    CompagnieFrame:Hide()
end)

test("la liste des membres se dessine depuis une Compagnie fabriquée : présent, absent, Retirer", function()
    fabriquer({ guid = LEO, nom = "Léo Lame" })
    membres()
    local l = lignes()
    assertEquals(2, #l)
    assertEquals(moi().nom, l[1].nom)
    assertTrue(l[1].presence:find("présent", 1, true) ~= nil, l[1].presence)
    assertNil(l[1].retirer, "on ne se retire pas soi-même")
    assertEquals("Léo Lame", l[2].nom)
    assertTrue(l[2].presence:find("absent", 1, true) ~= nil, "hors de mon groupe : absent")
    assertEquals("Retirer", l[2].retirer:GetText())
    assertTrue(not CompagnieVide:IsShown())
    -- Léo entre dans mon groupe du jeu : présent.
    avecLeo(function()
        CompagnieMessages:GetScript("OnEvent")(CompagnieMessages, "GROUP_ROSTER_UPDATE")
        assertTrue(lignes()[2].presence:find("présent", 1, true) ~= nil, "dans mon groupe : présent")
    end)
    CompagnieFrame:Hide()
    CompagnieDB.compagnie = nil
end)

test("Fonder hors d'un groupe, ou avec plus de 5 personnages, est refusé avec un message clair", function()
    CompagnieDB.compagnie = nil
    avecGroupe({}, false, function(envoyes)
        local t = dits(function() SlashCmdList.COMPAGNIE("fonder") end)
        assertTrue(t:find("groupe du jeu", 1, true) ~= nil, t)
        assertEquals(0, #envoyes)
    end)
    local raid = {}
    for i = 1, 5 do raid[i] = { ("Player-1-0000F00%d"):format(i), "Membre" .. i, "Raid" } end
    avecGroupe(raid, true, function(envoyes)
        local t = dits(function() SlashCmdList.COMPAGNIE("fonder") end)
        assertTrue(t:find("au plus 5 membres : ton groupe compte 6", 1, true) ~= nil, t)
        assertEquals(0, #envoyes)
    end)
    assertNil(CompagnieDB.compagnie)
end)

test("fonder avec Léo : la proposition part au groupe du jeu, Léo accepte, la Compagnie est fondée", function()
    CompagnieDB.compagnie = nil
    avecLeo(function(envoyes)
        dits(function() SlashCmdList.COMPAGNIE("fonder") end)
        local p = envoyes[1]
        assertEquals("Compagnie", p.prefixe)
        assertEquals("PARTY", p.canal)
        local id = p.texte:match("^P;([^;]+);" .. moi().guid:gsub("%-", "%%-") .. "," .. LEO:gsub("%-", "%%-") .. "$")
        assertNotNil(id, p.texte)
        recu("A;" .. id, "Mira Feuille") -- pas dans mon groupe : ignoré
        assertNil(CompagnieDB.compagnie)
        local t = dits(function() recu("A;" .. id) end)
        assertTrue(t:find("Compagnie fondée", 1, true) ~= nil, t)
        assertEquals("F;" .. id .. ";" .. moi().guid .. "," .. LEO, envoyes[2].texte)
        local c = CompagnieDB.compagnie
        assertEquals(2, #c.membres)
        assertEquals("Léo Lame", c.membres[2].nom)
        assertEquals(LEO, c.membres[2].guid)
        assertType("table", CompagnieDB.avant, "mes quêtes d'avant sont notées à mon entrée")
    end)
end)

test("quitter et retirer mettent à jour la liste", function()
    fabriquer({ guid = LEO, nom = "Léo Lame" }, { guid = MIRA, nom = "Mira Feuille" })
    avecLeo(function(envoyes)
        membres()
        assertEquals(3, #lignes())
        dits(function() recu("Q;essai") end) -- Léo quitte
        local l = lignes()
        assertEquals(2, #l)
        assertEquals("Mira Feuille", l[2].nom)
        fabriquer({ guid = LEO, nom = "Léo Lame" }, { guid = MIRA, nom = "Mira Feuille" })
        membres()
        dits(function() lignes()[3].retirer:Click() end) -- je retire Mira
        assertEquals("X;essai;" .. MIRA, envoyes[#envoyes].texte)
        assertEquals(2, #lignes())
        dits(function() recu("X;essai;" .. moi().guid) end) -- Léo me retire
        assertNil(CompagnieDB.compagnie)
        assertEquals(0, #lignes())
        assertTrue(CompagnieVide:IsShown())
        fabriquer({ guid = LEO, nom = "Léo Lame" })
        dits(function() SlashCmdList.COMPAGNIE("quitter") end)
        assertEquals("Q;essai", envoyes[#envoyes].texte)
        assertNil(CompagnieDB.compagnie)
    end)
    CompagnieFrame:Hide()
end)

test("une proposition reçue : refuser, accepter puis fondée ; déjà membre, elle le dit et le refus part tout seul", function()
    CompagnieDB.compagnie = nil
    avecLeo(function(envoyes)
        recu("P;p0;" .. LEO .. "," .. moi().guid)
        local _, popup = StaticPopup_Visible("COMPAGNIE_PROPOSITION")
        assertNotNil(popup, "proposition affichée")
        popup.button2:Click() -- Refuser
        assertEquals("R;p0", envoyes[#envoyes].texte)
        recu("P;p1;" .. LEO .. "," .. moi().guid)
        _, popup = StaticPopup_Visible("COMPAGNIE_PROPOSITION")
        popup.button1:Click() -- Accepter
        assertEquals("A;p1", envoyes[#envoyes].texte)
        assertNil(CompagnieDB.compagnie, "pas encore fondée")
        dits(function() recu("F;p1;" .. LEO .. "," .. moi().guid) end)
        assertEquals("p1", CompagnieDB.compagnie.id)
        assertEquals("Léo Lame", CompagnieDB.compagnie.membres[1].nom)
        CompagnieDB.compagnie = nil
        fabriquer({ guid = MIRA, nom = "Mira Feuille" })
        recu("P;p2;" .. LEO .. "," .. moi().guid)
        assertTrue(StaticPopup_Visible("COMPAGNIE_DEJA") ~= nil, "la proposition dit : déjà membre")
        assertEquals("R;p2;deja", envoyes[#envoyes].texte)
        StaticPopup_Hide("COMPAGNIE_DEJA")
    end)
    CompagnieDB.compagnie = nil
end)

test("une proposition acceptée tient : une autre reçue avant la fondation est refusée d'office", function()
    CompagnieDB.compagnie = nil
    avecGroupe({ { LEO, "Léo", "Lame" }, { MIRA, "Mira", "Feuille" } }, false, function(envoyes)
        recu("P;p5;" .. LEO .. "," .. moi().guid .. "," .. MIRA)
        local _, popup = StaticPopup_Visible("COMPAGNIE_PROPOSITION")
        popup.button1:Click() -- Accepter
        assertEquals("A;p5", envoyes[#envoyes].texte)
        local t = dits(function() recu("P;p6;" .. MIRA .. "," .. moi().guid .. "," .. LEO, "Mira Feuille") end)
        assertEquals("R;p6;occupe", envoyes[#envoyes].texte)
        assertTrue(t:find("refusé d'office, tu as déjà accepté celle de Léo Lame", 1, true) ~= nil, t)
        assertNil(StaticPopup_Visible("COMPAGNIE_PROPOSITION"), "pas de nouvelle proposition affichée")
        dits(function() recu("F;p5;" .. LEO .. "," .. moi().guid) end)
        assertEquals("p5", CompagnieDB.compagnie.id)
    end)
    CompagnieDB.compagnie = nil
end)

test("une 2e proposition pendant que la 1re est affichée la remplace, et reste à répondre", function()
    CompagnieDB.compagnie = nil
    avecLeo(function(envoyes)
        recu("P;p3;" .. LEO .. "," .. moi().guid)
        recu("P;p4;" .. LEO .. "," .. moi().guid)
        assertEquals(0, #envoyes, "aucun refus envoyé tout seul")
        local _, popup = StaticPopup_Visible("COMPAGNIE_PROPOSITION")
        popup.button1:Click()
        assertEquals("A;p4", envoyes[#envoyes].texte)
    end)
end)

test("la Compagnie est retrouvée telle quelle après un /reload (CompagnieDB relue au chargement)", function()
    CompagnieDB = { compagnie = { id = "r1", membres = { moi(), { guid = LEO, nom = "Léo Lame" } } } }
    CompagnieMessages:GetScript("OnEvent")(CompagnieMessages, "ADDON_LOADED", "Compagnie")
    CompagnieMessages:GetScript("OnEvent")(CompagnieMessages, "PLAYER_ENTERING_WORLD")
    membres()
    local l = lignes()
    assertEquals(2, #l)
    assertEquals("Léo Lame", l[2].nom)
    CompagnieFrame:Hide()
    CompagnieDB.compagnie = nil
end)

---------------------------------------------------------------------------------------------------
-- Le mode Compagnie et l'échange des états (#4).

-- Mon journal le temps de f : quetes = { { id, titre, finie, zone, partageable, objectifs = { { text, numFulfilled,
-- numRequired }, … } }, … } (C_QuestLog.GetInfo, GetQuestObjectives, IsComplete, IsPushableQuest… bouchonnés ;
-- info.isComplete reste nil comme sur Forever). Les partages (QuestLogPushQuest) sont retenus dans pousses.
-- Le journal range les quêtes sous des en-têtes de zone (isHeader), dans l'ordre donné ; sans zone, sous ICI, la zone où
-- je suis (GetRealZoneText bouchonné : ici, ou ICI).
local ICI, ici = "Forêt d'Elwynn", nil
local pousses = {}
local function avecJournal(quetes, f)
    local q, g = C_QuestLog, {}
    for _, n in ipairs({ "GetInfo", "GetQuestObjectives", "IsComplete", "IsQuestFlaggedCompleted", "GetTitleForQuestID",
        "IsUnitOnQuest", "IsPushableQuest", "GetLogIndexForQuestID", "GetSelectedQuest", "SetSelectedQuest",
        "GetAbandonQuest" }) do g[n] = q[n] end
    local pousser = QuestLogPushQuest
    local parId, lignes, zone = {}, {}, nil
    for _, x in ipairs(quetes) do
        parId[x.id] = x
        if (x.zone or ICI) ~= zone then zone = x.zone or ICI; lignes[#lignes + 1] = { title = zone, isHeader = true } end
        lignes[#lignes + 1] = { questID = x.id, title = x.titre, isHeader = false }
    end
    local zoneDuJeu = GetRealZoneText
    GetRealZoneText = function() return ici or ICI end
    q.GetInfo = function(i) return lignes[i] end
    q.GetQuestObjectives = function(id)
        local t = {}
        for k, o in ipairs(parId[id] and parId[id].objectifs or {}) do
            t[k] = { text = o[1], numFulfilled = o[2], numRequired = o[3], finished = tonumber(o[2]) == o[3], type = o[4] }
        end
        return t
    end
    q.IsComplete = function(id) return parId[id] and parId[id].finie or false end
    q.IsQuestFlaggedCompleted = function() return false end
    q.GetTitleForQuestID = function() return nil end
    q.IsUnitOnQuest = function() return nil end
    q.IsPushableQuest = function(id) return parId[id] and parId[id].partageable or false end
    q.GetLogIndexForQuestID = function(id) for i, l in ipairs(lignes) do if l.questID == id then return i end end end
    local choisie = 0
    q.GetSelectedQuest = function() return choisie end
    q.SetSelectedQuest = function(id) choisie = id end
    q.GetAbandonQuest = function() return choisie end -- SetAbandonQuest retient la quête choisie
    QuestLogPushQuest = function(i) pousses[#pousses + 1] = i end
    local ok, err = pcall(f)
    for n, fn in pairs(g) do q[n] = fn end
    QuestLogPushQuest = pousser
    GetRealZoneText, ici = zoneDuJeu, nil
    if not ok then error(err, 0) end
end
local function pattes(fait)
    return { id = 1001, titre = "Les pattes de loup", finie = fait == 8, objectifs = { { "Patte de loup : " .. fait .. "/8", fait, 8 } } }
end
local RAPTORS = { id = 95789, titre = "Les raptors", objectifs = { { "Raptor flagellant : 2/10 |4personnage tué:personnages tués;", 2, 10 } } }

-- Le temps s'écoule de s secondes (horloge manuelle du simulateur) : les minuteries programmées partent.
local function ecouler(s)
    pcall(A_Admin.SetManualClock, GetTime()) -- déjà manuelle : sans effet
    A_Admin.AdvanceTime(s)
end
local function evenement(ev, ...) CompagnieMessages:GetScript("OnEvent")(CompagnieMessages, ev, ...) end
local function charger()
    CompagnieMessages:GetScript("OnEvent")(CompagnieMessages, "ADDON_LOADED", "Compagnie")
    CompagnieMessages:GetScript("OnEvent")(CompagnieMessages, "PLAYER_ENTERING_WORLD") -- comme le jeu, juste après
end
local function chuchote(texte, de)
    CompagnieMessages:GetScript("OnEvent")(CompagnieMessages, "CHAT_MSG_ADDON", "Compagnie", texte, "WHISPER", de or "Léo Lame")
end
-- Le texte du suivi : ses lignes affichées (une par quête), dans l'ordre.
local function suivi()
    local t = {}
    for i = 1, 200 do
        local l = _G["CompagnieSuiviLigne" .. i]
        if not (l and l:IsShown()) then break end
        t[#t + 1] = l.texte:GetText() or ""
    end
    return table.concat(t, "\n")
end
-- La ligne du suivi qui commence par ce titre (une quête de la Compagnie : en jaune).
local function ligneSuivi(titre)
    for i = 1, 200 do
        local l = _G["CompagnieSuiviLigne" .. i]
        if not (l and l:IsShown()) then return end
        if (l.texte:GetText() or ""):find(titre, 1, true) then return l end
    end
end
-- Le menu contextuel ouvert pendant f (le vrai s'ouvre, puis est refermé) : rend sa description, avec ses entrées.
local function menuDe(f)
    local vrai, racine = MenuUtil.CreateContextMenu, nil
    MenuUtil.CreateContextMenu = function(owner, gen)
        racine = MenuUtil.CreateRootMenuDescription(MenuVariants.GetDefaultContextMenuMixin())
        gen(owner, racine)
        return vrai(owner, gen)
    end
    local ok, err = pcall(f)
    MenuUtil.CreateContextMenu = vrai
    Menu.GetManager():CloseMenus()
    if not ok then error(err, 0) end
    return racine
end
-- Choisir une entrée d'un menu par son texte ; rend false si elle n'y est pas.
local function choisir(racine, texte)
    if not racine then return false end
    for _, d in racine:EnumerateElementDescriptions() do
        if MenuUtil.GetElementText(d) == texte then d:Pick(MenuInputContext.MouseButton, "LeftButton") return true end
    end
    return false
end
local function contient(t, motif) return t:find(motif, 1, true) ~= nil end
local function eteindre() -- mode éteint, plus de Compagnie : le suivi du jeu revient pour les tests suivants
    CompagnieDB.compagnie, CompagnieDB.etats, CompagnieDB.modeCompagnie, CompagnieDB.ecartees = nil, nil, nil, nil
    CompagnieDB.avant, CompagnieDB.renduesVues, CompagnieDB.zoneCompagnie = nil, nil, nil
    charger()
end

test("le suivi se dessine depuis une Compagnie fabriquée : 5/8, en attente de Léo ; À rendre quand tout le monde a fini", function()
    avecGroupe({}, false, function()
        avecJournal({ pattes(8), RAPTORS }, function()
            fabriquer({ guid = LEO, nom = "Léo Lame" })
            CompagnieDB.modeCompagnie = nil -- activé par défaut dans une Compagnie
            CompagnieDB.etats = { [LEO] = { niveau = 10, rendues = {}, quetes = {
                [1001] = { finie = false, objectifs = { { fait = 5, total = 8 } } },
                [95789] = { finie = false, objectifs = { { fait = 1, total = 10 } } } } } }
            charger()
            assertTrue(CompagnieSuiviFrame:IsShown(), "le suivi s'ouvre en mode Compagnie")
            local t = suivi()
            assertTrue(contient(t, "Les pattes de loup"), t)
            assertTrue(contient(t, "Patte de loup : 5/8"), "avancement commun : " .. t)
            assertTrue(not contient(t, "8/8"), "mon avancement n'est pas affiché : " .. t)
            assertTrue(contient(t, "En attente de Léo"), t)
            assertTrue(not contient(t, "À rendre"), t)
            assertTrue(contient(t, "Raptor flagellant : 1/10 |4personnage tué:personnages tués;"), "texte du jeu, compte commun : " .. t)
            -- Léo a fini (son état arrive par chuchotement) : À rendre chez tout le monde.
            chuchote("E;essai;1/1/1;10#1001:1:8/8;95789:0:1/10########" .. FIN)
            assertEquals(1, CompagnieDB.etats[LEO].quetes[1001].objectifs[1].fait == 8 and 1 or 0, "état reçu gardé")
            t = suivi()
            assertTrue(contient(t, "Patte de loup : 8/8") and contient(t, "À rendre"), t)
            assertTrue(not contient(t, "En attente"), "Léo n'est pas nommé : " .. t)
            -- Un état d'un non-membre ne change rien.
            chuchote("E;essai;1/1/1;10#1001:0:0/8########" .. FIN, "Zoé Pierre")
            assertTrue(contient(suivi(), "À rendre"), "non-membre ignoré")
        end)
    end)
    eteindre()
end)

test("le suivi du jeu est masqué en mode Compagnie et revient quand on l'éteint", function()
    eteindre()
    ObjectiveTrackerFrame:Show()
    assertTrue(ObjectiveTrackerFrame:IsShown())
    avecGroupe({}, false, function()
        avecJournal({ pattes(3) }, function()
            fabriquer({ guid = LEO, nom = "Léo Lame" })
            charger()
            assertTrue(not ObjectiveTrackerFrame:IsShown(), "masqué en mode Compagnie")
            ObjectiveTrackerFrame:Show() -- le jeu le remontre
            assertTrue(not ObjectiveTrackerFrame:IsShown(), "recaché aussitôt")
            dits(function() SlashCmdList.COMPAGNIE("suivi") end)
            assertEquals(false, CompagnieDB.modeCompagnie)
            assertTrue(ObjectiveTrackerFrame:IsShown(), "éteint : le suivi du jeu revient")
            assertTrue(not CompagnieSuiviFrame:IsShown())
            -- Le bouton de la fenêtre des membres porte l'état du mode, et le bascule.
            membres()
            assertTrue(contient(CompagnieModeBouton:GetText(), "non"), CompagnieModeBouton:GetText())
            CompagnieModeBouton:Click()
            assertTrue(contient(CompagnieModeBouton:GetText(), "oui"), CompagnieModeBouton:GetText())
            assertTrue(not ObjectiveTrackerFrame:IsShown() and CompagnieSuiviFrame:IsShown(), "rallumé")
            CompagnieFrame:Hide()
            -- Le « – » du suivi éteint le mode.
            dits(function() CompagnieSuiviFrame.entete.MinimizeButton:Click() end)
            assertEquals(false, CompagnieDB.modeCompagnie)
            assertTrue(ObjectiveTrackerFrame:IsShown(), "fermé : le suivi du jeu revient")
            -- Quitter la Compagnie le rend aussi.
            CompagnieDB.modeCompagnie = nil
            charger()
            assertTrue(not ObjectiveTrackerFrame:IsShown())
            dits(function() SlashCmdList.COMPAGNIE("quitter") end)
            assertTrue(ObjectiveTrackerFrame:IsShown(), "plus de Compagnie : le suivi du jeu revient")
        end)
    end)
    eteindre()
end)

test("le dernier état connu d'un absent est retrouvé après un /reload et compte dans l'avancement commun", function()
    avecGroupe({}, false, function()
        avecJournal({ pattes(8) }, function()
            fabriquer({ guid = LEO, nom = "Léo Lame" })
            CompagnieDB.etats = nil
            charger()
            chuchote("E;essai;1/1/1;10#1001:0:5/8########" .. FIN)
            -- /reload : CompagnieDB relue (une copie, comme le fichier de sauvegarde), Léo ne s'est pas reconnecté.
            local function copie(t)
                if type(t) ~= "table" then return t end
                local c = {}
                for k, v in pairs(t) do c[copie(k)] = copie(v) end
                return c
            end
            CompagnieDB = copie(CompagnieDB)
            charger()
            assertEquals(5, CompagnieDB.etats[LEO].quetes[1001].objectifs[1].fait)
            assertTrue(contient(suivi(), "Patte de loup : 5/8"), suivi())
            assertTrue(contient(suivi(), "En attente de Léo"), "après le rechargement, Léo est absent : " .. suivi())
        end)
    end)
    eteindre()
end)

test("une demande d'état reçoit le mien : au groupe du jeu, ou chuchoté hors du groupe ; pas à un non-membre", function()
    avecJournal({ pattes(3) }, function()
        avecGroupe({}, false, function(envoyes)
            fabriquer({ guid = LEO, nom = "Léo Lame" })
            charger()
            ecouler(5) -- un envoi resté programmé par un test précédent
            local n = #envoyes
            chuchote("D;essai", "Zoé Pierre")
            ecouler(5)
            assertEquals(n, #envoyes, "non-membre : rien")
            chuchote("D;essai")
            assertEquals(n, #envoyes, "regroupé : rien ne part tout de suite")
            ecouler(5)
            assertEquals(n + 1, #envoyes, "un seul message")
            local m = envoyes[#envoyes]
            assertEquals("WHISPER", m.canal)
            assertEquals("Léo Lame", m.cible)
            assertTrue(m.texte:find("^E;essai;%d+/1/1;%d+[%d:]*#1001:0n:3/8##Forêt d'Elwynn=1001##[^#]*#%d*#%d*##" .. MIEN) ~= nil, m.texte)
        end)
        avecLeo(function(envoyes)
            recu("D;essai")
            ecouler(5)
            local m = envoyes[#envoyes]
            assertNotNil(m, "un état part")
            assertEquals("PARTY", m.canal)
            assertTrue(m.texte:find("^E;essai;") ~= nil, m.texte)
        end)
    end)
    eteindre()
end)

test("une autre version de Compagnie : ma demande dit ma version, son état illisible me prévient une fois", function()
    avecJournal({ pattes(3) }, function()
        avecGroupe({}, false, function(envoyes)
            local ANA = "Player-1-0000CDEF" -- un membre que les autres tests ne connaissent pas (prévenu une fois par session)
            fabriquer({ guid = ANA, nom = "Ana Roche" })
            charger()
            local n = #envoyes
            evenement("PLAYER_ENTERING_WORLD", true, false) -- une connexion : la demande d'état part 3 s plus tard
            ecouler(4)
            local demande
            for i = n + 1, #envoyes do if envoyes[i].texte:find("^D;essai;") then demande = envoyes[i].texte end end
            assertNotNil(demande, "la demande d'état de la connexion part")
            assertTrue(demande:find("^D;essai;[%w%.%-]+$") ~= nil, "avec ma version : " .. demande)
            n = #envoyes
            chuchote("D;essai;v0.1.0-beta99", "Ana Roche")
            local dite = false
            for i = n + 1, #envoyes do if envoyes[i].texte == demande and envoyes[i].cible == "Ana Roche" then dite = true end end
            assertTrue(dite, "une autre version que la mienne : je lui dis la mienne")
            local t = dits(function() chuchote("E;essai;4/1/1;35#######", "Ana Roche"); ecouler(11) end)
            assertTrue(contient(t, "Ana a Compagnie v0.1.0-beta99, toi "), "prévenu avec les deux versions : " .. t)
            t = dits(function() chuchote("E;essai;5/1/1;35#######", "Ana Roche"); ecouler(11) end)
            assertTrue(not contient(t, "Ana a Compagnie"), "une seule fois")
        end)
    end)
    eteindre()
end)

test("un membre hors du groupe entendu puis muet : redemandé, absent au bout de 2 min sans réponse", function()
    avecJournal({ pattes(8) }, function()
        avecGroupe({}, false, function(envoyes)
            fabriquer({ guid = LEO, nom = "Léo Lame" })
            CompagnieDB.etats = nil
            charger()
            ecouler(5)
            chuchote("E;essai;1/1/1;10#1001:0:5/8########" .. FIN)
            assertTrue(not contient(suivi(), "En attente"), "Léo vient d'écrire : présent")
            local n = #envoyes
            ecouler(125)
            ecouler(30)
            local demandes = 0
            for i = n + 1, #envoyes do
                if envoyes[i].texte:find("^D;essai;") and envoyes[i].cible == "Léo Lame" then demandes = demandes + 1 end
            end
            assertTrue(demandes >= 1 and demandes <= 3, "demandé une fois par minute de silence : " .. demandes)
            assertTrue(contient(suivi(), "En attente de Léo"), "sans réponse depuis 2 min : absent, " .. suivi())
            chuchote("E;essai;2/1/1;10#1001:0:5/8########" .. FIN) -- il répond
            assertTrue(not contient(suivi(), "En attente"), "de nouveau présent")
        end)
    end)
    eteindre()
end)

test("un membre du groupe déconnecté n'est pas présent, même entendu il y a peu", function()
    avecJournal({ pattes(8) }, function()
        fabriquer({ guid = LEO, nom = "Léo Lame" })
        charger()
        avecGroupe({}, false, function() chuchote("E;essai;1/1/1;10#1001:0:5/8########" .. FIN) end)
        avecGroupe({ { LEO, "Léo", "Lame", horsLigne = true } }, false, function()
            evenement("GROUP_ROSTER_UPDATE")
            assertTrue(contient(suivi(), "En attente de Léo"), suivi())
        end)
    end)
    eteindre()
end)

test("en combat, le suivi du jeu passe seulement en transparent ; l'état voulu suit la fin du combat", function()
    eteindre()
    ObjectiveTrackerFrame:Show()
    local garde, combat = InCombatLockdown, true
    InCombatLockdown = function() return combat end
    local ok, err = pcall(function()
        avecGroupe({}, false, function()
            avecJournal({ pattes(3) }, function()
                fabriquer({ guid = LEO, nom = "Léo Lame" })
                charger() -- mode Compagnie allumé en combat
                assertTrue(ObjectiveTrackerFrame:IsShown(), "pas de Hide en combat")
                assertEquals(0, ObjectiveTrackerFrame:GetAlpha())
                ObjectiveTrackerFrame:Show() -- le jeu le remontre en combat
                assertTrue(ObjectiveTrackerFrame:IsShown() and ObjectiveTrackerFrame:GetAlpha() == 0, "toujours transparent")
                combat = false
                evenement("PLAYER_REGEN_ENABLED")
                assertTrue(not ObjectiveTrackerFrame:IsShown(), "hors combat : masqué")
                assertEquals(1, ObjectiveTrackerFrame:GetAlpha())
                combat = true
                dits(function() SlashCmdList.COMPAGNIE("suivi") end) -- éteint en combat
                assertTrue(not ObjectiveTrackerFrame:IsShown(), "pas de Show en combat")
                combat = false
                evenement("PLAYER_REGEN_ENABLED")
                assertTrue(ObjectiveTrackerFrame:IsShown() and ObjectiveTrackerFrame:GetAlpha() == 1, "hors combat : rétabli")
            end)
        end)
    end)
    InCombatLockdown = garde
    eteindre()
    if not ok then error(err, 0) end
end)

test("les envois d'une rafale d'événements sont regroupés en un seul message", function()
    avecLeo(function(envoyes)
        avecJournal({ pattes(1) }, function()
            fabriquer({ guid = LEO, nom = "Léo Lame" })
            charger()
            ecouler(5)
        end)
        avecJournal({ pattes(2) }, function()
            local n = #envoyes
            for _ = 1, 20 do evenement("QUEST_LOG_UPDATE") end
            assertEquals(n, #envoyes, "rien ne part pendant la rafale")
            ecouler(5)
            assertEquals(n + 1, #envoyes, "un seul message")
            assertEquals("PARTY", envoyes[#envoyes].canal)
            assertTrue(envoyes[#envoyes].texte:find("#1001:0n:2/8#", 1, true) ~= nil, envoyes[#envoyes].texte)
        end)
    end)
    eteindre()
end)

test("quitter la Compagnie oublie les derniers états connus", function()
    fabriquer({ guid = LEO, nom = "Léo Lame" })
    CompagnieDB.etats = { [LEO] = { niveau = 10, quetes = {}, rendues = {} } }
    avecGroupe({}, false, function() dits(function() SlashCmdList.COMPAGNIE("quitter") end) end)
    assertNil(CompagnieDB.etats)
    eteindre()
end)

test("un texte d'objectif qui n'a pas mon compte exact ne montre aucun compte que le commun", function()
    avecGroupe({}, false, function()
        avecJournal({ { id = 1001, titre = "Les pattes de loup", objectifs = { { "Patte de loup : 7/8", 8, 8 } } },
            { id = 1002, titre = "Les crocs", objectifs = { { "Croc de loup : 3/4", "3", 4 } } } }, function()
            fabriquer({ guid = LEO, nom = "Léo Lame" })
            CompagnieDB.etats = { [LEO] = { niveau = 10, rendues = {}, quetes = {
                [1001] = { finie = false, objectifs = { { fait = 5, total = 8 } } },
                [1002] = { finie = false, objectifs = { { fait = 1, total = 4 } } } } } }
            charger()
            local t = suivi()
            assertTrue(contient(t, "Patte de loup : 5/8") and not contient(t, "7/8") and not contient(t, "8/8"), t)
            assertTrue(contient(t, "Croc de loup : 1/4") and not contient(t, "3/4"), t)
        end)
    end)
    eteindre()
end)

test("IsUnitOnQuest corrige un membre du groupe en vue ; trop loin, son « non » ne compte pas", function()
    avecJournal({ pattes(8) }, function()
        C_QuestLog.IsUnitOnQuest = function() return false end -- rendu par avecJournal
        fabriquer({ guid = LEO, nom = "Léo Lame" })
        CompagnieDB.etats = { [LEO] = { niveau = 10, rendues = {}, quetes = {
            [1001] = { finie = false, objectifs = { { fait = 5, total = 8 } } } } } }
        charger()
        avecGroupe({ { LEO, "Léo", "Lame", loin = true } }, false, function()
            evenement("GROUP_ROSTER_UPDATE")
            assertTrue(contient(suivi(), "Patte de loup : 5/8"), "trop loin : son état tient, " .. suivi())
        end)
        avecGroupe({ { LEO, "Léo", "Lame" } }, false, function()
            evenement("GROUP_ROSTER_UPDATE")
            assertTrue(contient(suivi(), "Patte de loup : 0/8"), "en vue, il n'a plus la quête : 0/8, " .. suivi())
        end)
    end)
    eteindre()
end)

test("la suggestion Questie n'apparaît qu'une fois et ne modifie aucune option de Questie", function()
    local ecrits = {}
    local profil = setmetatable({}, { __index = { trackerEnabled = true },
        __newindex = function(t, k, v) ecrits[#ecrits + 1] = k; rawset(t, k, v) end })
    Questie = { db = { profile = profil } }
    local ok, err = pcall(function()
        avecGroupe({}, false, function()
            avecJournal({}, function()
                fabriquer({ guid = LEO, nom = "Léo Lame" })
                CompagnieDB.questieSuggere = nil
                local t = dits(charger)
                assertTrue(contient(t, "Questie"), "suggestion : " .. t)
                t = dits(function()
                    charger()
                    SlashCmdList.COMPAGNIE("suivi")
                    SlashCmdList.COMPAGNIE("suivi")
                    CompagnieDB.questieSuggere = CompagnieDB.questieSuggere -- /reload : le drapeau est sauvegardé
                    charger()
                end)
                assertTrue(not contient(t, "Questie"), "une seule fois : " .. t)
            end)
        end)
    end)
    Questie = nil
    eteindre()
    if not ok then error(err, 0) end
    assertEquals(0, #ecrits, "aucune option de Questie écrite")
    assertNil(next(profil), "profil de Questie intact")
end)

test("beaucoup de quêtes : le suivi s'arrête à 60 % de l'écran et les quêtes défilent", function()
    avecGroupe({}, false, function()
        local beaucoup = {}
        for i = 1, 30 do beaucoup[i] = { id = 2000 + i, titre = "Quête " .. i, objectifs = { { "Truc : 0/5", 0, 5 } } } end
        avecJournal(beaucoup, function()
            fabriquer({ guid = LEO, nom = "Léo Lame" })
            CompagnieDB.modeCompagnie = nil
            charger()
            assertTrue(CompagnieSuiviFrame:IsShown(), "le suivi est ouvert")
            assertTrue(CompagnieSuiviContenu:GetHeight() > UIParent:GetHeight() * 0.6, "assez de quêtes pour dépasser")
            assertTrue(CompagnieSuiviFrame:GetHeight() <= UIParent:GetHeight() * 0.6 + 0.5,
                "hauteur bornée : " .. CompagnieSuiviFrame:GetHeight() .. " / écran " .. UIParent:GetHeight())
            assertTrue(CompagnieSuiviDefil:GetVerticalScrollRange() > 0, "les quêtes défilent")
        end)
    end)
    eteindre()
end)

test("suivi par zone : la zone en cours par défaut, une autre zone, toutes ; la quête de Léo ; le choix survit au rechargement", function()
    avecGroupe({}, false, function()
        avecJournal({ pattes(3), { id = 3001, titre = "Les Défias", zone = "Marche de l'Ouest", objectifs = { { "Défias : 1/10", 1, 10 } } } }, function()
            fabriquer({ guid = LEO, nom = "Léo Lame" })
            CompagnieDB.modeCompagnie, CompagnieDB.zoneSuivi = nil, nil
            -- Léo a les deux quêtes, plus une que je n'ai pas : rangée dans son journal sous Forêt d'Elwynn.
            CompagnieDB.etats = { [LEO] = { niveau = 10, rendues = {}, quetes = {
                [1001] = { finie = false, objectifs = { { fait = 3, total = 8 } } },
                [3001] = { finie = false, objectifs = { { fait = 1, total = 10 } } },
                [4001] = { finie = false, objectifs = {}, zone = "Forêt d'Elwynn" },
                [5001] = { finie = false, objectifs = {} } } } } -- une quête dont la zone n'est pas connue
            C_QuestLog.GetTitleForQuestID = function(id) return ({ [4001] = "La quête de Léo", [5001] = "Sans zone" })[id] end
            charger()
            local t = suivi()
            assertTrue(contient(t, "Les pattes de loup") and contient(t, "La quête de Léo"), "zone en cours : " .. t)
            assertTrue(not contient(t, "Les Défias") and not contient(t, "Sans zone"), "pas les autres zones : " .. t)
            assertEquals("Zone en cours (Forêt d'Elwynn)", CompagnieSuiviZone:GetText())
            assertTrue(not CompagnieSuiviZones:IsShown(), "la liste est fermée")
            CompagnieSuiviZone:Click() -- le titre ouvre la liste des zones
            assertTrue(CompagnieSuiviZones:IsShown(), "le titre ouvre la liste")
            assertEquals("Zone en cours (Forêt d'Elwynn)", CompagnieSuiviZonesLigne1:GetText())
            assertEquals("2", CompagnieSuiviZonesLigne1.n:GetText(), "deux quêtes ici")
            assertEquals("Marche de l'Ouest", CompagnieSuiviZonesLigne2:GetText())
            assertEquals("Toutes les zones", CompagnieSuiviZonesLigne3:GetText())
            assertEquals("4", CompagnieSuiviZonesLigne3.n:GetText(), "quatre quêtes en tout")
            CompagnieSuiviZonesLigne2:Click()
            assertTrue(not CompagnieSuiviZones:IsShown(), "un choix ferme la liste")
            t = suivi()
            assertEquals("Marche de l'Ouest", CompagnieSuiviZone:GetText())
            assertTrue(contient(t, "Les Défias") and not contient(t, "Les pattes de loup"), t)
            CompagnieSuiviZone:Click()
            CompagnieSuiviZonesLigne3:Click() -- toutes les zones
            t = suivi()
            assertEquals("Toutes les zones", CompagnieSuiviZone:GetText())
            assertTrue(contient(t, "Les Défias") and contient(t, "Les pattes de loup") and contient(t, "Sans zone"), t)
            -- Le choix est gardé par personnage : retrouvé après un /reload.
            CompagnieDB.zoneSuivi = "Marche de l'Ouest"
            charger()
            assertEquals("Marche de l'Ouest", CompagnieSuiviZone:GetText(), "le choix survit au rechargement")
            assertTrue(not contient(suivi(), "Les pattes de loup"), suivi())
            CompagnieSuiviZone:Click()
            CompagnieSuiviZonesLigne1:Click() -- retour à la zone en cours
            assertEquals("Zone en cours (Forêt d'Elwynn)", CompagnieSuiviZone:GetText())
            assertNil(CompagnieDB.zoneSuivi)
            -- « Zone en cours » suit le joueur : il entre dans la Marche de l'Ouest.
            ici = "Marche de l'Ouest"
            evenement("ZONE_CHANGED_NEW_AREA")
            assertEquals("Zone en cours (Marche de l'Ouest)", CompagnieSuiviZone:GetText())
            assertTrue(contient(suivi(), "Les Défias") and not contient(suivi(), "Les pattes de loup"), suivi())
            -- Une zone sans quête de la Compagnie : le suivi le dit.
            ici = "Duskwood"
            evenement("ZONE_CHANGED_NEW_AREA")
            assertTrue(contient(suivi(), "Aucune quête de la Compagnie dans cette zone"), suivi())
        end)
    end)
    CompagnieDB.zoneSuivi = nil
    eteindre()
end)

test("quêtes d'avant (#20) : celles de Léo à part, nommées, avec son avancement ; les miennes aussi ; aucun écart", function()
    local RESTES = { id = 2101, titre = "Les restes du Comté", partageable = true, objectifs = { { "Sanglier : 2/6", 2, 6 } } }
    -- (ids 21xx : les titres vus pendant la session restent, 2001-2030 sont pris par « beaucoup de quêtes »)
    avecJournal({ pattes(3), RESTES }, function()
        fabriquer({ guid = LEO, nom = "Léo Lame" })
        CompagnieDB.modeCompagnie, CompagnieDB.avant = nil, { [2101] = true } -- dans mon journal à mon entrée
        CompagnieDB.etats = { [LEO] = { niveau = 12, rendues = {}, avant = { [2102] = true }, quetes = {
            [1001] = { finie = false, objectifs = { { fait = 3, total = 8 } } },
            [2102] = { finie = true, objectifs = { { fait = 8, total = 8 } }, zone = "Forêt d'Elwynn" } } } }
        C_QuestLog.GetTitleForQuestID = function(id) return id == 2102 and "Le chêne de Teldrassil" or nil end
        -- Le texte de ses objectifs : dans le jeu, même hors de mon journal (il ne part pas avec son état).
        local dansJournal = C_QuestLog.GetQuestObjectives
        C_QuestLog.GetQuestObjectives = function(id)
            if id == 2102 then return { { text = "Gland : 0/8", numFulfilled = 0, numRequired = 8 } } end
            return dansJournal(id)
        end
        avecLeo(function(envoyes)
            charger()
            local t = suivi()
            assertTrue(contient(t, "Les pattes de loup") and contient(t, "Patte de loup : 3/8"), "la quête de la Compagnie : " .. t)
            local apart = t:sub((t:find("À part", 1, true) or #t + 1))
            assertTrue(contient(apart, "Le chêne de Teldrassil (Léo)"), "la quête d'avant de Léo, à part et nommée : " .. t)
            assertTrue(contient(apart, "Gland : 8/8") and contient(apart, "À rendre"), "son avancement, le texte pris dans le jeu, À rendre sans m'attendre : " .. apart)
            assertTrue(contient(apart, "Les restes du Comté (" .. moi().nom:match("^%S+") .. ")") and contient(apart, "Sanglier : 2/6"),
                "la mienne aussi : " .. apart)
            assertTrue(not (CompagnieSuiviAFaire1 and CompagnieSuiviAFaire1:IsShown()), "aucun écart : ni « Partager », ni « Rendue en avance »")
            assertEquals(nil, CompagnieDB.etats[LEO].quetes[2102].objectifs[1].texte, "son dernier état connu n'est pas touché")
            -- Les plaques des monstres : le reste à tuer d'un objectif (Sanglier : 2/6 → 4), rien sur un autre monstre.
            local p, nom = CreateFrame("Frame"), "Sanglier"
            p.unitToken = "nameplate1"
            local vrais = { C_NamePlate.GetNamePlateForUnit, C_NamePlate.GetNamePlates, UnitName, UnitIsPlayer }
            C_NamePlate.GetNamePlateForUnit = function(u) return u == "nameplate1" and p or nil end
            C_NamePlate.GetNamePlates = function() return { p } end
            UnitName = function(u) if u == "nameplate1" then return nom end return vrais[3](u) end
            UnitIsPlayer = function(u) return u ~= "nameplate1" and vrais[4](u) end
            local ok, err = pcall(function()
                evenement("GROUP_ROSTER_UPDATE") -- un redessin (en jeu : à chaque changement du journal ou d'un état)
                evenement("NAME_PLATE_UNIT_ADDED", "nameplate1")
                assertEquals("4", p.compagnie and p.compagnie:GetText())
                nom = "Loup"
                evenement("NAME_PLATE_UNIT_ADDED", "nameplate1")
                assertEquals("", p.compagnie:GetText() or "")
            end)
            C_NamePlate.GetNamePlateForUnit, C_NamePlate.GetNamePlates, UnitName, UnitIsPlayer = unpack(vrais)
            if not ok then error(err, 0) end
            evenement("QUEST_LOG_UPDATE")
            ecouler(5)
            assertTrue(envoyes[#envoyes].texte:find("#2101#" .. MIEN) ~= nil, "mon état porte ma quête d'avant : " .. envoyes[#envoyes].texte)
        end)
    end)
    CompagnieDB.avant = nil
    eteindre()
end)

---------------------------------------------------------------------------------------------------
-- La liste À faire (#5) : quête à partager, quête écartée (#21).
local KOBOLDS = { id = 1003, titre = "Les Kobolds", partageable = true, objectifs = { { "Bougie : 0/8", 0, 8 } } }
-- Le simulateur n'a ni SetAbandonQuest ni AbandonQuest : bouchonnés ici, avant le prochain chargement (ADDON_LOADED),
-- où Compagnie s'y accroche. abandons : les abandons faits.
local abandons = 0
C_QuestLog.SetAbandonQuest = C_QuestLog.SetAbandonQuest or function() end
C_QuestLog.AbandonQuest = C_QuestLog.AbandonQuest or function() abandons = abandons + 1 end
local function bouton(nom) local b = _G[nom] return b and b:IsShown() and b or nil end

test("la liste À faire se dessine avec ses boutons ; aucun abandon sans un clic ; un écart résorbé disparaît", function()
    avecJournal({ pattes(3), KOBOLDS }, function()
        fabriquer({ guid = LEO, nom = "Léo Lame" }, { guid = MIRA, nom = "Mira Feuille" })
        CompagnieDB.modeCompagnie = nil
        -- Léo a les pattes, pas les Kobolds ; Mira (absente) a les pattes.
        CompagnieDB.etats = {
            [LEO] = { niveau = 5, rendues = {}, quetes = { [1001] = { finie = false, objectifs = { { fait = 0, total = 8 } } } } },
            [MIRA] = { niveau = 5, rendues = {}, quetes = { [1001] = { finie = false, objectifs = { { fait = 0, total = 8 } } } } } }
        avecGroupe({}, false, function()
            charger()
            local b = assert(bouton("CompagnieSuiviAFaire1"), "un bouton À faire")
            assertEquals("Partager en groupe : Les Kobolds", b:GetText())
            assertTrue(not b:IsEnabled(), "personne qui ne l'a pas n'est dans mon groupe : inactif")
            assertNil(bouton("CompagnieSuiviAFaire2"), "les pattes ne sont pas partageables : pas d'écart")
        end)
        avecLeo(function(envoyes)
            evenement("GROUP_ROSTER_UPDATE")
            local b = bouton("CompagnieSuiviAFaire1")
            assertEquals("Partager : Les Kobolds", b:GetText())
            assertTrue(b:IsEnabled(), "Léo est dans mon groupe : actif")
            local n = #pousses
            b:Click()
            assertEquals(n + 1, #pousses, "partagée")
            assertEquals(3, pousses[#pousses], "la ligne des Kobolds dans mon journal (en-tête, pattes, Kobolds)")
            -- Léo accepte les Kobolds et abandonne les pattes (il les écarte) : son état le dit, le chat aussi.
            local t = dits(function() chuchote("E;essai;3/1/1;5#1003:0:0/8###1001:1:100:Léo#####" .. FIN) end)
            assertTrue(CompagnieDB.ecartees[1001].ecartee, "la décision de Léo est celle de la Compagnie")
            assertTrue(contient(t, "Léo a écarté « Les pattes de loup » pour la Compagnie."), t)
            local a = bouton("CompagnieSuiviAFaire1")
            assertEquals("Abandonner aussi : Les pattes de loup", a and a:GetText())
            assertTrue(a:IsEnabled())
            assertEquals("Partager en groupe : Les Kobolds", bouton("CompagnieSuiviAFaire2"):GetText(), "Mira ne l'a pas encore")
            assertTrue(not bouton("CompagnieSuiviAFaire2"):GetFontString():CanWordWrap(), "une seule ligne : un long titre est coupé par « … », pas sur deux lignes")
            -- Aucun abandon sans un clic : ni à la réception, ni au fil des événements et des minuteries.
            for _ = 1, 5 do evenement("QUEST_LOG_UPDATE") end
            ecouler(10)
            assertEquals(0, abandons, "rien n'est abandonné tout seul")
            -- Le clic abandonne cette quête-là ; mon état porte la décision de Léo (pour Mira).
            a:Click()
            assertEquals(0, abandons, "le clic demande confirmation (objets de quête détruits)")
            local _, popup = StaticPopup_Visible("COMPAGNIE_ABANDON")
            assertNotNil(popup, "confirmation affichée")
            StaticPopup_Hide("COMPAGNIE_ABANDON")
            assertEquals(0, abandons, "annulé : rien d'abandonné")
            a:Click()
            _, popup = StaticPopup_Visible("COMPAGNIE_ABANDON")
            popup.button1:Click()
            assertEquals(1, abandons, "confirmé : un abandon")
            assertEquals("Léo", CompagnieDB.ecartees[1001].par, "déjà écartée : pas de nouvelle décision")
            ecouler(5)
            assertTrue(envoyes[#envoyes].texte:find("#1001:1:100:Léo#[^#]*#%d*#%d*##" .. MIEN) ~= nil, "mon état porte l'écartée : " .. envoyes[#envoyes].texte)
            abandons = 0
        end)
        -- Le jeu retire les pattes de mon journal : l'écart est résorbé, il n'apparaît plus.
        avecJournal({ KOBOLDS }, function()
            avecLeo(function()
                chuchote("E;essai;4/1/1;5#1003:0:0/8###1001:1:100:Léo#####" .. FIN)
                local b = bouton("CompagnieSuiviAFaire1")
                assertEquals("Partager en groupe : Les Kobolds", b and b:GetText(), "seul l'écart des Kobolds reste (pour Mira)")
                assertNil(bouton("CompagnieSuiviAFaire2"))
                -- Mira prend les Kobolds : plus rien à faire.
                CompagnieDB.etats[MIRA].quetes[1003] = { finie = false, objectifs = {} }
                evenement("GROUP_ROSTER_UPDATE")
                assertNil(bouton("CompagnieSuiviAFaire1"), "plus de bouton")
                assertTrue(CompagnieSuiviAFaire.vide:IsShown(), "Rien à faire.")
            end)
        end)
    end)
    eteindre()
end)

test("objets à donner : la Compagnie en a assez, qui donne combien à qui ; le clic ouvre l'échange", function()
    local info, compte, echange = C_Item.GetItemInfo, C_Item.GetItemCount, InitiateTrade
    local echanges = {}
    C_Item.GetItemInfo = function(nom) if nom == "Patte de loup" then return nom, nil, 1, 1, 1, "", "", 20, "", 0, 0, 12, 0, 0 end end
    C_Item.GetItemCount = function(nom) return nom == "Patte de loup" and 13 or 0 end
    InitiateTrade = function(u) echanges[#echanges + 1] = u end
    local p = pattes(8)
    p.objectifs[1][4] = "item"
    avecJournal({ p }, function()
        fabriquer({ guid = LEO, nom = "Léo Lame" })
        CompagnieDB.modeCompagnie = nil
        CompagnieDB.etats = { [LEO] = { niveau = 5, rendues = {}, quetes = { [1001] = { finie = false, objectifs = { { fait = 3, total = 8 } } } } } }
        avecLeo(function(envoyes)
            charger()
            evenement("GROUP_ROSTER_UPDATE")
            local b = assert(bouton("CompagnieSuiviAFaire1"), "un bouton À faire")
            assertEquals("Donne 5 Patte de loup à Léo", b:GetText())
            assertTrue(b:IsEnabled(), "Léo est dans mon groupe : actif")
            b:Click()
            assertEquals(1, #echanges, "le clic ouvre l'échange avec Léo")
            evenement("BAG_UPDATE_DELAYED")
            ecouler(5)
            local tout = {} for _, x in ipairs(envoyes) do tout[#tout + 1] = x.texte end
            assertTrue(table.concat(tout, " | "):find(":8/8/13#", 1, true) ~= nil, "mon stock part")
        end)
    end)
    -- Chez Léo : c'est moi qui ai 3/8, il en a 13.
    avecJournal({ pattes(3) }, function()
        CompagnieDB.etats[LEO].quetes[1001] = { finie = true, objectifs = { { fait = 8, total = 8, stock = 13 } } }
        avecLeo(function()
            evenement("GROUP_ROSTER_UPDATE")
            local b = assert(bouton("CompagnieSuiviAFaire1"), "un bouton À faire")
            assertEquals("Léo te donne 5 Patte de loup", b:GetText())
            assertTrue(not b:IsEnabled(), "rien à cliquer pour qui reçoit")
        end)
    end)
    C_Item.GetItemInfo, C_Item.GetItemCount, InitiateTrade = info, compte, echange
    eteindre()
end)

test("mode Compagnie éteint : la petite liste À faire reste visible ; son « – » la ferme jusqu'au prochain changement", function()
    avecGroupe({}, false, function()
        avecJournal({ pattes(3), KOBOLDS }, function()
            fabriquer({ guid = LEO, nom = "Léo Lame" })
            CompagnieDB.modeCompagnie = false
            CompagnieDB.etats = { [LEO] = { niveau = 5, rendues = {}, quetes = { [1001] = { finie = false, objectifs = {} } } } }
            charger()
            assertTrue(not (CompagnieSuiviFrame and CompagnieSuiviFrame:IsShown()), "pas de suivi, mode éteint")
            assertTrue(CompagnieAFaireFrame and CompagnieAFaireFrame:IsShown(), "la petite liste est visible")
            local p = bouton("CompagniePetiteListe1")
            assertEquals("Partager en groupe : Les Kobolds", p:GetText())
            -- Clic droit sur sa ligne (inactive) : le menu Écarter, comme dans le suivi.
            assertTrue(choisir(menuDe(function() p:GetScript("OnMouseUp")(p, "RightButton") end), "Écarter pour la Compagnie"))
            assertNotNil(select(2, StaticPopup_Visible("COMPAGNIE_ECARTER")), "confirmation")
            StaticPopup_Hide("COMPAGNIE_ECARTER")
            -- Léo prend les Kobolds : rien à faire, la petite liste se cache.
            chuchote("E;essai;1/1/1;5#1001:0;1003:0########" .. FIN)
            assertTrue(not CompagnieAFaireFrame:IsShown(), "rien à faire : cachée")
            -- Léo abandonne les pattes : elle revient ; son « – » la ferme, elle reste fermée tant que la liste ne change pas.
            chuchote("E;essai;2/1/1;5#1003:0###1001:1:100:Léo#####" .. FIN)
            assertTrue(CompagnieAFaireFrame:IsShown(), "un écart : visible")
            assertEquals("Abandonner aussi : Les pattes de loup", bouton("CompagniePetiteListe1"):GetText())
            CompagnieAFaireFrame.entete.MinimizeButton:Click() -- son « – »
            evenement("QUEST_LOG_UPDATE")
            ecouler(1)
            evenement("GROUP_ROSTER_UPDATE")
            assertTrue(not CompagnieAFaireFrame:IsShown(), "fermée : elle le reste")
            chuchote("E;essai;3/1/1;5####1001:1:100:Léo;1003:1:101:Léo#####" .. FIN) -- Léo abandonne aussi les Kobolds : la liste change
            assertTrue(CompagnieAFaireFrame:IsShown(), "la liste a changé : de retour")
            assertEquals(0, abandons, "aucun abandon sans clic")
            -- Mode Compagnie rallumé : la petite liste s'efface, le suivi porte les boutons.
            dits(function() SlashCmdList.COMPAGNIE("suivi") end)
            assertTrue(not CompagnieAFaireFrame:IsShown() and CompagnieSuiviFrame:IsShown())
            assertEquals("Abandonner aussi : Les pattes de loup", bouton("CompagnieSuiviAFaire1"):GetText())
            assertEquals("Abandonner aussi : Les Kobolds", bouton("CompagnieSuiviAFaire2"):GetText())
        end)
    end)
    eteindre()
end)

test("abandonner dans le jeu écarte la quête pour la Compagnie, mon état le porte ; ma quête d'avant est seulement oubliée", function()
    local moiPrenom = moi().nom:match("^%S+")
    avecJournal({ pattes(3), { id = 2201, titre = "Mes restes" } }, function()
        fabriquer({ guid = LEO, nom = "Léo Lame" })
        CompagnieDB.avant = { [2201] = true }
        CompagnieDB.etats = { [LEO] = { niveau = 5, rendues = {}, quetes = { [1001] = { finie = false, objectifs = {} } } } }
        avecLeo(function(envoyes)
            charger()
            ecouler(5)
            -- Comme la fenêtre du jeu : la quête choisie, SetAbandonQuest, puis AbandonQuest à la confirmation.
            local t = dits(function()
                C_QuestLog.SetSelectedQuest(1001)
                C_QuestLog.SetAbandonQuest()
                C_QuestLog.AbandonQuest()
            end)
            local d = CompagnieDB.ecartees and CompagnieDB.ecartees[1001]
            assertTrue(d and d.ecartee and d.par == moiPrenom, "écartée par moi")
            assertTrue(contient(t, "Tu as écarté « Les pattes de loup » pour la Compagnie."), t)
            ecouler(5)
            assertTrue(envoyes[#envoyes].texte:find("#1001:1:%d+:" .. moiPrenom .. "#") ~= nil, "mon état porte l'écartée : " .. envoyes[#envoyes].texte)
            -- Je la reprends (QUEST_ACCEPTED) : je l'avais écartée, c'est une remise, datée et annoncée.
            t = dits(function() evenement("QUEST_ACCEPTED", 1001) end)
            assertTrue(contient(t, "Tu as remis « Les pattes de loup » dans la Compagnie."), t)
            assertTrue(CompagnieDB.ecartees[1001].ecartee == false and CompagnieDB.ecartees[1001].par == moiPrenom, "remise par moi")
            -- Une quête écartée par Léo, que je prends : elle reste écartée (c'est à lui de la remettre, ou à « Remettre »).
            CompagnieDB.ecartees[1003] = { ecartee = true, date = 1, par = "Léo" }
            t = dits(function() evenement("QUEST_ACCEPTED", 1003) end)
            assertTrue(CompagnieDB.ecartees[1003].ecartee and t == "", "écartée par Léo : inchangée " .. t)
            -- Ma quête d'avant, que Léo n'a pas : à moi seul, rien n'est écarté.
            C_QuestLog.SetSelectedQuest(2201)
            C_QuestLog.SetAbandonQuest()
            C_QuestLog.AbandonQuest()
            assertNil(CompagnieDB.ecartees[2201], "quête d'avant : pas écartée")
            assertNil(CompagnieDB.avant[2201], "seulement oubliée")
        end)
        eteindre()
        C_QuestLog.SetSelectedQuest(1001)
        C_QuestLog.SetAbandonQuest()
        C_QuestLog.AbandonQuest()
        assertNil(CompagnieDB.ecartees, "sans Compagnie : rien")
    end)
    abandons = 0
end)

test("Écarter (#21) : clic droit sur une quête du suivi ou une ligne À faire (même inactive), menu, confirmé ; Écartées avec Remettre", function()
    local moiPrenom = moi().nom:match("^%S+")
    local MURLOCS = { id = 1004, titre = "Les murlocs", partageable = true }
    local function ecarter(racine, titre)
        local premier
        for _, d in racine:EnumerateElementDescriptions() do premier = premier or MenuUtil.GetElementText(d) end
        assertEquals(titre, premier, "le titre de la quête est en tête du menu")
        assertTrue(choisir(racine, "Écarter pour la Compagnie"), "le menu propose d'écarter")
        local _, popup = StaticPopup_Visible("COMPAGNIE_ECARTER")
        assertNotNil(popup, "confirmation affichée")
        return dits(function() popup.button1:Click() end)
    end
    -- La bulle de la ligne s'affiche-t-elle à son survol ? (le simulateur ne rend pas le texte de GameTooltip : le texte,
    -- « Clic droit : écarter pour la Compagnie », se vérifie sur la capture et en jeu.)
    local function bulle(b)
        GameTooltip:Hide()
        b:GetScript("OnEnter")(b)
        local vue = GameTooltip:IsShown() and GameTooltip:GetOwner() == b
        GameTooltip:Hide()
        return vue
    end
    avecJournal({ pattes(3), KOBOLDS, MURLOCS }, function()
        fabriquer({ guid = LEO, nom = "Léo Lame" })
        CompagnieDB.modeCompagnie = nil
        CompagnieDB.etats = { [LEO] = { niveau = 5, rendues = {}, quetes = { [1001] = { finie = false, objectifs = { { fait = 1, total = 8 } } } } } }
        -- Léo n'est pas dans mon groupe : « Partager en groupe » est inactif, son clic droit marche quand même.
        avecGroupe({}, false, function()
            charger()
            local p = bouton("CompagnieSuiviAFaire1")
            assertEquals("Partager en groupe : Les Kobolds (+1)", p:GetText())
            assertTrue(not p:IsEnabled(), "inactif")
            assertTrue(bulle(p), "la bulle s'affiche, même inactif")
            local t = ecarter(menuDe(function() p:GetScript("OnMouseUp")(p, "RightButton") end), "Les Kobolds")
            assertTrue(contient(t, "Tu as écarté « Les Kobolds » pour la Compagnie."), t)
            assertTrue(CompagnieDB.ecartees[1003].ecartee, "Kobolds écartés")
            -- La ligne « Abandonner aussi » (déjà écartée) : pas de menu, ni de bulle.
            local a = bouton("CompagnieSuiviAFaire1")
            assertEquals("Abandonner aussi : Les Kobolds", a:GetText())
            assertNil(menuDe(function() a:GetScript("OnMouseUp")(a, "RightButton") end), "déjà écartée : pas de menu")
            assertTrue(not bulle(a), "pas de bulle")
        end)
        avecLeo(function(envoyes)
            evenement("GROUP_ROSTER_UPDATE")
            -- Une ligne active : le clic gauche partage, le clic droit ouvre le menu.
            local p = bouton("CompagnieSuiviAFaire2")
            assertEquals("Partager : Les murlocs", p:GetText())
            assertTrue(p:IsEnabled())
            ecarter(menuDe(function() p:GetScript("OnMouseUp")(p, "RightButton") end), "Les murlocs")
            assertTrue(CompagnieDB.ecartees[1004].ecartee, "murlocs écartés")
            -- Une quête du suivi : clic droit sur sa ligne, le menu, la confirmation (annulable).
            local l = assert(ligneSuivi("Les pattes de loup"), "la quête est dans le suivi : " .. suivi())
            assertTrue(bulle(l), "la bulle de la ligne s'affiche")
            local racine = menuDe(function() l:Click("RightButton") end)
            assertTrue(choisir(racine, "Écarter pour la Compagnie"))
            StaticPopup_Hide("COMPAGNIE_ECARTER")
            assertTrue(not CompagnieDB.ecartees[1001], "annulé : rien d'écarté")
            local t = ecarter(menuDe(function() l:Click("RightButton") end), "Les pattes de loup")
            assertTrue(contient(t, "Tu as écarté « Les pattes de loup » pour la Compagnie."), t)
            -- Hors de l'avancement commun : à part, à moi (je l'ai encore), dite écartée, et « Abandonner aussi ».
            local q = suivi()
            local apart = q:sub(q:find("À part", 1, true) or #q + 1)
            assertTrue(contient(apart, "Les pattes de loup (" .. moiPrenom .. ", écartée)"), q)
            assertTrue(not contient(q:sub(1, (q:find("À part", 1, true) or #q + 1) - 1), "Les pattes de loup"), "plus une quête de la Compagnie : " .. q)
            assertNil(menuDe(function() ligneSuivi("Les pattes de loup"):Click("RightButton") end), "à part : pas de menu")
            assertEquals("Abandonner aussi : Les pattes de loup", bouton("CompagnieSuiviAFaire1"):GetText())
            assertEquals(0, abandons, "rien n'est abandonné tout seul")
            ecouler(5)
            assertTrue(envoyes[#envoyes].texte:find("#1001:1:%d+:" .. moiPrenom .. ";") ~= nil, envoyes[#envoyes].texte)
            -- L'onglet Écartées : les trois, qui l'a décidé, « Remettre ».
            membres(3)
            local lg = lignes()
            assertEquals(3, #lg)
            assertEquals("Les Kobolds", lg[1].nom)
            assertEquals("Les pattes de loup", lg[3].nom)
            assertEquals(moiPrenom, lg[3].presence)
            assertEquals("Remettre", lg[3].retirer:GetText())
            t = dits(function() lg[3].retirer:Click() end)
            assertTrue(contient(t, "Tu as remis « Les pattes de loup » dans la Compagnie."), t)
            assertEquals(2, #lignes(), "il reste les Kobolds et les murlocs")
            assertNotNil(ligneSuivi("|cffffd100Les pattes de loup"), "de retour dans les quêtes de la Compagnie : " .. suivi())
            -- Léo remet les Kobolds (décision plus récente) : annoncé, la liste suit.
            t = dits(function() chuchote("E;essai;5/1/1;5#1001:0:1/8###1003:0:" .. math.floor(GetServerTime() + 60) .. ":Léo#####" .. FIN) end)
            assertTrue(contient(t, "Léo a remis « Les Kobolds » dans la Compagnie."), t)
            assertEquals(1, #lignes(), "il reste les murlocs")
            CompagnieFrameTab2:Click()
            assertEquals(2, #lignes(), "l'onglet Membres")
            CompagnieFrame:Hide()
        end)
    end)
    eteindre()
end)

---------------------------------------------------------------------------------------------------
-- Remise trop tôt (#8) : le bandeau sous la fenêtre de remise du jeu, et la quête en avance.

-- Deux cadres se recouvrent-ils ?
local function recouvre(a, b)
    return a:GetLeft() < b:GetRight() and b:GetLeft() < a:GetRight() and a:GetBottom() < b:GetTop() and b:GetBottom() < a:GetTop()
end

test("remise : le bandeau s'affiche quand l'avancement commun n'est pas complet, pas quand la quête est À rendre ; le bouton du jeu n'est pas touché", function()
    local garde = GetQuestID
    GetQuestID = function() return 1001 end
    local ok, err = pcall(function()
        avecGroupe({}, false, function()
            avecJournal({ pattes(8) }, function()
                fabriquer({ guid = LEO, nom = "Léo Lame" })
                CompagnieDB.etats = { [LEO] = { niveau = 10, rendues = {}, quetes = {
                    [1001] = { finie = false, objectifs = { { fait = 5, total = 8 } } } } } }
                charger()
                ShowUIPanel(QuestFrame)
                QuestFrameRewardPanel:Show()
                local bouton = QuestFrameCompleteQuestButton
                local actif = bouton:IsEnabled()
                evenement("QUEST_COMPLETE")
                assertTrue(CompagnieBandeau and CompagnieBandeau:IsVisible(), "le bandeau s'affiche")
                assertEquals("La Compagnie n'a pas fini : 5/8", CompagnieBandeauTexte:GetText())
                -- Le bouton de remise du jeu : ni masqué, ni désactivé, ni recouvert (le bandeau est hors de la fenêtre).
                assertTrue(bouton:IsVisible(), "bouton du jeu visible")
                assertEquals(actif, bouton:IsEnabled(), "bouton du jeu ni activé ni désactivé")
                assertTrue(not recouvre(CompagnieBandeau, bouton), "bandeau hors du bouton")
                assertTrue(not recouvre(CompagnieBandeau, QuestFrame), "bandeau hors de la fenêtre du jeu")
                -- Léo a fini : la quête est À rendre, plus de bandeau (aussi par la page de progression).
                chuchote("E;essai;1/1/1;10#1001:1:8/8########" .. FIN)
                assertTrue(not CompagnieBandeau:IsShown(), "À rendre : pas de bandeau")
                evenement("QUEST_PROGRESS")
                assertTrue(not CompagnieBandeau:IsShown(), "À rendre, page de progression : pas de bandeau")
                -- Léo retombe à 5/8 (autre envoi) ; la fenêtre se ferme : le bandeau part avec elle.
                chuchote("E;essai;2/1/1;10#1001:0:5/8########" .. FIN)
                evenement("QUEST_PROGRESS")
                assertTrue(CompagnieBandeau:IsShown(), "progression : bandeau")
                evenement("QUEST_FINISHED")
                HideUIPanel(QuestFrame)
                assertTrue(not CompagnieBandeau:IsShown(), "fenêtre fermée : plus de bandeau")
            end)
        end)
    end)
    GetQuestID = garde
    eteindre()
    if not ok then error(err, 0) end
end)

test("quête en avance : Léo a rendu les pattes pendant que j'en suis à 5/8, l'écart le dit chez moi sans le nommer", function()
    avecGroupe({}, false, function()
        avecJournal({ pattes(5) }, function()
            fabriquer({ guid = LEO, nom = "Léo Lame" })
            CompagnieDB.modeCompagnie = nil
            CompagnieDB.etats = { [LEO] = { niveau = 10, rendues = {}, quetes = {
                [1001] = { finie = true, objectifs = { { fait = 8, total = 8 } } } } } }
            charger()
            assertNil(bouton("CompagnieSuiviAFaire1"), "pas encore d'écart")
            chuchote("E;essai;1/1/1;10##1001#######" .. FIN) -- Léo l'a rendue
            local b = bouton("CompagnieSuiviAFaire1")
            assertEquals("Rendue en avance : Les pattes de loup", b and b:GetText())
            assertTrue(not contient(b:GetText(), "Léo"), "personne n'est nommé")
            assertTrue(not b:IsEnabled(), "rien à cliquer : je la finis")
            assertTrue(contient(suivi(), "Patte de loup : 5/8"), suivi())
        end)
        avecJournal({ pattes(8) }, function()
            evenement("GROUP_ROSTER_UPDATE")
            assertNil(bouton("CompagnieSuiviAFaire1"), "finie : résorbée")
            assertTrue(contient(suivi(), "À rendre"), suivi())
        end)
    end)
    eteindre()
end)

---------------------------------------------------------------------------------------------------
-- Foyer et pierre de la Compagnie (#9).

test("foyer et pierre se dessinent depuis une Compagnie fabriquée, sans nommer personne ; ma liaison part avec mon état", function()
    local g = { GetBindLocation = GetBindLocation, GetServerTime = GetServerTime, cd = C_Container.GetItemCooldown }
    local maintenant, auberge, maPierre = 1764000000, "Hurlevent", { 0, 0 }
    GetBindLocation = function() return auberge end
    GetServerTime = function() return maintenant end
    C_Container.GetItemCooldown = function(id) assertEquals(6948, id) return maPierre[1], maPierre[2], 1 end
    local ok, err = pcall(function()
        avecJournal({ pattes(3) }, function()
            fabriquer({ guid = LEO, nom = "Léo Lame" })
            CompagnieDB.modeCompagnie, CompagnieDB.foyer = nil, nil
            -- Léo (absent) s'est lié à Comté-de-l'Or il y a une heure ; sa pierre, d'après son dernier envoi, sera prête
            -- dans 40 min. Moi : lié à Hurlevent, sans date connue (add-on éteint), pierre prête.
            CompagnieDB.etats = { [LEO] = { niveau = 5, rendues = {}, ecartees = {},
                quetes = { [1001] = { finie = false, objectifs = { { fait = 3, total = 8 } } } },
                auberge = "Comté-de-l'Or", liaison = maintenant - 3600, finRecharge = maintenant + 2400 } }
            avecGroupe({}, false, function()
                charger()
                local b = bouton("CompagnieSuiviAFaire1")
                assertEquals("Lie-toi à l'auberge de Comté-de-l'Or", b and b:GetText())
                assertTrue(not b:IsEnabled(), "rien à cliquer : on se lie chez l'aubergiste")
                local p = CompagniePierre
                assertTrue(p and p:IsShown(), "la pierre de la Compagnie est sur le suivi")
                assertEquals("Foyer dans 40 min", p:GetText())
                assertTrue(not contient(p:GetText(), "Léo"), "la pierre ne nomme personne")
                assertEquals("item", p:GetAttribute("type"))
                assertEquals("item:6948", p:GetAttribute("item"), "le clic utilise ma pierre de foyer")
                assertTrue(recouvre(p, CompagnieSuiviFrame) and not recouvre(p, CompagnieSuiviAFaire), "en tête du suivi")
                -- 40 min plus tard (la veille redessine) : prête chez tous.
                maintenant = maintenant + 2400
                ecouler(30)
                assertEquals("Rentrer au foyer", p:GetText())
                -- J'utilise ma pierre : 20 min de recharge.
                maPierre = { GetTime(), 1200 }
                evenement("BAG_UPDATE_COOLDOWN")
                ecouler(1)
                assertEquals("Foyer dans 20 min", p:GetText())
                maPierre = { 0, 0 }
            end)
            -- Je me lie à Comté-de-l'Or : l'écart est résorbé, mon état porte l'auberge et l'heure de la liaison.
            avecLeo(function(envoyes)
                auberge = "Comté-de-l'Or"
                evenement("HEARTHSTONE_BOUND")
                ecouler(5)
                assertNil(bouton("CompagnieSuiviAFaire1"), "lié au foyer : plus d'écart")
                local m = envoyes[#envoyes]
                assertTrue(m and m.texte:find("#Comté%-de%-l'Or#" .. maintenant .. "###" .. MIEN) ~= nil, m and m.texte)
            end)
            -- Mode éteint : le suivi se ferme, la pierre avec lui.
            avecGroupe({}, false, function() dits(function() SlashCmdList.COMPAGNIE("suivi") end) end)
            assertTrue(not CompagniePierre:IsShown(), "suivi fermé : pierre cachée")
        end)
    end)
    GetBindLocation, GetServerTime, C_Container.GetItemCooldown = g.GetBindLocation, g.GetServerTime, g.cd
    CompagnieDB.foyer = nil
    eteindre()
    if not ok then error(err, 0) end
end)

---------------------------------------------------------------------------------------------------
-- Partager (#22) : le jeu ne partage que dans un clic (OneForAll bloqué depuis un minuteur sur Forever) ; un seul bouton
-- « Partager », chaque clic partage la suivante.

test("Partager (#22) : un seul bouton, chaque clic partage la suivante ; une quête prise entre-temps est sautée", function()
    local Q = {}
    for i = 1, 3 do Q[i] = { id = 2300 + i, titre = "Partage " .. i, partageable = true } end
    avecJournal(Q, function() -- lignes du journal : 1 en-tête, puis 2, 3, 4
        fabriquer({ guid = LEO, nom = "Léo Lame" })
        CompagnieDB.modeCompagnie = nil
        CompagnieDB.etats = { [LEO] = { niveau = 5, rendues = {}, quetes = {} } }
        avecLeo(function()
            charger()
            local b = bouton("CompagnieSuiviAFaire1")
            assertEquals("Partager : Partage 1 (+2)", b and b:GetText())
            assertNil(bouton("CompagnieSuiviAFaire2"), "un seul bouton « Partager »")
            local n = #pousses
            b:Click()
            assertEquals("Partager : Partage 2 (+1)", b:GetText())
            b:Click()
            assertEquals("Partager : Partage 3", b:GetText())
            b:Click()
            assertEquals(n + 3, #pousses, "trois clics, trois partages")
            assertEquals("2,3,4", table.concat({ pousses[n + 1], pousses[n + 2], pousses[n + 3] }, ","), "dans l'ordre")
            -- Tout est parti, Léo n'a encore rien accepté : un nouveau tour. Léo prend Partage 2 entre-temps : sautée.
            assertEquals("Partager : Partage 1 (+2)", b:GetText())
            chuchote("E;essai;1/1/1;5#2302:0########" .. FIN)
            b = bouton("CompagnieSuiviAFaire1")
            assertEquals("Partager : Partage 1 (+1)", b:GetText())
            b:Click()
            b:Click()
            assertEquals("2,4", pousses[n + 4] .. "," .. pousses[n + 5], "Partage 2 sautée")
        end)
    end)
    eteindre()
end)

---------------------------------------------------------------------------------------------------
-- Acceptation automatique (#26) : une quête qu'un autre membre a est acceptée à l'ouverture de sa fenêtre.

test("acceptation automatique (#26) : la quête de Léo acceptée, pas une que personne n'a, ni une écartée, ni réglage éteint ; l'escorte de Léo confirmée", function()
    local g = { GetQuestID = GetQuestID, AcceptQuest = AcceptQuest, ConfirmAcceptQuest = ConfirmAcceptQuest }
    local quete, acceptees, confirmees = 1001, 0, 0
    GetQuestID = function() return quete end
    AcceptQuest = function() acceptees = acceptees + 1 end
    ConfirmAcceptQuest = function() confirmees = confirmees + 1 end
    local ok, err = pcall(function()
        avecGroupe({}, false, function()
            avecJournal({}, function()
                fabriquer({ guid = LEO, nom = "Léo Lame" })
                CompagnieDB.accepteAuto = nil -- allumée par défaut
                CompagnieDB.etats = { [LEO] = { niveau = 5, rendues = {}, quetes = {
                    [1001] = { finie = false, objectifs = {} }, [1003] = { finie = false, objectifs = {} } } } }
                C_QuestLog.GetTitleForQuestID = function(id) return ({ [1001] = "Les pattes de loup", [1003] = "Les Kobolds" })[id] end
                charger()
                evenement("QUEST_DETAIL")
                assertEquals(1, acceptees, "Léo a la quête : acceptée")
                quete = 1005
                evenement("QUEST_DETAIL")
                assertEquals(1, acceptees, "personne ne l'a : la fenêtre s'ouvre normalement")
                quete = 1003
                CompagnieDB.ecartees = { [1003] = { ecartee = true, date = 1, par = "Léo" } }
                evenement("QUEST_DETAIL")
                assertEquals(1, acceptees, "écartée : pas acceptée")
                -- Escorte lancée par Léo : confirmée ; une escorte écartée, ou lancée par un inconnu : non.
                evenement("QUEST_ACCEPT_CONFIRM", "Léo", "Les pattes de loup")
                assertEquals(1, confirmees, "l'escorte de Léo : confirmée")
                evenement("QUEST_ACCEPT_CONFIRM", "Léo", "Les Kobolds")
                evenement("QUEST_ACCEPT_CONFIRM", "Zoé", "Les pattes de loup")
                assertEquals(1, confirmees, "écartée, ou lancée par un non-membre : non")
                -- Le réglage, dans la page de Compagnie des réglages fusionnés : éteint, plus rien n'est accepté.
                local cb = assert(CompagnieAccepteAuto, "la case des réglages")
                assertTrue(cb:GetChecked(), "allumée par défaut")
                cb:Click()
                assertEquals(false, CompagnieDB.accepteAuto)
                quete = 1001
                evenement("QUEST_DETAIL")
                evenement("QUEST_ACCEPT_CONFIRM", "Léo", "Les pattes de loup")
                assertEquals(1, acceptees, "réglage éteint : pas acceptée")
                assertEquals(1, confirmees, "réglage éteint : pas confirmée")
                cb:Click()
                assertNotEquals(false, CompagnieDB.accepteAuto)
            end)
        end)
    end)
    GetQuestID, AcceptQuest, ConfirmAcceptQuest = g.GetQuestID, g.AcceptQuest, g.ConfirmAcceptQuest
    CompagnieDB.accepteAuto = nil
    eteindre()
    if not ok then error(err, 0) end
end)

---------------------------------------------------------------------------------------------------
-- Le bandeau d'abandon (#25) et la base des quêtes du socle (fausse, le temps d'un test).

-- La base des quêtes vaut base le temps de f.
local function avecBase(base, f)
    baseTest = base
    local ok, err = pcall(f)
    baseTest = {}
    if not ok then error(err, 0) end
end

test("bandeau d'abandon (#25) : au-dessus de la fenêtre d'abandon, avec la suite coupée ; sans suite connue, sans elle ; hors Compagnie, rien ; le bouton du jeu intact", function()
    local BASE = { [1001] = { nom = "Les pattes de loup", suites = { 1101 } }, [1101] = { nom = "La peau de loup", suites = { 1102 } },
        [1102] = { nom = "Le chef des loups" }, [1003] = { nom = "Les Kobolds" } }
    local function ouvrirAbandon(id, which)
        C_QuestLog.SetSelectedQuest(id) -- comme le jeu : la quête choisie, SetAbandonQuest, puis la fenêtre
        C_QuestLog.SetAbandonQuest()
        StaticPopup_Show(which or "ABANDON_QUEST", BASE[id].nom, "des objets") -- le jeu passe le titre de la quête
        return select(2, StaticPopup_Visible(which or "ABANDON_QUEST"))
    end
    avecBase(BASE, function()
        avecGroupe({}, false, function()
            avecJournal({ pattes(3), KOBOLDS }, function()
                fabriquer({ guid = LEO, nom = "Léo Lame" })
                CompagnieDB.etats = { [LEO] = { niveau = 5, rendues = {}, quetes = { [1001] = { finie = false, objectifs = {} } } } }
                charger()
                local f = assert(ouvrirAbandon(1001), "la fenêtre d'abandon du jeu")
                local b = CompagnieBandeauAbandon
                assertTrue(b and b:IsVisible(), "le bandeau s'affiche")
                assertEquals("Abandonner « Les pattes de loup » l'écarte pour la Compagnie et coupe sa suite : La peau de loup, Le chef des loups.",
                    CompagnieBandeauAbandonTexte:GetText())
                assertTrue(b:GetBottom() >= f:GetTop(), "au-dessus de la fenêtre, hors d'elle")
                assertTrue(f.button1:IsVisible() and f.button1:IsEnabled(), "le bouton du jeu : visible et actif")
                StaticPopup_Hide("ABANDON_QUEST")
                assertTrue(not b:IsVisible(), "fenêtre fermée : plus de bandeau")
                f = ouvrirAbandon(1003, "ABANDON_QUEST_WITH_ITEMS")
                assertTrue(b:IsVisible(), "avec des objets de quête aussi")
                assertEquals("Abandonner « Les Kobolds » l'écarte pour la Compagnie.", CompagnieBandeauAbandonTexte:GetText(), "sans suite connue")
                StaticPopup_Hide("ABANDON_QUEST_WITH_ITEMS")
                -- Déjà écartée (« Abandonner aussi ») : l'abandon n'écarte rien de plus, pas de bandeau.
                CompagnieDB.ecartees = { [1001] = { ecartee = true, date = 1, par = "Léo" } }
                ouvrirAbandon(1001)
                assertTrue(not b:IsVisible(), "déjà écartée : pas de bandeau")
                StaticPopup_Hide("ABANDON_QUEST")
                eteindre()
                ouvrirAbandon(1001)
                assertTrue(not b:IsVisible(), "hors Compagnie : pas de bandeau")
                StaticPopup_Hide("ABANDON_QUEST")
            end)
        end)
    end)
    eteindre()
end)

---------------------------------------------------------------------------------------------------
-- La zone de la Compagnie (#24).

-- Une fausse base des quêtes avec des zones (areaID) : combien de quêtes, et à quel niveau requis.
local NOMS_ZONES = { [40] = "Marche de l'Ouest", [148] = "Sombrivage", [10] = "Bois de la Pénombre", [12] = "Forêt d'Elwynn" }
local function baseDeZones(extra)
    local b, id = {}, 50000
    for z, requis in pairs({ [40] = 9, [148] = 10, [10] = 20, [12] = 1 }) do
        for _ = 1, 10 do id = id + 1; b[id] = { nom = "Quête " .. id, zone = z, niveau_requis = requis } end
    end
    for k, v in pairs(extra or {}) do b[k] = v end
    return b
end
local function avecZones(f)
    local vrai = C_Map.GetAreaInfo
    C_Map.GetAreaInfo = function(z) return NOMS_ZONES[z] end
    local ok, err = pcall(f)
    C_Map.GetAreaInfo = vrai
    if not ok then error(err, 0) end
end
-- Les entrées d'un menu, dans l'ordre : leurs textes.
local function entrees(racine)
    local t = {}
    for _, d in racine:EnumerateElementDescriptions() do t[#t + 1] = MenuUtil.GetElementText(d) or "" end
    return t
end

test("zone de la Compagnie (#24) : le menu, une zone grisée sous le niveau ; choisie, en tête du suivi ; celle de Léo annoncée ; la suggestion à l'entrée d'une zone, une fois", function()
    avecZones(function()
        avecBase(baseDeZones(), function()
            avecGroupe({}, false, function()
                avecJournal({ pattes(3) }, function()
                    fabriquer({ guid = LEO, nom = "Léo Lame" })
                    CompagnieDB.modeCompagnie = nil
                    CompagnieDB.etats = { [LEO] = { niveau = 10, rendues = {}, quetes = { [1001] = { finie = false, objectifs = {} } } } }
                    charger()
                    assertEquals("Choisir la zone de la Compagnie", CompagnieZoneBouton:GetText())
                    local racine = menuDe(function() CompagnieZoneBouton:Click() end)
                    local e = entrees(racine)
                    -- Niveau de la Compagnie 10 (Léo) : Sombrivage, Marche de l'Ouest, Forêt d'Elwynn ; le Bois de la Pénombre grisé.
                    assertEquals("Zone de la Compagnie|Sombrivage (niv. 10)|Marche de l'Ouest (niv. 9)|Forêt d'Elwynn (niv. 1)|" ..
                        "|cff808080Bois de la Pénombre (niv. 20)|r", table.concat(e, "|"))
                    local t = dits(function() assertTrue(choisir(racine, "Sombrivage (niv. 10)")) end)
                    assertTrue(contient(t, "Tu as choisi Sombrivage pour la Compagnie."), t)
                    -- Léo n'a pas encore dit ses prérequis pour Sombrivage : à contrôler.
                    assertEquals("Zone : Sombrivage (Léo à contrôler)", CompagnieZoneBouton:GetText(), "en tête du suivi, sur son bouton")
                    assertEquals(148, CompagnieDB.zoneCompagnie.zone)
                    -- Une zone grisée se choisit aussi.
                    dits(function() choisir(menuDe(function() CompagnieZoneBouton:Click() end), "|cff808080Bois de la Pénombre (niv. 20)|r") end)
                    assertEquals("Zone : Bois de la Pénombre (Léo à contrôler)", CompagnieZoneBouton:GetText())
                    -- Léo choisit la Marche de l'Ouest après moi : le chat le dit, le suivi suit.
                    t = dits(function()
                        chuchote("E;essai;1/1/1;10#1001:0#########40:" .. math.floor(GetServerTime() + 60) .. ":Léo#40###")
                    end)
                    assertTrue(contient(t, "Léo a choisi Marche de l'Ouest pour la Compagnie."), t)
                    assertEquals("Zone : Marche de l'Ouest", CompagnieZoneBouton:GetText(), "Léo l'a contrôlée : rien à contrôler")
                    -- J'entre en Forêt d'Elwynn (pas la zone de la Compagnie) : une ligne propose de la choisir, une seule fois.
                    ici = "Forêt d'Elwynn"
                    t = dits(function() evenement("ZONE_CHANGED_NEW_AREA") end)
                    assertTrue(contient(t, "Tu entres en Forêt d'Elwynn, qui n'est pas la zone de la Compagnie (Marche de l'Ouest)"), t)
                    ici = "Marche de l'Ouest"
                    t = dits(function() evenement("ZONE_CHANGED_NEW_AREA") end)
                    assertTrue(not contient(t, "Tu entres"), "la zone de la Compagnie : rien " .. t)
                    ici = "Forêt d'Elwynn"
                    t = dits(function() evenement("ZONE_CHANGED_NEW_AREA") end)
                    assertTrue(not contient(t, "Tu entres"), "une seule fois par zone : " .. t)
                    assertEquals(40, CompagnieDB.zoneCompagnie.zone, "rien ne change tout seul")
                    -- « /compagnie zone » choisit la zone où je suis.
                    t = dits(function() SlashCmdList.COMPAGNIE("zone") end)
                    assertTrue(contient(t, "Tu as choisi Forêt d'Elwynn pour la Compagnie."), t)
                    assertEquals(12, CompagnieDB.zoneCompagnie.zone)
                end)
            end)
        end)
    end)
    eteindre()
end)

---------------------------------------------------------------------------------------------------
-- Le contrôle des prérequis (#27).

test("prérequis manquant (#27) : l'écart se dessine dans À faire, sa bulle dit tout ; clic droit, Écarter : il disparaît", function()
    local BASE = baseDeZones({
        [952] = { nom = "Bosquet des Anciens", zone = 148, niveau_requis = 6, prerequis_un = { 940 } },
        [937] = { nom = "La clairière enchantée", zone = 141, suites = { 98392 }, donneur = { pnj = 3519, nom = "Sentinelle Arynia" } },
        [98392] = { nom = "Les ténèbres dans la clairière", zone = 141, prerequis_un = { 937 }, suites = { 98398 } },
        [98398] = { nom = "L'arbre de l'Oracle", zone = 141, prerequis_un = { 98392 }, suites = { 940 } },
        [940] = { nom = "Teldrassil", zone = 141, prerequis_un = { 98398 }, suites = { 952 } } })
    NOMS_ZONES[141] = "Teldrassil"
    avecZones(function()
        avecBase(BASE, function()
            avecGroupe({}, false, function()
                avecJournal({}, function()
                    fabriquer({ guid = LEO, nom = "Léo Lame" })
                    CompagnieDB.modeCompagnie = nil
                    -- Léo, l'elfe, a fait Teldrassil : son état couvre Sombrivage, rien ne lui manque.
                    CompagnieDB.etats = { [LEO] = { niveau = 12, rendues = {}, quetes = {}, prerequis = { zone = 148, manquants = {} } } }
                    CompagnieDB.zoneCompagnie = { zone = 148, date = 1, par = "Léo" }
                    charger()
                    assertEquals("Zone : Sombrivage", CompagnieZoneBouton:GetText())
                    local b = assert(bouton("CompagnieSuiviAFaire1"), "un écart À faire")
                    assertEquals("Avant Bosquet des Anciens : 4 quêtes à Teldrassil", b:GetText())
                    assertTrue(not b:IsEnabled(), "rien à cliquer : on va faire la chaîne")
                    assertEquals("« Bosquet des Anciens » demande avant 4 quêtes à Teldrassil, à commencer par « La clairière enchantée » " ..
                        "(Sentinelle Arynia). Manque à toi.", b.details)
                    -- Mon état porte le prérequis manquant, avec la zone qu'il couvre.
                    avecLeo(function(envoyes)
                        evenement("QUEST_LOG_UPDATE")
                        ecouler(5)
                        assertTrue(envoyes[#envoyes].texte:find("#148=952:940#%d+=") ~= nil, envoyes[#envoyes].texte)
                        -- …et mes quêtes rendues de la zone (#34) : la zone couverte, rien de rendu.
                        assertTrue(envoyes[#envoyes].texte:find("#148#$") ~= nil, envoyes[#envoyes].texte)
                    end)
                    -- Clic droit sur la ligne (inactive) : Écarter le Bosquet ; l'écart disparaît, la chaîne avec lui.
                    local racine = menuDe(function() b:GetScript("OnMouseUp")(b, "RightButton") end)
                    assertTrue(choisir(racine, "Écarter pour la Compagnie"), "le menu Écarter")
                    local _, popup = StaticPopup_Visible("COMPAGNIE_ECARTER")
                    local t = dits(function() popup.button1:Click() end)
                    assertTrue(contient(t, "Tu as écarté « Bosquet des Anciens » pour la Compagnie."), t)
                    assertNil(bouton("CompagnieSuiviAFaire1"), "plus d'écart")
                    assertTrue(CompagnieDB.ecartees[952].ecartee and not CompagnieDB.ecartees[940], "une seule décision, la chaîne suit")
                end)
            end)
        end)
    end)
    eteindre()
end)

---------------------------------------------------------------------------------------------------
-- Inviter (#23).

test("Inviter (#23) : se dessine pour un joueur du groupe non membre ; l'invitation part, sa réponse le fait entrer ; invité, j'entre avec l'état de qui m'invite", function()
    avecGroupe({ { LEO, "Léo", "Lame" }, { MIRA, "Mira", "Feuille" } }, false, function(envoyes)
        avecJournal({}, function()
            fabriquer({ guid = LEO, nom = "Léo Lame" })
            CompagnieDB.compagnie.date = 1
            membres()
            local l = lignes(true)
            assertEquals(3, #l, "Léo, moi, et Mira du groupe")
            assertEquals("Mira Feuille", l[3].nom)
            assertEquals("Inviter", l[3].retirer:GetText(), "« Inviter » pour Mira, du groupe, pas membre")
            assertEquals("Retirer", l[2].retirer:GetText(), "« Retirer » pour Léo, membre")
            local t = dits(function() l[3].retirer:Click() end)
            assertTrue(contient(t, "Invitation envoyée à Mira Feuille"), t)
            assertEquals("I;essai;" .. MIRA, envoyes[#envoyes].texte)
            assertEquals("PARTY", envoyes[#envoyes].canal)
            assertEquals("Invité…", lignes(true)[3].retirer:GetText(), "l'état de l'invitation, sur son bouton")
            t = dits(function() recu("A;essai", "Mira Feuille") end)
            assertTrue(contient(t, "Mira Feuille entre dans la Compagnie."), t)
            assertEquals(3, #CompagnieDB.compagnie.membres)
            assertEquals(3, #lignes(), "Mira est membre")
            -- Mon état porte la nouvelle liste (pour les absents, et pour qu'elle entre chez elle).
            ecouler(5)
            assertTrue(envoyes[#envoyes].texte:find("Mira Feuille##$") ~= nil, envoyes[#envoyes].texte)
            CompagnieFrame:Hide()
        end)
    end)
    eteindre()
    -- Invité : Léo m'invite, j'accepte ; son état, qui porte la liste avec moi, me fait entrer.
    avecGroupe({ { LEO, "Léo", "Lame" } }, false, function(envoyes)
        avecJournal({ pattes(3) }, function()
            CompagnieDB.compagnie = nil
            recu("I;c1;" .. moi().guid)
            local _, popup = StaticPopup_Visible("COMPAGNIE_INVITATION")
            assertNotNil(popup, "l'invitation s'affiche")
            popup.button1:Click()
            assertEquals("A;c1", envoyes[#envoyes].texte)
            assertNil(CompagnieDB.compagnie, "pas encore entré")
            local g = moi().guid:gsub("^Player%-", "")
            local t = dits(function()
                recu("E;c1;1/1/1;10############" .. math.floor(GetServerTime()) .. "=" .. LEO:gsub("^Player%-", "") ..
                    ":Léo Lame,1-0000BCDE:Mira Feuille," .. g .. ":" .. moi().nom .. "##")
            end)
            assertTrue(contient(t, "Tu entres dans la Compagnie : Léo Lame"), t)
            assertEquals("c1", CompagnieDB.compagnie.id)
            assertEquals(3, #CompagnieDB.compagnie.membres)
            assertTrue(CompagnieDB.avant[1001], "mes quêtes d'avant sont notées à mon entrée")
        end)
    end)
    eteindre()
end)

---------------------------------------------------------------------------------------------------
-- Quête personnelle et niveau insuffisant (#7).

test("quête personnelle et niveau insuffisant (#7) : à part et nommée, marquée à la main ; « au niveau 10 », appris d'un partage refusé", function()
    local moiPrenom = moi().nom:match("^%S+")
    local LUMIERE = { id = 2201, titre = "La lumière sacrée", partageable = true, objectifs = { { "Lettre : 0/1", 0, 1 } } }
    local MOUSSE = { id = 2202, titre = "La mousse des grottes", partageable = true }
    local CHAMPI = { id = 2203, titre = "Les champignons", partageable = true }
    local PUITS = { id = 2204, titre = "Le vieux puits", partageable = true }
    -- La lumière sacrée : ma classe seulement (Léo, classe 99, ne peut pas) ; la mousse : niveau 10 (Léo est niveau 9).
    local BASE = { [2201] = { classes = { select(3, UnitClass("player")) or 2 } }, [2202] = { niveau_requis = 10 } }
    avecBase(BASE, function()
        avecJournal({ LUMIERE, MOUSSE, CHAMPI }, function()
            fabriquer({ guid = LEO, nom = "Léo Lame" })
            CompagnieDB.modeCompagnie, CompagnieDB.personnelles, CompagnieDB.niveauxRequis = nil, nil, nil
            CompagnieDB.etats = { [LEO] = { niveau = 9, race = 1, classe = 99, rendues = {}, quetes = {} } }
            avecLeo(function(envoyes)
                charger()
                local t = suivi()
                local apart = t:sub(t:find("À part", 1, true) or #t + 1)
                assertTrue(contient(apart, "La lumière sacrée (" .. moiPrenom .. ")") and contient(apart, "Lettre : 0/1"),
                    "personnelle : à part, nommée, avec mon avancement : " .. t)
                local n = bouton("CompagnieSuiviAFaire1")
                assertEquals("Au niveau 10 : La mousse des grottes", n and n:GetText())
                assertTrue(not n:IsEnabled(), "niveau insuffisant : rien à cliquer, pas de partage impossible")
                assertEquals("Partager : Les champignons", bouton("CompagnieSuiviAFaire2"):GetText())
                assertNil(bouton("CompagnieSuiviAFaire3"), "rien pour la quête personnelle")
                -- Marquer les champignons personnels à la main : clic droit sur la quête, la case du menu.
                assertTrue(choisir(menuDe(function() ligneSuivi("Les champignons"):Click("RightButton") end),
                    "Quête personnelle (à moi seul)"), "le menu propose de la marquer")
                t = suivi()
                apart = t:sub(t:find("À part", 1, true) or #t + 1)
                assertTrue(contient(apart, "Les champignons (" .. moiPrenom .. ")"), "marquée : à part : " .. t)
                assertNil(bouton("CompagnieSuiviAFaire2"), "plus de « Partager »")
                ecouler(5)
                assertTrue(envoyes[#envoyes].texte:find("2203:0p", 1, true) ~= nil, "mon état porte le marquage : " .. envoyes[#envoyes].texte)
                assertTrue(envoyes[#envoyes].texte:find("^E;essai;%d+/%d+/%d+;%d+:%d+:%d+#") ~= nil, "et ma race, ma classe : " .. envoyes[#envoyes].texte)
                -- La démarquer : clic droit sur sa ligne à part, la case seule (pas d'Écarter).
                local racine = menuDe(function() ligneSuivi("Les champignons"):Click("RightButton") end)
                local textes = {}
                for _, d in racine:EnumerateElementDescriptions() do textes[#textes + 1] = MenuUtil.GetElementText(d) or "" end
                assertTrue(not contient(table.concat(textes, "|"), "Écarter"), "à part : pas d'Écarter : " .. table.concat(textes, "|"))
                assertTrue(choisir(racine, "Quête personnelle (à moi seul)"))
                assertEquals("Partager : Les champignons", bouton("CompagnieSuiviAFaire2"):GetText(), "démarquée : de nouveau à partager")
                -- Léo passe niveau 10 : l'écart est résorbé, la mousse est à partager.
                CompagnieDB.etats[LEO].niveau = 10
                evenement("GROUP_ROSTER_UPDATE")
                assertEquals("Partager : La mousse des grottes (+1)", bouton("CompagnieSuiviAFaire1"):GetText())
            end)
        end)
    end)
    -- Sans base : le partage du vieux puits est refusé, Léo (niveau 9) a un niveau trop bas : le niveau requis est appris.
    avecJournal({ PUITS }, function()
        CompagnieDB.etats[LEO].niveau = 9
        avecLeo(function()
            evenement("GROUP_ROSTER_UPDATE")
            local b = bouton("CompagnieSuiviAFaire1")
            assertEquals("Partager : Le vieux puits", b:GetText())
            evenement("CHAT_MSG_SYSTEM", ERR_QUEST_PUSH_LOW_LEVEL_S:format("Léo"))
            assertNil(CompagnieDB.niveauxRequis, "sans partage de ma part : rien n'est appris")
            b:Click()
            evenement("CHAT_MSG_SYSTEM", ERR_QUEST_PUSH_LOW_LEVEL_S:format("Léo"))
            assertEquals(10, CompagnieDB.niveauxRequis and CompagnieDB.niveauxRequis[2204])
            assertEquals("Au niveau 10 : Le vieux puits", bouton("CompagnieSuiviAFaire1"):GetText())
        end)
    end)
    CompagnieDB.personnelles, CompagnieDB.niveauxRequis = nil, nil
    eteindre()
end)

---------------------------------------------------------------------------------------------------
-- Quête à prendre soi-même (#6).

test("quête à prendre soi-même (#6) : « Va voir » le PNJ relevé par Léo ; l'objet, où il a été ramassé, sinon d'où il vient ; ma prise part avec mon état", function()
    local BASE = { [2600] = { nom = "Les Kobolds" }, [2602] = { nom = "La lettre" },
        [2601] = { nom = "Le collecteur", objet = 1307, origine = { nom = "Plan de route du Collecteur", pnjs = { "Rivepatte chétif", "Lardeur" } } } }
    local CARTES = { [1429] = { name = "Forêt d'Elwynn" }, [1436] = { name = "Marche de l'Ouest" } }
    local g = { carte = C_Map.GetBestMapForUnit, pos = C_Map.GetPlayerMapPosition, info = C_Map.GetMapInfo, existe = UnitExists,
        nom = UnitName, qid = GetQuestID }
    C_Map.GetBestMapForUnit = function() return 1436 end
    C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.561, 0.474 end } end
    C_Map.GetMapInfo = function(c) return CARTES[c] end
    UnitExists = function(u) if u == "npc" then return true end return g.existe(u) end
    UnitName = function(u) if u == "npc" then return "Gryan Stoutmantle" end return g.nom(u) end
    GetQuestID = function() return 2602 end
    local ok, err = pcall(function()
        avecBase(BASE, function()
            avecJournal({}, function()
                fabriquer({ guid = LEO, nom = "Léo Lame" })
                CompagnieDB.modeCompagnie, CompagnieDB.accepteAuto, CompagnieDB.origines = nil, false, nil
                local function etatDeLeo(ramasse)
                    CompagnieDB.etats = { [LEO] = { niveau = 5, rendues = {}, quetes = {
                        [2600] = { finie = false, objectifs = {}, partageable = false, origine = { nom = "Maréchal Dughan", carte = 1429, x = 42, y = 65 } },
                        [2601] = { finie = false, objectifs = {}, partageable = false, origine = ramasse },
                        [2602] = { finie = false, objectifs = {}, partageable = false } } } }
                end
                etatDeLeo({ carte = 1436, x = 30, y = 40 })
                avecGroupe({}, false, function()
                    charger()
                    local b = assert(bouton("CompagnieSuiviAFaire1"), "un écart À faire")
                    assertEquals("Va voir Maréchal Dughan, Forêt d'Elwynn", b:GetText())
                    assertTrue(not b:IsEnabled(), "rien à cliquer : il faut y aller")
                    assertEquals("« Les Kobolds » ne se partage pas : va voir Maréchal Dughan, Forêt d'Elwynn (42, 65).", b.details)
                    b = bouton("CompagnieSuiviAFaire2")
                    assertEquals("Trouve Plan de route du Collecteur", b:GetText())
                    assertEquals("« Le collecteur » part d'un objet, « Plan de route du Collecteur » : un membre l'a ramassé, " ..
                        "Marche de l'Ouest (30, 40).", b.details)
                    assertEquals("À prendre soi-même : La lettre", bouton("CompagnieSuiviAFaire3"):GetText(), "ni relevé ni base : sans endroit")
                    -- Sans ramassage connu : d'où vient l'objet, d'après la base des quêtes.
                    etatDeLeo(nil)
                    evenement("GROUP_ROSTER_UPDATE")
                    assertEquals("« Le collecteur » part d'un objet, « Plan de route du Collecteur » : lâché par Rivepatte chétif, Lardeur.",
                        bouton("CompagnieSuiviAFaire2").details)
                    -- Je ramasse le plan : l'endroit est noté pour quand je prendrai la quête.
                    evenement("CHAT_MSG_LOOT", "Vous recevez le butin : |cffffffff|Hitem:1307::::::::5:::::|h[Plan de route du Collecteur]|h|r.")
                    local o = CompagnieDB.origines and CompagnieDB.origines[2601]
                    assertEquals("1436 56 47 nil", o and ("%s %s %s %s"):format(o.carte, o.x, o.y, tostring(o.nom)), "le ramassage, sans PNJ")
                end)
                -- Je prends La lettre chez Gryan Stoutmantle : l'écart est résorbé, mon état porte le PNJ et l'endroit.
                evenement("QUEST_DETAIL")
                evenement("QUEST_ACCEPTED", 2602)
                avecJournal({ { id = 2602, titre = "La lettre", partageable = false } }, function()
                    avecLeo(function(envoyes)
                        evenement("QUEST_LOG_UPDATE")
                        ecouler(5)
                        local t = envoyes[#envoyes].texte
                        assertTrue(t:find("2602:0n", 1, true) ~= nil, "non partageable : " .. t)
                        assertTrue(t:find("#2602=Gryan Stoutmantle@1436:56:47$") ~= nil, "le PNJ et l'endroit : " .. t)
                        assertEquals("Va voir Maréchal Dughan, Forêt d'Elwynn", bouton("CompagnieSuiviAFaire1"):GetText())
                        assertEquals("Trouve Plan de route du Collecteur", bouton("CompagnieSuiviAFaire2"):GetText())
                        assertNil(bouton("CompagnieSuiviAFaire3"), "La lettre : prise")
                    end)
                end)
            end)
        end)
    end)
    C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition, C_Map.GetMapInfo = g.carte, g.pos, g.info
    UnitExists, UnitName, GetQuestID = g.existe, g.nom, g.qid
    CompagnieDB.accepteAuto, CompagnieDB.origines = nil, nil
    eteindre()
    if not ok then error(err, 0) end
end)

test("fenêtres du socle (#31) : la Compagnie s'agrandit, colonne Membre extensible ; listes près de la minicarte sans poignée, à leur place", function()
    fabriquer({ guid = LEO, nom = "Léo Lame" })
    membres()
    local f = CompagnieFrame
    assertNotNil(f.ResizeButton, "la fenêtre de la Compagnie a sa poignée")
    local function celluleNom()
        local function chercher(p)
            for _, c in ipairs({ p:GetChildren() }) do
                if c.item and c:IsVisible() then return c.cells[1] end
                local r = chercher(c)
                if r then return r end
            end
        end
        return chercher(f)
    end
    local avant = celluleNom():GetWidth()
    f:SetSize(f:GetWidth() + 120, f:GetHeight() + 60)
    membres() -- redessinée (dans le simulateur, OnSizeChanged n'arrive qu'à l'image suivante)
    assertTrue(celluleNom():GetWidth() >= avant + 119, "la colonne Membre prend la largeur gagnée : " .. avant .. " → " .. celluleNom():GetWidth())
    f:Hide()
    CompagnieDB.compagnie = nil
    -- Les deux listes près de la minicarte (créées par les tests d'avant) : pas des fenêtres (cadre nu, en-tête du suivi
    -- des quêtes du jeu), en LOW, place par défaut.
    for _, l in ipairs({ CompagnieAFaireFrame, CompagnieSuiviFrame }) do
        assertNil(l.ResizeButton, l:GetName() .. " : pas de poignée")
        assertTrue(l.NineSlice == nil and l.CloseButton == nil and l.title == nil, l:GetName() .. " : pas de cadre de fenêtre")
        assertNotNil(l.entete and l.entete.MinimizeButton, l:GetName() .. " : l'en-tête du suivi des quêtes et son « – »")
        assertEquals("LOW", l:GetFrameStrata())
    end
    assertEquals("À faire", CompagnieAFaireFrame.entete.Text:GetText())
    assertEquals("Compagnie", CompagnieSuiviFrame.entete.Text:GetText())
    assertEquals(Minimap, select(2, CompagnieAFaireFrame:GetPoint(1)), "À faire : à gauche de la minicarte")
    -- Glisser le suivi par une de ses lignes retient sa place (pas sa taille, qui suit le contenu).
    AzerothCommuneDB.fenetres = AzerothCommuneDB.fenetres or {}
    AzerothCommuneDB.fenetres.CompagnieSuiviFrame = nil
    CompagnieSuiviLigne1:GetScript("OnDragStop")(CompagnieSuiviLigne1)
    local g = AzerothCommuneDB.fenetres.CompagnieSuiviFrame
    assertTrue(g and g.x and g.y and not g.w, "place retenue, sans taille")
    -- Par son en-tête, la petite liste aussi.
    AzerothCommuneDB.fenetres.CompagnieAFaireFrame = nil
    local h = CompagnieAFaireFrame.entete
    h:GetScript("OnDragStart")(h, "LeftButton")
    h:GetScript("OnDragStop")(h)
    g = AzerothCommuneDB.fenetres.CompagnieAFaireFrame
    assertTrue(g and g.x and g.y and not g.w, "À faire : place retenue par l'en-tête")
    AzerothCommuneDB.fenetres.CompagnieSuiviFrame = nil
    AzerothCommuneDB.fenetres.CompagnieAFaireFrame = nil
end)

---------------------------------------------------------------------------------------------------
-- L'arbre des chaînes (#33) : l'onglet Chaînes, une fenêtre à part reliée à Membres et Écartées.

-- Les cases affichées de l'arbre des chaînes : { [titre] = case } (le cadre porte n, la case de ns.arbreDesChaines).
local function casesChaines()
    local t = {}
    local function parcourir(f)
        for _, c in ipairs({ f:GetChildren() }) do
            if c.n and c.nom and c:IsVisible() then t[c.nom:GetText()] = c end
            parcourir(c)
        end
    end
    parcourir(CompagnieChainesFrame)
    return t
end
local function compter(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

test("onglet Chaînes (#33, #34) : en premier, sans zone le message ; la zone dessinée, clic droit = le menu du suivi ; repli au clic ; onglets reliés, tailles à part ; « Voir les chaînes »", function()
    NOMS_ZONES[141] = "Teldrassil"
    local BASE = {
        [82001] = { nom = "Les loups", zone = 12, niveau = 5, suites = { 82002 }, donneur = { nom = "Maréchal Dughan", carte = 1429, x = 42, y = 65 } },
        [82002] = { nom = "Les peaux", zone = 12, niveau = 6, prerequis = { 82001 } },
        [82003] = { nom = "Le colis", zone = 12, niveau = 3 },
        [82004] = { nom = "Le message", zone = 12, niveau = 12, niveau_requis = 11, prerequis = { 940 } },
        [940] = { nom = "Teldrassil", zone = 141, niveau = 4, suites = { 82004 } },
    }
    avecZones(function()
        avecBase(BASE, function()
            avecGroupe({}, false, function()
                avecJournal({ { id = 82001, titre = "Les loups", objectifs = { { "Loup : 2/8", 2, 8 } } } }, function()
                    fabriquer({ guid = LEO, nom = "Léo Lame" })
                    CompagnieDB.modeCompagnie = nil
                    CompagnieDB.etats = { [LEO] = { niveau = 10, rendues = {}, quetes = { [82001] = { finie = false, objectifs = { { fait = 1, total = 8 } } } } } }
                    charger()
                    -- Sans zone de la Compagnie : l'onglet Chaînes, en premier, dit quoi faire ; aucune case.
                    SlashCmdList.COMPAGNIE("")
                    assertTrue(CompagnieChainesFrame:IsShown(), "la fenêtre s'ouvre sur Chaînes")
                    assertEquals("Chaînes", CompagnieChainesFrameTab1:GetText())
                    assertEquals(1, PanelTemplates_GetSelectedTab(CompagnieChainesFrame))
                    assertTrue(CompagnieChainesMessage:IsShown())
                    assertEquals("Choisis la zone de la Compagnie dans le suivi.", CompagnieChainesMessage:GetText())
                    assertEquals(0, compter(casesChaines()), "pas de toile vide")
                    -- La zone choisie : ses chaînes, le début hors zone en une case, l'avancement commun.
                    CompagnieDB.zoneCompagnie = { zone = 12, date = 1, par = "Léo" }
                    evenement("GROUP_ROSTER_UPDATE")
                    assertTrue(not CompagnieChainesMessage:IsShown())
                    local c = casesChaines()
                    assertEquals(5, compter(c), "4 quêtes de la zone et Teldrassil")
                    assertEquals("Niv. 5 · 1/8", c["Les loups"].sous:GetText())
                    assertEquals("Niv. 12 · niveau 11 requis", c["Le message"].sous:GetText())
                    assertEquals("Hors zone : Teldrassil", c["Teldrassil"].sous:GetText())
                    assertEquals("Compagnie · Forêt d'Elwynn", CompagnieChainesFrame.title:GetText())
                    assertTrue(c["Les peaux"]:GetLeft() > c["Les loups"]:GetRight(), "la suite à droite de sa quête")
                    -- Clic droit sur une case : le menu du suivi.
                    local racine = menuDe(function() c["Les loups"]:Click("RightButton") end)
                    assertEquals("Les loups", entrees(racine)[1])
                    assertTrue(choisir(racine, "Écarter pour la Compagnie"))
                    local _, popup = StaticPopup_Visible("COMPAGNIE_ECARTER")
                    dits(function() popup.button1:Click() end)
                    -- Écartée avec sa suite (#34) : la chaîne se replie en une ligne ; clic, elle se déplie ; clic sur une
                    -- de ses quêtes, elle se replie.
                    local ligne = casesChaines()["Les loups — 2 quêtes"]
                    assertNotNil(ligne, "la chaîne écartée en une ligne")
                    assertEquals("Écartée · clic : déplier", ligne.sous:GetText())
                    assertNil(casesChaines()["Les peaux"])
                    ligne:Click("LeftButton")
                    assertEquals("Niv. 5 · Écartée", casesChaines()["Les loups"].sous:GetText(), "dépliée")
                    casesChaines()["Les peaux"]:Click("LeftButton")
                    assertNotNil(casesChaines()["Les loups — 2 quêtes"], "repliée")
                    casesChaines()["Les loups — 2 quêtes"]:Click("LeftButton")
                    assertTrue(choisir(menuDe(function() casesChaines()["Les loups"]:Click("RightButton") end), "Remettre dans la Compagnie"))
                    assertEquals("Niv. 5 · 1/8", casesChaines()["Les loups"].sous:GetText(), "remise")
                    -- Les onglets : Membres ouvre l'autre fenêtre à la même place ; chacune garde sa taille.
                    local haut = CompagnieChainesFrame:GetTop()
                    CompagnieChainesFrameTab2:Click()
                    assertTrue(CompagnieFrame:IsShown() and not CompagnieChainesFrame:IsShown())
                    assertEquals(2, PanelTemplates_GetSelectedTab(CompagnieFrame))
                    assertEquals(math.floor(haut), math.floor(CompagnieFrame:GetTop()), "à la même place")
                    assertTrue(CompagnieFrame:GetWidth() < CompagnieChainesFrame:GetWidth(), "tailles à part")
                    CompagnieFrameTab3:Click()
                    assertEquals(3, PanelTemplates_GetSelectedTab(CompagnieFrame))
                    CompagnieFrameTab1:Click()
                    assertTrue(CompagnieChainesFrame:IsShown() and not CompagnieFrame:IsShown(), "retour aux Chaînes")
                    -- « Voir les chaînes » dans le menu du bouton de zone du suivi.
                    CompagnieChainesFrame:Hide()
                    assertTrue(choisir(menuDe(function() CompagnieZoneBouton:Click() end), "Voir les chaînes"))
                    assertTrue(CompagnieChainesFrame:IsShown())
                    CompagnieChainesFrame:Hide()
                end)
            end)
        end)
    end)
    eteindre()
end)
