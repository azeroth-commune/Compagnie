-- Tests d'intégration dans wow-ui-sim (tools/sim.sh test Compagnie) : Compagnie chargé avec le socle Azeroth Commune.
-- Le groupe du jeu est simulé en bouchonnant les appels du jeu (Léo dans party1) ; les messages d'add-on envoyés sont
-- retenus, ceux de Léo arrivent par l'événement CHAT_MSG_ADDON du cadre CompagnieMessages.
local LEO, MIRA = "Player-1-0000ABCD", "Player-1-0000BCDE"

local function moi() return { guid = UnitGUID("player"), nom = AzerothCommune.Personnage().nom } end

-- Les lignes affichées de la liste des membres, dans l'ordre : { nom, presence, retirer = bouton ou nil }.
local function lignes()
    local t = {}
    local function parcourir(f)
        for _, c in ipairs({ f:GetChildren() }) do
            if c.item and c:IsShown() then t[#t + 1] = c end
            parcourir(c)
        end
    end
    parcourir(CompagnieFrame)
    table.sort(t, function(a, b) return a:GetTop() > b:GetTop() end)
    for i, r in ipairs(t) do
        local b = r.cells[3]
        t[i] = { nom = r.cells[1]:GetText(), presence = r.cells[2]:GetText(), retirer = b:IsShown() and b or nil }
    end
    return t
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
    SlashCmdList.COMPAGNIE("")
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
    end)
end)

test("quitter et retirer mettent à jour la liste", function()
    fabriquer({ guid = LEO, nom = "Léo Lame" }, { guid = MIRA, nom = "Mira Feuille" })
    avecLeo(function(envoyes)
        SlashCmdList.COMPAGNIE("")
        assertEquals(3, #lignes())
        dits(function() recu("Q;essai") end) -- Léo quitte
        local l = lignes()
        assertEquals(2, #l)
        assertEquals("Mira Feuille", l[2].nom)
        fabriquer({ guid = LEO, nom = "Léo Lame" }, { guid = MIRA, nom = "Mira Feuille" })
        SlashCmdList.COMPAGNIE("")
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
    SlashCmdList.COMPAGNIE("")
    local l = lignes()
    assertEquals(2, #l)
    assertEquals("Léo Lame", l[2].nom)
    CompagnieFrame:Hide()
    CompagnieDB.compagnie = nil
end)

---------------------------------------------------------------------------------------------------
-- Le mode Compagnie et l'échange des états (#4).

-- Mon journal le temps de f : quetes = { { id, titre, finie, zone, objectifs = { { text, numFulfilled, numRequired }, … } }, … }
-- (C_QuestLog.GetInfo, GetQuestObjectives, IsComplete bouchonnés ; info.isComplete reste nil comme sur Forever).
-- Le journal range les quêtes sous des en-têtes de zone (isHeader), dans l'ordre donné ; sans zone, sous ICI, la zone où
-- je suis (GetRealZoneText bouchonné : ici, ou ICI).
local ICI, ici = "Forêt d'Elwynn", nil
local function avecJournal(quetes, f)
    local q, g = C_QuestLog, {}
    for _, n in ipairs({ "GetInfo", "GetQuestObjectives", "IsComplete", "IsQuestFlaggedCompleted", "GetTitleForQuestID",
        "IsUnitOnQuest" }) do g[n] = q[n] end
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
            t[k] = { text = o[1], numFulfilled = o[2], numRequired = o[3], finished = tonumber(o[2]) == o[3] }
        end
        return t
    end
    q.IsComplete = function(id) return parId[id] and parId[id].finie or false end
    q.IsQuestFlaggedCompleted = function() return false end
    q.GetTitleForQuestID = function() return nil end
    q.IsUnitOnQuest = function() return nil end
    local ok, err = pcall(f)
    for n, fn in pairs(g) do q[n] = fn end
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
local function suivi() return CompagnieSuiviQuetes:GetText() or "" end
local function contient(t, motif) return t:find(motif, 1, true) ~= nil end
local function eteindre() -- mode éteint, plus de Compagnie : le suivi du jeu revient pour les tests suivants
    CompagnieDB.compagnie, CompagnieDB.etats, CompagnieDB.modeCompagnie = nil, nil, nil
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
            chuchote("E;essai;1/1/1;10#1001:1:8/8;95789:0:1/10##")
            assertEquals(1, CompagnieDB.etats[LEO].quetes[1001].objectifs[1].fait == 8 and 1 or 0, "état reçu gardé")
            t = suivi()
            assertTrue(contient(t, "Patte de loup : 8/8") and contient(t, "À rendre"), t)
            assertTrue(not contient(t, "En attente"), "Léo n'est pas nommé : " .. t)
            -- Un état d'un non-membre ne change rien.
            chuchote("E;essai;1/1/1;10#1001:0:0/8##", "Zoé Pierre")
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
            SlashCmdList.COMPAGNIE("")
            assertTrue(contient(CompagnieModeBouton:GetText(), "non"), CompagnieModeBouton:GetText())
            CompagnieModeBouton:Click()
            assertTrue(contient(CompagnieModeBouton:GetText(), "oui"), CompagnieModeBouton:GetText())
            assertTrue(not ObjectiveTrackerFrame:IsShown() and CompagnieSuiviFrame:IsShown(), "rallumé")
            CompagnieFrame:Hide()
            -- La croix du suivi éteint le mode.
            dits(function() CompagnieSuiviFrame:Hide() end)
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
            chuchote("E;essai;1/1/1;10#1001:0:5/8##")
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
            assertTrue(m.texte:find("^E;essai;%d+/1/1;%d+#1001:0:3/8##Forêt d'Elwynn=1001$") ~= nil, m.texte)
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

test("un membre hors du groupe entendu puis muet : redemandé, absent au bout de 2 min sans réponse", function()
    avecJournal({ pattes(8) }, function()
        avecGroupe({}, false, function(envoyes)
            fabriquer({ guid = LEO, nom = "Léo Lame" })
            CompagnieDB.etats = nil
            charger()
            ecouler(5)
            chuchote("E;essai;1/1/1;10#1001:0:5/8##")
            assertTrue(not contient(suivi(), "En attente"), "Léo vient d'écrire : présent")
            local n = #envoyes
            ecouler(125)
            ecouler(30)
            local demandes = 0
            for i = n + 1, #envoyes do
                if envoyes[i].texte == "D;essai" and envoyes[i].cible == "Léo Lame" then demandes = demandes + 1 end
            end
            assertTrue(demandes >= 1 and demandes <= 3, "demandé une fois par minute de silence : " .. demandes)
            assertTrue(contient(suivi(), "En attente de Léo"), "sans réponse depuis 2 min : absent, " .. suivi())
            chuchote("E;essai;2/1/1;10#1001:0:5/8##") -- il répond
            assertTrue(not contient(suivi(), "En attente"), "de nouveau présent")
        end)
    end)
    eteindre()
end)

test("un membre du groupe déconnecté n'est pas présent, même entendu il y a peu", function()
    avecJournal({ pattes(8) }, function()
        fabriquer({ guid = LEO, nom = "Léo Lame" })
        charger()
        avecGroupe({}, false, function() chuchote("E;essai;1/1/1;10#1001:0:5/8##") end)
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
            assertTrue(envoyes[#envoyes].texte:find("#1001:0:2/8#", 1, true) ~= nil, envoyes[#envoyes].texte)
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
            assertTrue(CompagnieSuiviQuetes:GetStringHeight() > UIParent:GetHeight() * 0.6, "assez de quêtes pour dépasser")
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
