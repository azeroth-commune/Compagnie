-- Compagnie, la couche du jeu : le groupe du jeu, les messages d'add-on, la proposition, la fenêtre et la commande. La
-- logique des membres est dans Membres.lua (pure) ; ici, seulement ce que le jeu donne et ce qu'il affiche.
-- Présent : un membre connecté dans mon groupe du jeu (donné par le serveur : GUID, UnitIsConnected) ; sinon absent.
-- Rien n'est deviné, et aucun message n'est chuchoté (un chuchotement à un absent fait écrire « Aucun joueur nommé … »
-- au serveur) : tout part au groupe du jeu, donc quitter et retirer n'atteignent que les membres présents.
-- ponytail: un absent ne l'apprend pas à son retour ; l'échange des états de quêtes (tranche suivante), qui se fait en
-- rejoignant le groupe, pourra porter la liste des membres.
local _, ns = ...
local AC = AzerothCommune
local PREFIXE, DELAI = "Compagnie", 60 -- délai de réponse à une proposition, en secondes
local e = { db = {} } -- l'état de Membres.lua ; db devient CompagnieDB au chargement

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
  maj = function() if CompagnieFrame and CompagnieFrame:IsShown() then dessiner() end end,
}

StaticPopupDialogs.COMPAGNIE_PROPOSITION = {
  text = "%s te propose de fonder une Compagnie avec ce groupe : vous ferez l'aventure ensemble. En être membre ?",
  button1 = "Accepter", button2 = "Refuser",
  OnAccept = function() ns.repondre(e, true, jeu) end,
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
-- La fenêtre : la liste des membres, présent ou absent, « Retirer » sur les autres ; « Fonder » ou « Quitter ».
local tableau, vide, boutonFonder, boutonQuitter
local COLONNES = {
  { key = "nom", title = "Membre", w = 180, get = function(m) return m.nom end },
  { key = "presence", title = "Présence", w = 80, get = function(m) return m.presence end,
    fmt = function(v) return (v == "présent" and "|cff59cc73" or "|cff999999") .. v .. "|r" end },
  { key = "retirer", w = 80, button = function(m) if m.guid ~= moi() then return "Retirer" end end,
    click = function(m) ns.retirer(e, moi(), m.guid, jeu) end },
}

function dessiner()
  local c, presents, lignes = e.db.compagnie, {}, {}
  for _, p in ipairs(groupe()) do presents[p.guid] = true end
  for i, m in ipairs(c and c.membres or {}) do
    lignes[i] = { guid = m.guid, nom = m.nom, presence = presents[m.guid] and "présent" or "absent" }
  end
  tableau:SetData(lignes)
  vide:SetShown(not c)
  boutonFonder:SetShown(not c)
  boutonQuitter:SetShown(c ~= nil)
end

local function bouton(f, texte, fn)
  local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  b:SetSize(100, 22)
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
  end
  CompagnieFrame:Show()
  dessiner()
end

---------------------------------------------------------------------------------------------------
-- Messages d'add-on : seulement du groupe du jeu, d'un expéditeur que le serveur y nomme (son GUID vient du groupe).
local cadre = CreateFrame("Frame", "CompagnieMessages")
for _, ev in ipairs({ "ADDON_LOADED", "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE" }) do cadre:RegisterEvent(ev) end
cadre:SetScript("OnEvent", function(_, ev, a1, texte, canal, expediteur)
  if ev == "ADDON_LOADED" then
    if a1 == "Compagnie" then
      CompagnieDB = CompagnieDB or {}
      e.db = CompagnieDB
    end
  elseif ev == "GROUP_ROSTER_UPDATE" then
    jeu.maj()
  elseif a1 == PREFIXE and (canal == "PARTY" or canal == "RAID") and type(texte) == "string" and type(expediteur) == "string" then
    local g, nom = groupe(), AC.Destinataire(expediteur)
    for _, p in ipairs(g) do
      if p.nom == nom then return ns.recevoir(e, moi(), g, p.guid, texte, jeu) end
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
  ouvrir()
end
