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

-- Mon groupe du jeu le temps de f(envoyes) : autres = { { guid, prénom, nom }, … } (connectés), {} : hors d'un groupe
-- (le simulateur met le joueur dans un groupe de 5) ; raid : un raid. envoyes : les messages d'add-on partis.
local function avecGroupe(autres, raid, f)
    local g = { GetNumGroupMembers = GetNumGroupMembers, IsInRaid = IsInRaid, IsInGroup = IsInGroup, UnitGUID = UnitGUID,
        UnitName = UnitName, UnitIsConnected = UnitIsConnected, envoi = C_ChatInfo.SendAddonMessage }
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
    UnitIsConnected = function(u) local a = autre(u) if a then return a[1] ~= nil end return g.UnitIsConnected(u) end
    C_ChatInfo.SendAddonMessage = function(prefixe, texte, canal)
        envoyes[#envoyes + 1] = { prefixe = prefixe, texte = texte, canal = canal }
    end
    local ok, err = pcall(f, envoyes)
    GetNumGroupMembers, IsInRaid, IsInGroup, UnitGUID, UnitName, UnitIsConnected =
        g.GetNumGroupMembers, g.IsInRaid, g.IsInGroup, g.UnitGUID, g.UnitName, g.UnitIsConnected
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
    SlashCmdList.COMPAGNIE("")
    local l = lignes()
    assertEquals(2, #l)
    assertEquals("Léo Lame", l[2].nom)
    CompagnieFrame:Hide()
    CompagnieDB.compagnie = nil
end)
