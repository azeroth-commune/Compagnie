-- Compagnie, le calcul de la Compagnie : une fonction pure, sans aucun appel à l'API du jeu (vérifié par check.lua).
-- Entrée : la liste des membres, chacun avec son état (dernier état connu pour un absent) :
--   { nom = "Léo", niveau = 10, absent = true,
--     quetes = { [idQuête] = { finie = false, objectifs = { { texte = "Patte de loup", fait = 5, total = 8 }, … } } },
--     avant = { [idQuête] = true } (ses quêtes d'avant, #20 : dans son journal à son entrée dans la Compagnie),
--     rendues = { [idQuête] = true } (rendues depuis son entrée), renduesAvant = { [idQuête] = true } (avant),
--     auberge = "Comté-de-l'Or", liaison = 1764000000, finRecharge = 1764002400 } (heures serveur ; nil : inconnu, ou
--     pierre prête)
--     (une quête peut porter sa zone : zone = "Forêt d'Elwynn", et partageable = true : seulement dans mon journal, lu
--     en direct, le jeu ne le dit que pour mes quêtes)
-- maintenant : l'heure serveur (pour la pierre de la Compagnie).
-- ecartees : les décisions de la Compagnie (#21), { [idQuête] = { ecartee = true (false : remise), date, par = "Léo" } } ;
--   une quête écartée emporte sa chaîne (#27, ns.ecarteesEffectives).
-- base : la base des quêtes du socle ({ [id] = { zone, suites, prerequis, … } }, vide : aucune chaîne) ; zone : la zone
--   de la Compagnie (#24, areaID, nil : pas de contrôle des prérequis) ; chaque membre porte alors ses prérequis
--   manquants : prerequis = { zone = la zone qu'ils couvrent, manquants = { { quete, prerequis }, … } } (#27).
-- Sortie : { niveau = 9, foyer = "Comté-de-l'Or", pierre = 2400 (secondes avant qu'elle soit prête ; 0 : prête),
--           quetes = { [idQuête] = { objectifs = { … }, aRendre = false, enAttente = { "Léo" }, zone = … } },
--           aPart = { { quete = id, membre = "Léo", objectifs = { … }, aRendre = true, zone = …, ecartee = true } },
--           aFaire = { { type = "partager", membre = "Virgile", quete = id, manquants = { "Léo" } },
--                      { type = "ecartee", membre = "Léo", quete = id, par = "Virgile" },
--                      { type = "avance", membre = "Léo", quete = id, par = { "Virgile" } },
--                      { type = "foyer", membre = "Léo", auberge = "Comté-de-l'Or" },
--                      { type = "prerequis", membre = "Léo", quete = id, prerequis = id, chaine, zone, donneur, manquants,
--                        tous, aControler } },
--           aControler = { "Mira" } }
-- Les quêtes de la Compagnie sont celles qu'au moins un membre a en cours, sauf une quête écartée (#21) et une quête
-- d'avant (#20) pour tous ceux qui l'ont : elle est à part (aPart, chez chaque membre qui l'a, avec son avancement à lui),
-- sans faire attendre personne, sauf si tous les membres l'ont. Dès qu'un membre l'a prise après son entrée, elle est de
-- la Compagnie : les quêtes d'avant des autres comptent normalement pour elle, et qui ne l'a pas reçoit « Partager ».
-- Pour chaque quête de la Compagnie, membre par membre :
--   - en cours : son avancement compte, objectif par objectif (le moins avancé l'emporte) ;
--   - déjà rendue (avant ou après son entrée) : il ne retient plus la Compagnie ;
--   - ni l'un ni l'autre : il compte à 0 et la Compagnie l'attend (jamais à rendre sans lui).
-- Le texte d'un objectif (affichage seulement) est pris chez le membre qui l'a, quel que soit son avancement.
-- Un absent compte comme les autres, avec son dernier état connu : le calcul ne lit donc pas « absent ».
-- Le foyer de la Compagnie (#9) : l'auberge du membre lié le plus récemment, sans vote ni chef. Une liaison sans date
-- (faite add-on éteint : rien n'est deviné) ne l'emporte jamais ; aucune date connue : pas de foyer.
-- La pierre de la Compagnie : prête quand celle de chaque membre l'est ; sinon le plus long reste, sans dire de qui.
-- Comme le niveau, un membre jamais entendu ne compte pas.
local _, ns = ...

local function rendue(m, id) return m.rendues and m.rendues[id] or m.renduesAvant and m.renduesAvant[id] end

function ns.calculer(membres, maintenant, ecartees, base, zone)
  base = base or {}
  local quetes, aPart, niveau, foyer, recent, pierre = {}, {}, nil, nil, 0, 0
  local tenue, prise = {}, {} -- [id] = combien de membres l'ont en cours ; [id] = true : un membre l'a prise après son entrée
  for _, m in ipairs(membres) do
    if m.niveau and (not niveau or m.niveau < niveau) then niveau = m.niveau end -- un membre jamais entendu : sans niveau
    if m.auberge and (m.liaison or 0) > recent then foyer, recent = m.auberge, m.liaison end
    if m.finRecharge then pierre = math.max(pierre, m.finRecharge - maintenant) end
    for id in pairs(m.quetes or {}) do
      tenue[id] = (tenue[id] or 0) + 1
      if not (m.avant and m.avant[id]) then prise[id] = true end
    end
  end
  ecartees = ns.ecarteesEffectives(ecartees, base) -- avec les chaînes qu'elles emportent (#27)
  local function ecartee(id) return ecartees[id] ~= nil end
  local function commune(id) return not ecartee(id) and (prise[id] or tenue[id] == #membres) end
  for id in pairs(tenue) do if commune(id) then quetes[id] = { objectifs = {}, aRendre = true, enAttente = {} } end end
  for _, m in ipairs(membres) do
    for id, q in pairs(m.quetes or {}) do
      if not commune(id) then
        aPart[#aPart + 1] = { quete = id, membre = m.nom, objectifs = q.objectifs or {}, aRendre = q.finie == true, zone = q.zone,
          ecartee = ecartee(id) }
      end
    end
  end
  local ordre = {}
  for i, m in ipairs(membres) do ordre[m.nom] = i end
  table.sort(aPart, function(a, b) if a.quete ~= b.quete then return a.quete < b.quete end return ordre[a.membre] < ordre[b.membre] end)
  for id, commune in pairs(quetes) do
    for _, m in ipairs(membres) do
      local q = m.quetes and m.quetes[id]
      for i, o in ipairs(q and q.objectifs or {}) do
        local c = commune.objectifs[i]
        if not c or o.fait < c.fait then commune.objectifs[i] = { texte = o.texte or c and c.texte, fait = o.fait, total = o.total }
        elseif not c.texte then c.texte = o.texte end -- le texte ne vient que de mon journal (Etats.lua) : pris chez qui l'a
      end
      commune.zone = commune.zone or q and q.zone -- la zone (affichage seulement) : prise chez qui l'a
      if not (q and q.finie or rendue(m, id)) then
        commune.aRendre = false
        commune.enAttente[#commune.enAttente + 1] = m.nom
      end
    end
    -- Un objectif absent du journal d'un membre (quête pas encore chargée, ou pas de quête du tout) compte à 0.
    -- ponytail: sans la quête, un membre compte à 0 ; l'écart (à partager, écartée) dit quoi faire.
    for _, m in ipairs(membres) do
      local q = m.quetes and m.quetes[id]
      if q or not rendue(m, id) then
        for i, c in ipairs(commune.objectifs) do
          if not (q and q.objectifs and q.objectifs[i]) then c.fait = 0 end
        end
      end
    end
  end
  local aFaire, aControler = ns.ecarts(membres, foyer, quetes, ecartees, base, zone)
  return { niveau = niveau, foyer = foyer, pierre = pierre, quetes = quetes, aPart = aPart, aFaire = aFaire,
    aControler = aControler }
end

-- La liste À faire : les écarts, chacun avec le membre visé (celui qui agit) et l'action ; triée par quête.
--   - quête écartée (#21) : la Compagnie ne la fait pas, un membre l'a encore : chez lui, « Abandonner aussi » (par = qui
--     l'a écartée) ; résorbée quand il l'a abandonnée. Elle n'est jamais à partager ni en avance ;
--   - quête à partager : un membre l'a, partageable, d'autres ne l'ont ni en cours, ni rendue : chez lui, « Partager » ;
--     résorbée quand tous l'ont.
--   - quête en avance : un membre l'a rendue pendant qu'un autre l'a encore, pas finie : chez celui-ci, l'écart dit ce
--     qui s'est passé (par = qui l'a rendue, jamais affiché) ; résorbée quand il l'a finie.
--   - foyer différent : un membre lié à une autre auberge que le foyer (sans quête : en tête de liste).
--   - prérequis manquant (#27) : sur la zone de la Compagnie, chez chaque membre qui ne l'a pas fait : la quête
--     débloquée, le prérequis et sa chaîne (ns.chaine), sa zone, le donneur de la première quête, les membres à qui il
--     manque (tous : « toute la Compagnie »), ceux à contrôler ; résorbé quand le membre l'a fait, ou que la quête
--     débloquée ou le prérequis est écarté (la chaîne d'une quête écartée l'est avec elle).
-- Une quête à part (d'avant, #20 : communes = les quêtes de la Compagnie) ne crée aucun écart ; seule une remise vue
-- après l'entrée (rendues, pas renduesAvant) fait une quête en avance.
-- Rend aussi les membres à contrôler (#27) : ceux dont l'état ne couvre pas la zone de la Compagnie (absent depuis le
-- choix, jamais entendu) ; on ne sait pas ce qui leur manque, on ne leur prête rien.
function ns.ecarts(membres, foyer, communes, ecartees, base, zone)
  local t, rendues = {}, {}
  for _, m in ipairs(membres) do
    if foyer and m.auberge and m.auberge ~= foyer then t[#t + 1] = { type = "foyer", membre = m.nom, auberge = foyer } end
    for id in pairs(m.rendues or {}) do rendues[id] = rendues[id] or {}; table.insert(rendues[id], m.nom) end
  end
  for _, m in ipairs(membres) do
    for id, q in pairs(m.quetes or {}) do
      local d = ecartees[id]
      if d and d.ecartee then t[#t + 1] = { type = "ecartee", membre = m.nom, quete = id, par = d.par }
      elseif communes[id] then -- sinon une quête d'avant : aucun écart
        if rendues[id] and not q.finie then t[#t + 1] = { type = "avance", membre = m.nom, quete = id, par = rendues[id] } end
        if q.partageable then
          local manquants = {}
          for _, n in ipairs(membres) do
            if not (n.quetes and n.quetes[id] or rendue(n, id)) then manquants[#manquants + 1] = n.nom end
          end
          if #manquants > 0 then t[#t + 1] = { type = "partager", membre = m.nom, quete = id, manquants = manquants } end
        end
      end
    end
  end
  local aControler, manque, ordre = {}, {}, {}
  for _, m in ipairs(zone and membres or {}) do
    local p = m.prerequis
    if not (p and p.zone == zone) then aControler[#aControler + 1] = m.nom
    else
      for _, x in ipairs(p.manquants) do
        if not (ecartees[x.quete] or ecartees[x.prerequis]) and base[x.prerequis] then
          local cle = x.quete .. ":" .. x.prerequis
          if not manque[cle] then manque[cle] = {}; ordre[#ordre + 1] = x end
          table.insert(manque[cle], m.nom)
        end
      end
    end
  end
  for _, x in ipairs(ordre) do
    local noms = manque[x.quete .. ":" .. x.prerequis]
    local chaine = ns.chaine(base, x.prerequis, zone)
    for _, nom in ipairs(noms) do
      t[#t + 1] = { type = "prerequis", membre = nom, quete = x.quete, prerequis = x.prerequis, chaine = chaine,
        zone = base[x.prerequis].zone, donneur = base[chaine[1]].donneur, manquants = noms, tous = #noms == #membres,
        aControler = aControler }
    end
  end
  table.sort(t, function(a, b)
    if a.quete ~= b.quete then return (a.quete or 0) < (b.quete or 0) end
    if a.type ~= b.type then return a.type < b.type end
    if a.prerequis ~= b.prerequis then return (a.prerequis or 0) < (b.prerequis or 0) end
    return tostring(a.membre) < tostring(b.membre)
  end)
  return t, aControler
end

-- La suite d'une quête (#25) : ses suites dans la base des quêtes (base[id].suites : la suite de QuestieDB et les quêtes
-- qui l'ont en prérequis), puis les leurs, de proche en proche, chacune une fois, dans l'ordre où on les rencontre.
function ns.suite(base, id)
  local file, vues, i = { id }, { [id] = true }, 1
  while i <= #file do
    for _, s in ipairs(base[file[i]] and base[file[i]].suites or {}) do
      if not vues[s] then vues[s] = true; file[#file + 1] = s end
    end
    i = i + 1
  end
  table.remove(file, 1)
  return file
end

-- Un personnage de cette race et de cette classe (raceID, classID du jeu) peut-il prendre la quête q de la base ? (races,
-- classes : listes d'IDs, nil : toutes ; une quête absente de la base : oui, rien n'est deviné.)
local function dans(liste, x)
  if not liste then return true end
  for _, y in ipairs(liste) do if y == x then return true end end
  return false
end
function ns.peutPrendre(q, race, classe) return not q or dans(q.races, race) and dans(q.classes, classe) end

-- Les zones que propose le menu de la zone de la Compagnie (#24), d'après la base des quêtes (celles de la faction) :
-- { { zone = areaID, niveau = niveau d'entrée, ouverte = la Compagnie l'a }, … }, les ouvertes d'abord (de la plus haute
-- à la plus basse), puis les autres (de la plus basse à la plus haute). Le niveau d'entrée : le niveau requis du premier
-- quart des quêtes de la zone (quelques quêtes de niveau 1 n'en font pas une zone de début).
-- ponytail: une zone a au moins MIN_QUETES quêtes (les instances, à quelques quêtes, n'y sont pas) ; une liste des
-- zones viendra si une zone manque.
local MIN_QUETES = 10
function ns.zones(base, niveau)
  local requis, t = {}, {}
  for _, q in pairs(base) do
    if q.zone and q.zone > 0 then -- négative : une catégorie de QuestieDB (classe, métier…), pas une zone
      requis[q.zone] = requis[q.zone] or {}
      table.insert(requis[q.zone], q.niveau_requis or 1)
    end
  end
  for z, r in pairs(requis) do
    if #r >= MIN_QUETES then
      table.sort(r)
      local n = r[math.ceil(#r / 4)]
      t[#t + 1] = { zone = z, niveau = n, ouverte = n <= (niveau or 1) }
    end
  end
  table.sort(t, function(a, b)
    if a.ouverte ~= b.ouverte then return a.ouverte end
    if a.niveau ~= b.niveau then return a.ouverte == (a.niveau > b.niveau) end
    return a.zone < b.zone
  end)
  return t
end

-- Les quêtes écartées pour de bon (#27) : les décisions de la Compagnie (ecartees, { [id] = { ecartee, date, par } }) et
-- ce qu'elles emportent dans la base des quêtes : les suites d'une quête écartée, puis les prérequis qui ne servaient
-- qu'à des quêtes écartées (toutes leurs suites le sont) ; un prérequis qui ouvre une autre quête gardée reste. Une
-- quête qui a sa propre décision (écartée, ou remise) la garde, et une remise arrête les suites. Rend { [id] = la décision qui l'écarte }.
local function prerequisDe(q)
  local t = {}
  for _, p in ipairs(q and q.prerequis or {}) do t[#t + 1] = p end
  for _, p in ipairs(q and q.prerequis_un or {}) do t[#t + 1] = p end
  return t
end
function ns.ecarteesEffectives(ecartees, base)
  ecartees, base = ecartees or {}, base or {}
  local t, racines = {}, {}
  for id, d in pairs(ecartees) do if d.ecartee then t[id] = d; racines[#racines + 1] = id end end
  local function libre(id) return not ecartees[id] and not t[id] end
  local i = 1 -- les suites, de proche en proche, sans passer une quête qui a sa propre décision
  while i <= #racines do
    for _, s in ipairs(base[racines[i]] and base[racines[i]].suites or {}) do
      if libre(s) then t[s] = t[racines[i]]; racines[#racines + 1] = s end
    end
    i = i + 1
  end
  local change = true
  while change do
    change = false
    local ids = {}
    for id in pairs(t) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do
      for _, p in ipairs(prerequisDe(base[id])) do
        local suites = base[p] and base[p].suites
        if libre(p) and suites then
          local toutes = true
          for _, s in ipairs(suites) do toutes = toutes and t[s] ~= nil end
          if toutes then t[p], change = t[id], true end
        end
      end
    end
  end
  return t
end

-- Mes prérequis manquants pour la zone de la Compagnie (#27), chaque membre calcule les siens : pour chaque quête de la
-- zone que je peux prendre (race, classe), pas encore rendue ni écartée, ses prérequis hors de la zone, qui ne sont pas
-- ses amorces et que je n'ai pas rendus (prerequis : tous ; prerequis_un : un seul suffit, rien n'est signalé si l'un
-- est rendu ou dans la zone, sinon le premier). Un prérequis absent de la base (autre faction) ne compte pas : rien
-- n'est deviné. rendue(id) : IsQuestFlaggedCompleted ; ecartees : ns.ecarteesEffectives. Rend { { quete, prerequis }, … }
-- trié. Une chaîne qui reste dans la zone n'est pas signalée : on la fera en avançant ; une quête de la zone qui demande
-- une quête de la zone qui demande une quête d'ailleurs l'est, par celle du milieu.
function ns.prerequisManquants(zone, base, rendue, race, classe, ecartees)
  local t = {}
  for id, q in pairs(base) do
    if q.zone == zone and ns.peutPrendre(q, race, classe) and not rendue(id) and not ecartees[id] then
      local amorce = {}
      for _, a in ipairs(q.amorces or {}) do amorce[a] = true end
      local function dehors(p) return base[p].zone ~= zone and not amorce[p] end
      for _, p in ipairs(q.prerequis or {}) do
        if base[p] and dehors(p) and not rendue(p) then t[#t + 1] = { quete = id, prerequis = p } end
      end
      local premier, couvert = nil, false
      for _, p in ipairs(q.prerequis_un or {}) do
        if base[p] then
          if rendue(p) or not dehors(p) then couvert = true else premier = premier or p end
        end
      end
      if premier and not couvert then t[#t + 1] = { quete = id, prerequis = premier } end
    end
  end
  table.sort(t, function(a, b) return a.quete < b.quete or a.quete == b.quete and a.prerequis < b.prerequis end)
  return t
end

-- La chaîne d'un prérequis manquant (#27) : lui et ceux qu'il demande, de proche en proche, hors de la zone de la
-- Compagnie (prerequis : tous ; prerequis_un : le premier de la base), la première à faire d'abord.
-- ponytail: tirée de la base, pas de ce que le membre a déjà fait de la chaîne ; il le voit en jeu.
function ns.chaine(base, p, zone)
  local t, vues = {}, {}
  local function visiter(id)
    vues[id] = true
    local q = base[id]
    local avant = {}
    for _, a in ipairs(q.prerequis or {}) do avant[#avant + 1] = a end
    for _, a in ipairs(q.prerequis_un or {}) do if base[a] then avant[#avant + 1] = a break end end
    for _, a in ipairs(avant) do
      if base[a] and base[a].zone ~= zone and not vues[a] then visiter(a) end
    end
    t[#t + 1] = id
  end
  if base[p] then visiter(p) end
  return t
end
