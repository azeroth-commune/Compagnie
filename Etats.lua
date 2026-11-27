-- Compagnie, les états des membres : encodage, réception, dernier état connu, envoi regroupé. La logique seule, sans
-- aucun appel à l'API du jeu (vérifié par check.lua) ; Compagnie.lua lit mon journal en direct et transporte les messages.
-- Un état : { niveau = 35, race = 1, classe = 2 (#7 : raceID, classID ; nil : inconnues),
--             quetes = { [idQuête] = { finie = false, objectifs = { { fait = 2, total = 10 }, … }, zone = "…",
--             personnelle = true (#7 : marquée à la main), partageable = false (#6 : le jeu ne la partage pas),
--             origine = { nom = "Maréchal Dughan" (nil : un objet ramassé), carte = uiMapID, x, y (%, entiers) } (#6) } },
--             rendues = { [idQuête] = true }, ecartees = { [idQuête] = { ecartee = true|false, date, par = "Léo" } },
--             avant = { [idQuête] = true } (mes quêtes d'avant encore dans mon journal), renduesAvant = { [idQuête] = true },
--             auberge = "Comté-de-l'Or", liaison = heure serveur de la liaison, finRecharge = heure serveur où la pierre
--             de foyer est prête (les trois du foyer, #9 : nil quand inconnus, ou pierre prête),
--             zoneCompagnie = { zone = areaID, date, par = "Léo" } (#24 : la zone de la Compagnie, nil sans choix),
--             prerequis = { zone = areaID, manquants = { { quete, prerequis }, … } } (#27 : mes prérequis manquants),
--             liste = { date, membres = { { guid, nom }, … } } (#23 : la liste des membres) }
-- Le texte des objectifs ne part jamais (il porte un code de grammaire du jeu, « |4…; ») : seulement les nombres, dans
-- l'ordre des objectifs ; chacun retrouve le texte dans le jeu, même pour une quête hors de son journal (Compagnie.lua).
-- Corps encodé : « niveau[:race:classe]#quête;quête…#rendue,rendue…#zone=id,id;zone=id…#écartée;écartée…#auberge#liaison#fin
-- #avant,avant…#renduesAvant,renduesAvant…#zone:date:par#zone=quête:prérequis,…#date=serveur-id:nom,… »,
-- une quête « id:finie(0|1)[p][n][:fait/total[/stock]…] » (stock : un objet échangeable que j'ai au-delà du total, objectif fini) (p : marquée personnelle, #7 ; n : non partageable, #6 ; partageable
-- ne part pas, le jeu ne le dit que pour mes quêtes), ids triés. Le 4e champ (#13) range les quêtes par zone (l'en-tête de zone de mon journal), zones triées ; vide si
-- aucune quête n'a de zone. Une zone : 1 à MAX_ZONE octets, ni caractère de contrôle, ni « | » (codes du chat), ni
-- séparateur du format ; un en-tête de mon journal qui ne l'est pas ne part pas (la quête part sans zone). Le 5e champ
-- (#21) : les décisions de la Compagnie sur les quêtes écartées, telles que je les connais, « id:1|0:date:par » (1 :
-- écartée, 0 : remise ; date : heure serveur ; par : le prénom de qui l'a décidé, mêmes règles qu'une zone), ids triés ;
-- au plus MAX_ECARTEES : les écartées d'abord (une remise récente ne pousse jamais dehors une écartée), puis les plus
-- récentes ; reçue, une décision datée de plus d'un jour après mon heure serveur fait rejeter l'état (elle
-- l'emporterait pour toujours). « partageable » ne part pas (le jeu
-- ne le dit que pour mes quêtes). Les 6e à 8e champs (#9) : l'auberge liée (mêmes règles qu'une zone), l'heure serveur
-- (GetServerTime) de la liaison et celle où la pierre de foyer sera prête ; chacun vide quand il est inconnu (ou la
-- pierre prête). Une heure et non une durée : un absent compte avec sa recharge recalculée depuis son envoi.
-- Les 9e et 10e champs (#20) : mes quêtes d'avant (parmi les quêtes de l'état : une autre fait rejeter l'état), et
-- les quêtes rendues avant mon entrée dans la Compagnie (le 3e champ : celles rendues depuis, vues par l'add-on).
-- Le 11e champ (#24) : la zone de la Compagnie telle que je la connais, « areaID:date:par » (mêmes règles qu'une
-- décision sur une quête écartée), vide sans zone choisie. Le 12e (#27) : mes prérequis manquants pour la zone de la
-- Compagnie, « zone=quête:prérequis,quête:prérequis… » (zone : celle qu'ils couvrent ; « zone » seule : rien ne manque ;
-- vide : pas de zone), au plus MAX_PREREQUIS, les premiers par quête ; jamais mes quêtes rendues (trop lourd). Le 13e
-- (#23) : la liste des membres de la Compagnie telle que je la connais, « date=serveur-id:Prénom Nom,… » (date : celle
-- du dernier changement de la liste, Membres.lua ; le GUID sans « Player- » ; le nom, mêmes règles qu'une zone), de 2 à
-- ns.MAX membres, vide hors d'une Compagnie. Le 14e (#6) : où j'ai pris mes quêtes non partageables, « id=PNJ@carte:x:y;… »
-- (le PNJ quand je l'ai acceptée, ou rien pour l'objet ramassé qui la lance ; ma position, sans « @… » dans une instance ;
-- au moins l'un des deux ; le nom, mêmes règles qu'une zone, sans « @ » ; x et y de 0 à 100), ids triés. Il passe en
-- dernier : les origines remplissent la place qui reste dans MAX_MORCEAUX (PLACE), les suivantes ne partent pas.
-- Messages d'add-on (préfixe Compagnie) : « E;idCompagnie;envoi/i/n;morceau » (un état en n morceaux bornés à 255
-- octets) et « D;idCompagnie » (demande d'état). L'expéditeur (de) est le GUID que Compagnie.lua tient du serveur.
-- Donnée reçue entre membres (CONTEXT-MAP) : servie telle quelle, mais lue strictement (un champ mal formé et tout l'état
-- est rejeté ; rien n'est jamais exécuté ni interprété) et bornée (taille, nombre de morceaux, débit par expéditeur).
local _, ns = ...
local MAX_QUETES, MAX_OBJECTIFS, MAX_RENDUES, MAX_MORCEAUX, DEBIT = 60, 20, 300, 10, 60 -- DEBIT : messages / minute
local MAX_ZONE = 48 -- octets : « Contreforts de Hautebrande » en fait 26
-- Un journal plein (25 quêtes) + 20 décisions + la zone, les prérequis et la liste des membres tient dans MAX_MORCEAUX
-- (check.lua) ; 20 et non plus 30 : une décision emporte désormais toute la chaîne de la quête (#27).
local MAX_ECARTEES, MAX_PREREQUIS = 20, 8
-- Octets d'un état : MAX_MORCEAUX morceaux, chacun sans son en-tête « E;id;99/10/10; » (id : un GUID et l'heure
-- serveur, Compagnie.lua, 33 caractères au plus). ponytail: au-delà, les origines (#6) ne partent pas ; l'écart reste,
-- avec l'endroit de la base des quêtes.
local PLACE = MAX_MORCEAUX * (255 - #"E;Player-99999-0A1B2C3D-1764000000;99/10/10;")
local AVENIR, OUBLI = 86400, 7 * 86400 -- secondes : une décision à plus d'un jour est rejetée ; une remise oubliée à 7 jours
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

local function zoneValide(z)
  return type(z) == "string" and #z >= 1 and #z <= MAX_ZONE and not z:find("[%c|#;:,/=]")
end
local function nomValide(n) return zoneValide(n) and not n:find("@", 1, true) end -- le nom d'un PNJ (#6)
-- Une position que decoder accepte (#6) : une position hors carte (x < 0 ou > 100) rendrait tout mon état illisible.
local function posValide(o)
  return (entier(tostring(o.carte), 2147483647) or 0) >= 1 and entier(tostring(o.x), 100) and entier(tostring(o.y), 100)
end

-- Une décision datée (la zone de la Compagnie) : « valeur:date:par », vide sans décision.
local function decision(d, cle)
  return d and table.concat({ d[cle], d.date, zoneValide(d.par) and d.par or "?" }, ":") or ""
end

local function prerequis(p)
  if not p then return "" end
  local t = {}
  for i, x in ipairs(p.manquants) do
    if i > MAX_PREREQUIS then break end -- ponytail: au-delà, les suivants partiront quand les premiers seront faits
    t[i] = x.quete .. ":" .. x.prerequis
  end
  return p.zone .. (#t > 0 and "=" .. table.concat(t, ",") or "")
end

local function listeMembres(l)
  if not l then return "" end
  local t = {}
  for i, m in ipairs(l.membres) do t[i] = m.guid:gsub("^Player%-", "") .. ":" .. (zoneValide(m.nom) and m.nom or "?") end
  return (l.date or 0) .. "=" .. table.concat(t, ",")
end

-- Le nom d'un objectif, d'après son texte du jeu : sans compte, sans code de grammaire ni « : » final
-- (« Raptor flagellant : 2/10 |4personnage tué:personnages tués; » → « Raptor flagellant ») ; nil sans texte.
-- Celui d'un objectif de monstre est le nom du monstre (les plaques, Compagnie.lua).
function ns.libelle(t)
  if type(t) ~= "string" then return nil end
  t = t:gsub("|4[^;]*;", ""):gsub("%c", ""):gsub("%d+/%d+", ""):match("^%s*(.-)%s*$"):gsub("%s*:$", "")
  return t ~= "" and t or nil
end

function ns.encoder(etat)
  local quetes, rendues, zones = {}, {}, {}
  for _, id in ipairs(trier(etat.quetes)) do
    local q = etat.quetes[id]
    local t = { id, (q.finie and 1 or 0) .. (q.personnelle and "p" or "") .. (q.partageable == false and "n" or "") }
    for _, o in ipairs(q.objectifs or {}) do
      t[#t + 1] = o.fait .. "/" .. o.total .. ((o.stock or 0) > o.total and o.fait == o.total and "/" .. o.stock or "")
    end
    quetes[#quetes + 1] = table.concat(t, ":")
    if zoneValide(q.zone) then zones[q.zone] = zones[q.zone] or {}; table.insert(zones[q.zone], id) end
  end
  for _, id in ipairs(trier(etat.rendues)) do rendues[#rendues + 1] = id end
  local decisions, ecartees = {}, {}
  for id, d in pairs(etat.ecartees or {}) do decisions[#decisions + 1] = { id = id, d = d } end
  table.sort(decisions, function(a, b) -- les écartées d'abord, puis les plus récentes
    if a.d.ecartee ~= b.d.ecartee then return a.d.ecartee end
    return a.d.date > b.d.date
  end) -- ponytail: au-delà de MAX_ECARTEES, les plus anciennes ne partent plus
  for i = #decisions, MAX_ECARTEES + 1, -1 do decisions[i] = nil end
  table.sort(decisions, function(a, b) return a.id < b.id end)
  for _, x in ipairs(decisions) do
    ecartees[#ecartees + 1] = table.concat({ x.id, x.d.ecartee and 1 or 0, x.d.date, zoneValide(x.d.par) and x.d.par or "?" }, ":")
  end
  local avant = {}
  for _, id in ipairs(trier(etat.avant)) do if etat.quetes and etat.quetes[id] then avant[#avant + 1] = id end end
  local parZone = {}
  for _, z in ipairs(trier(zones)) do parZone[#parZone + 1] = z .. "=" .. table.concat(zones[z], ",") end
  local niveau = (etat.niveau or 0) .. (etat.race and etat.classe and ":" .. etat.race .. ":" .. etat.classe or "")
  local corps = niveau .. "#" .. table.concat(quetes, ";") .. "#" .. table.concat(rendues, ",") .. "#" ..
    table.concat(parZone, ";") .. "#" .. table.concat(ecartees, ";") .. "#" ..
    (zoneValide(etat.auberge) and etat.auberge or "") .. "#" .. (etat.liaison or "") .. "#" .. (etat.finRecharge or "") ..
    "#" .. table.concat(avant, ",") .. "#" .. table.concat(trier(etat.renduesAvant), ",") .. "#" .. decision(etat.zoneCompagnie, "zone") .. "#" .. prerequis(etat.prerequis) .. "#" .. listeMembres(etat.liste)
  local origines, place = {}, PLACE - #corps - 1
  for _, id in ipairs(trier(etat.quetes)) do
    local q = etat.quetes[id]
    local o = q.partageable == false and q.origine or {}
    local x = (nomValide(o.nom) and "=" .. o.nom or "") .. (posValide(o) and "@" .. o.carte .. ":" .. o.x .. ":" .. o.y or "")
    if x ~= "" and #x + #tostring(id) < place then
      origines[#origines + 1] = id .. x
      place = place - #origines[#origines] - 1
    end
  end
  return corps .. "#" .. table.concat(origines, ";")
end

-- L'état, ou nil au moindre champ mal formé. maintenant : mon heure serveur (nil : pas de contrôle des dates, les tests
-- du format).
function ns.decoder(corps, maintenant)
  local f = couper(corps, "#")
  local n, rc, race, classe = (#f == 14 and f[1] or ""):match("^(%d+)(:?(%d*):?(%d*))$")
  local niveau = n and entier(n, 200)
  race, classe = race and entier(race, 999), classe and entier(classe, 999)
  if not niveau or niveau < 1 or rc ~= "" and not (race and classe and rc == ":" .. race .. ":" .. classe) then return end
  local etat = { niveau = niveau, race = race, classe = classe, quetes = {}, rendues = {}, ecartees = {}, avant = {}, renduesAvant = {} }
  local liste = f[2] == "" and {} or couper(f[2], ";")
  if #liste > MAX_QUETES then return end
  for _, q in ipairs(liste) do
    local c = couper(q, ":")
    local id = entier(c[1], 2147483647) -- questID : entier 32 bits signé
    local finie, perso, np = (c[2] or ""):match("^([01])(p?)(n?)$")
    if not id or id < 1 or etat.quetes[id] or not finie or #c - 2 > MAX_OBJECTIFS then return end
    local objectifs = {}
    for k = 3, #c do
      local a, b, s = c[k]:match("^(%d+)/(%d+)/?(%d*)$")
      a, b, s = a and entier(a, 99999), b and entier(b, 99999), s ~= "" and entier(s, 99999) or nil
      if not (a and b) or a > b or s and (a < b or s <= b) then return end
      objectifs[k - 2] = { fait = a, total = b, stock = s }
    end
    etat.quetes[id] = { finie = finie == "1", personnelle = perso == "p" or nil, objectifs = objectifs }
    if np == "n" then etat.quetes[id].partageable = false end
  end
  liste = f[5] == "" and {} or couper(f[5], ";")
  if #liste > MAX_ECARTEES then return end
  for _, x in ipairs(liste) do
    local c = couper(x, ":")
    local id, date = entier(c[1], 2147483647), entier(c[3] or "", 2147483647)
    if #c ~= 4 or not (id and id >= 1 and date and date >= 1) or etat.ecartees[id] or (c[2] ~= "0" and c[2] ~= "1")
      or not zoneValide(c[4]) or (maintenant and date > maintenant + AVENIR) then return end
    -- ponytail: « par » n'est pas authentifié (un membre peut signer d'un autre prénom) ; seuls des membres sont lus.
    etat.ecartees[id] = { ecartee = c[2] == "1", date = date, par = c[4] }
  end
  for champ, ids in pairs({ [3] = etat.rendues, [9] = etat.avant, [10] = etat.renduesAvant }) do
    liste = f[champ] == "" and {} or couper(f[champ], ",")
    if #liste > MAX_RENDUES then return end
    for _, r in ipairs(liste) do
      local id = entier(r, 2147483647)
      if not id or id < 1 or (champ == 9 and (ids[id] or not etat.quetes[id])) then return end
      ids[id] = true
    end
  end
  for champ, cle in pairs({ [7] = "liaison", [8] = "finRecharge" }) do
    if f[champ] ~= "" then
      local n = entier(f[champ], 2147483647)
      if not n or n < 1 then return end
      etat[cle] = n
    end
  end
  if f[6] ~= "" then
    if not zoneValide(f[6]) then return end
    etat.auberge = f[6]
  end
  if f[11] ~= "" then
    local c = couper(f[11], ":")
    local z, date = entier(c[1], 2147483647), entier(c[2] or "", 2147483647)
    if #c ~= 3 or not (z and z >= 1 and date and date >= 1) or not zoneValide(c[3])
      or (maintenant and date > maintenant + AVENIR) then return end
    etat.zoneCompagnie = { zone = z, date = date, par = c[3] }
  end
  if f[12] ~= "" then
    local z, liste = f[12]:match("^(%d+)=?(.*)$")
    z = z and entier(z, 2147483647)
    if not (z and z >= 1) or (liste == "" and f[12]:find("=", 1, true)) then return end
    local manquants = {}
    for _, x in ipairs(liste == "" and {} or couper(liste, ",")) do
      local q, p = x:match("^(%d+):(%d+)$")
      q, p = q and entier(q, 2147483647), p and entier(p, 2147483647)
      if not (q and p and q >= 1 and p >= 1) or #manquants >= MAX_PREREQUIS then return end
      manquants[#manquants + 1] = { quete = q, prerequis = p }
    end
    etat.prerequis = { zone = z, manquants = manquants }
  end
  if f[13] ~= "" then
    local date, liste = f[13]:match("^(%d+)=(.*)$")
    date = date and entier(date, 2147483647)
    local membres, vus = {}, {}
    for _, x in ipairs(date and couper(liste, ",") or {}) do
      local g, nom = x:match("^(%d+%-%w+):(.*)$")
      if not (g and #g <= 24 and zoneValide(nom)) or vus[g] then return end
      vus[g] = true
      membres[#membres + 1] = { guid = "Player-" .. g, nom = nom }
    end
    if not date or #membres < 2 or #membres > ns.MAX or (maintenant and date > maintenant + AVENIR) then return end
    etat.liste = { date = date, membres = membres }
  end
  local vues = {}
  for _, champ in ipairs(f[4] == "" and {} or couper(f[4], ";")) do
    local z, ids = champ:match("^([^=]*)=(.*)$")
    if not (z and zoneValide(z)) or vues[z] or ids == "" then return end
    vues[z] = true
    for _, r in ipairs(couper(ids, ",")) do
      local q = etat.quetes[entier(r, 2147483647) or 0]
      if not q or q.zone then return end -- une quête absente de l'état, ou rangée deux fois
      q.zone = z
    end
  end
  for _, x in ipairs(f[14] == "" and {} or couper(f[14], ";")) do
    local id, egal, nom, pos = x:match("^(%d+)(=?)([^@]*)(.*)$")
    local q = id and etat.quetes[entier(id, 2147483647) or 0]
    local carte, px, py = (pos or ""):match("^@(%d+):(%d+):(%d+)$")
    carte, px, py = carte and entier(carte, 2147483647), px and entier(px, 100), py and entier(py, 100)
    if not (q and q.partageable == false and not q.origine) or (egal == "") ~= (nom == "") or nom ~= "" and not nomValide(nom)
      or pos ~= "" and not (carte and carte >= 1 and px and py) or nom == "" and pos == "" then return end
    q.origine = { nom = nom ~= "" and nom or nil, carte = carte, x = px, y = py }
  end
  return etat
end

-- Les messages d'un envoi (numéro 1-99) : chacun tient dans les 255 octets d'un message d'add-on.
function ns.morceaux(id, corps, envoi)
  local taille = 255 - #("E;" .. id .. ";99/10/10;")
  local n, t = math.max(1, math.ceil(#corps / taille)), {}
  if n > MAX_MORCEAUX then return t end -- un journal plein tient (check.lua) ; au-delà, rien ne part et ns.signaler le dit
  for i = 1, n do t[i] = ("E;%s;%d/%d/%d;%s"):format(id, envoi, i, n, corps:sub((i - 1) * taille + 1, i * taille)) end
  return t
end

-- Un message E ou D reçu de de (GUID). e = { db = CompagnieDB, moi = mon GUID } ; io = { maj = fn(), demande = fn(de),
-- maintenant = fn() -> secondes (GetTime : le débit), heure = fn() -> heure serveur (les dates des décisions),
-- annoncer = fn(décisions à annoncer, voir ns.fusionner), zone = fn(zone de la Compagnie reçue, plus récente),
-- liste = fn(changement de la liste des membres, voir ns.fusionnerListe) }. Rend true si le message est un message d'état (traité ou ignoré).
function ns.recevoirEtat(e, de, texte, io)
  local verbe, id, reste = texte:match("^([ED]);([^;]+);?(.*)$")
  if not verbe then return false end
  local c, p = e.db.compagnie, e.proposition
  -- Un invité (#23) qui a accepté écoute l'état de qui l'a invité : la liste qu'il porte le fait entrer.
  local invite = not c and p and p.invitation and p.accepte and p.id == id and p.de == de
  if de == e.moi or not (invite or c and c.id == id and ns.membre(c, de)) then return true end -- un non-membre : ignoré
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
  local etat = ns.decoder(table.concat(b), io.heure())
  if not etat then return true end
  local liste = ns.fusionnerListe(e, id, etat.liste)
  if invite and not (liste and liste.entre) then return true end -- pas encore dans sa liste
  e.db.etats = e.db.etats or {}
  e.db.etats[de] = etat -- le dernier état connu : une donnée propre, sauvegardée
  local changees, zone = ns.fusionner(e.db, etat.ecartees), ns.fusionnerZone(e.db, etat.zoneCompagnie)
  io.maj()
  if #changees > 0 and not invite then io.annoncer(changees) end -- l'invité les trouve dans l'onglet Écartées
  if zone then io.zone(etat.zoneCompagnie) end
  if liste then io.liste(liste) end
  return true
end

-- Écarter (ecartee = true) ou remettre une quête (#21) : une décision de la Compagnie, datée (heure serveur), avec le
-- prénom de qui l'a prise ; db.ecartees la garde (donnée propre, envoyée avec mon état).
function ns.decider(db, id, ecartee, par, date)
  db.ecartees = db.ecartees or {}
  db.ecartees[id] = { ecartee = ecartee, date = date, par = par }
end

-- Les décisions reçues avec l'état d'un membre : la plus récente l'emporte, quête par quête (à la même seconde, écarter
-- l'emporte sur remettre). Rend celles à annoncer, { { quete = id, ecartee, par }, … } triées par quête : une écartée
-- qui a changé, une remise seulement si je connaissais la quête écartée (une vieille remise d'une quête inconnue : rien).
function ns.fusionner(db, recues)
  local changees = {}
  for id, d in pairs(recues or {}) do
    db.ecartees = db.ecartees or {}
    local a = db.ecartees[id]
    if not a or d.date > a.date or (d.date == a.date and d.ecartee and not a.ecartee) then
      db.ecartees[id] = { ecartee = d.ecartee, date = d.date, par = d.par }
      if d.ecartee or (a and a.ecartee) then changees[#changees + 1] = { quete = id, ecartee = d.ecartee, par = d.par } end
    end
  end
  table.sort(changees, function(a, b) return a.quete < b.quete end)
  return changees
end

-- La liste des membres reçue avec l'état d'un membre (#23) : plus récente que la mienne, elle la remplace (ma Compagnie,
-- d'id id). Rend ce qui change, ou nil : { entre = true } (invité, j'y suis : j'entre), { sorti = true } (je n'y suis
-- plus : plus de Compagnie), sinon { ajoutes = { noms }, retires = { noms } }.
function ns.fusionnerListe(e, id, recue)
  local c = e.db.compagnie
  if not recue or c and recue.date <= (c.date or 0) then return nil end
  local l = { membres = recue.membres }
  if not ns.membre(l, e.moi) then
    if not c then return nil end
    e.db.compagnie = nil
    return { sorti = true }
  end
  local t = { ajoutes = {}, retires = {} }
  for _, m in ipairs(recue.membres) do if c and not ns.membre(c, m.guid) then table.insert(t.ajoutes, m.nom) end end
  for _, m in ipairs(c and c.membres or {}) do if not ns.membre(l, m.guid) then table.insert(t.retires, m.nom) end end
  if not c then t, e.proposition = { entre = true }, nil end
  local membres = {} -- une copie ; un nom inconnu de l'expéditeur (« ? ») garde celui que je connais
  for i, m in ipairs(recue.membres) do
    local k = c and ns.membre(c, m.guid)
    membres[i] = { guid = m.guid, nom = m.nom == "?" and k and c.membres[k].nom or m.nom }
  end
  e.db.compagnie = { id = id, date = recue.date, membres = membres }
  return t
end

-- La zone de la Compagnie reçue avec l'état d'un membre (#24) : la plus récente l'emporte (à la même seconde, le plus
-- grand areaID, pour que tous retiennent la même) ; rend true si elle a changé (à annoncer).
function ns.fusionnerZone(db, recue)
  local a = db.zoneCompagnie
  if not recue or a and (recue.date < a.date or recue.date == a.date and recue.zone <= a.zone) then return false end
  db.zoneCompagnie = { zone = recue.zone, date = recue.date, par = recue.par }
  return true
end

-- Les remises datées de plus de OUBLI avant maintenant (heure serveur) sont oubliées : les décisions ne s'accumulent pas
-- (une écartée reste, elle sert tant que la quête existe).
-- ponytail: un membre absent plus de 7 jours qui a manqué une remise ramène l'écartée (annoncée : « Remettre » de nouveau).
function ns.purger(db, maintenant)
  for id, d in pairs(db.ecartees or {}) do
    if not d.ecartee and d.date < maintenant - OUBLI then db.ecartees[id] = nil end
  end
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
    liste[i] = { nom = m.guid, niveau = etat.niveau, race = etat.race, classe = etat.classe, quetes = etat.quetes, rendues = etat.rendues,
      renduesAvant = etat.renduesAvant, avant = etat.avant, auberge = etat.auberge, liaison = etat.liaison, finRecharge = etat.finRecharge,
      prerequis = etat.prerequis, absent = m.guid ~= moi and not presents[m.guid] }
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
  return { nom = etat.nom, niveau = etat.niveau, race = etat.race, classe = etat.classe, quetes = quetes, rendues = etat.rendues, renduesAvant = etat.renduesAvant,
    avant = etat.avant, prerequis = etat.prerequis,
    auberge = etat.auberge, liaison = etat.liaison, finRecharge = etat.finRecharge, absent = etat.absent }
end

-- Un changement de mon état (force : une demande d'état, il part même inchangé). Une rafale d'événements ne programme
-- qu'un envoi, ns.DELAI_ENVOI plus tard, avec l'état lu à ce moment ; un état inchangé ne repart pas.
-- io = { programmer = fn(délai, fn), monEtat = fn() -> état, envoyerEtat = fn(message) -> false si refusé,
-- trop = fn() : l'état ne tient pas dans MAX_MORCEAUX, rien ne part (jamais un état tronqué) ; dit une fois, jusqu'à ce
-- qu'un état tienne de nouveau }.
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
    e.force, e.envoi = false, (e.envoi or 0) % 99 + 1
    local morceaux, tous = ns.morceaux(c.id, corps, e.envoi), true
    if #morceaux == 0 and not e.trop then io.trop() end
    e.trop = #morceaux == 0
    for _, m in ipairs(morceaux) do tous = io.envoyerEtat(m) ~= false and tous end
    -- Noté comme parti seulement s'il est entré en entier dans la file d'envoi : sinon il repartira.
    e.dernier = tous and #morceaux > 0 and corps or nil
  end)
end
