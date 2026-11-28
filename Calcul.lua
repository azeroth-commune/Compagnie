-- Compagnie, le calcul de la Compagnie : une fonction pure, sans aucun appel à l'API du jeu (vérifié par check.lua).
-- Entrée : la liste des membres, chacun avec son état (dernier état connu pour un absent) :
--   { nom = "Léo", niveau = 10, race = 1, classe = 2 (raceID, classID du jeu ; nil : inconnues), absent = true,
--     quetes = { [idQuête] = { finie = false, objectifs = { { texte = "Patte de loup", fait = 5, total = 8,
--       stock = 11 (objet échangeable dans ses sacs, nil sauf au-delà du total) }, … } } },
--     avant = { [idQuête] = true } (ses quêtes d'avant, #20 : dans son journal à son entrée dans la Compagnie),
--     rendues = { [idQuête] = true } (rendues depuis son entrée), renduesAvant = { [idQuête] = true } (avant),
--     auberge = "Comté-de-l'Or", liaison = 1764000000, finRecharge = 1764002400 } (heures serveur ; nil : inconnu, ou
--     pierre prête)
--     (une quête peut porter sa zone : zone = "Forêt d'Elwynn", et partageable = true : seulement dans mon journal, lu
--     en direct, le jeu ne le dit que pour mes quêtes ; personnelle = true : marquée à la main par le membre, #7 ;
--     partageable = false : dans mon journal et dans l'état reçu d'un membre, #6, avec origine = { nom = "Maréchal
--     Dughan" (nil : un objet ramassé), carte = uiMapID, x, y (en %) } : où il l'a prise, PNJ à l'acceptation ou
--     position du ramassage de l'objet qui la lance, nil : pas relevé)
-- maintenant : l'heure serveur (pour la pierre de la Compagnie).
-- ecartees : les décisions de la Compagnie (#21), { [idQuête] = { ecartee = true (false : remise), date, par = "Léo" } } ;
--   une quête écartée emporte sa chaîne (#27, ns.ecarteesEffectives).
-- base : la base des quêtes du socle ({ [id] = { zone, suites, prerequis, … } }, vide : aucune chaîne) ; zone : la zone
--   de la Compagnie (#24, areaID, nil : pas de contrôle des prérequis) ; chaque membre porte alors ses prérequis
--   manquants : prerequis = { zone = la zone qu'ils couvrent, manquants = { { quete, prerequis }, … } } (#27).
-- appris : les niveaux requis appris quand un partage échoue (#7, { [idQuête] = niveau }), en plus de la base.
-- Sortie : { niveau = 9, foyer = "Comté-de-l'Or", pierre = 2400 (secondes avant qu'elle soit prête ; 0 : prête),
--           quetes = { [idQuête] = { objectifs = { … }, aRendre = false, enAttente = { "Léo" }, zone = … } },
--           aPart = { { quete = id, membre = "Léo", objectifs = { … }, aRendre = true, zone = …, ecartee = true,
--                       personnelle = true } },
--           aFaire = { { type = "partager", membre = "Virgile", quete = id, manquants = { "Léo" } },
--                      { type = "ecartee", membre = "Léo", quete = id, par = "Virgile" },
--                      { type = "avance", membre = "Léo", quete = id, par = { "Virgile" } },
--                      { type = "foyer", membre = "Léo", auberge = "Comté-de-l'Or" },
--                      { type = "niveau", membre = "Virgile", quete = id, niveau = 10 },
--                      { type = "prendre", membre = "Léo", quete = id, donneur = { nom, carte, x, y } ou nil,
--                        objet = { id, nom, pnjs, objets, ramasse = { carte, x, y } ou nil } ou nil },
--                      { type = "prerequis", membre = "Léo", quete = id, prerequis = id, chaine, zone, donneur, manquants,
--                        tous, aControler },
--                      { type = "donner", membre = "Virgile", quete = id, texte, nombre = 3, a = "Léo" },
--                      { type = "recevoir", membre = "Léo", quete = id, texte, nombre = 3, de = "Virgile" } },
--           aControler = { "Mira" } }
-- Une quête personnelle (#7) : le jeu interdit à un autre membre de la prendre (classes, races de la base des quêtes ;
-- un membre de race ou de classe inconnue peut : rien n'est deviné), ou un membre qui l'a l'a marquée personnelle ; elle
-- est à part chez chaque membre qui l'a, sans écart.
-- ponytail: une quête de paladin dans une Compagnie de deux paladins et un guerrier est personnelle pour les deux
-- paladins (chacun la sienne, à part) ; un avancement commun à un sous-groupe viendra si on le demande.
-- Les quêtes de la Compagnie sont celles qu'au moins un membre a en cours, sauf une quête écartée (#21), une quête
-- personnelle (#7) et une quête d'avant (#20) pour tous ceux qui l'ont : elle est à part (aPart, chez chaque membre qui l'a, avec son avancement à lui),
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

local function dans(liste, x)
  if not liste then return true end
  for _, y in ipairs(liste) do if y == x then return true end end
  return false
end
local function interdite(q, membres) -- un membre (race et classe connues) ne peut pas prendre la quête q de la base
  for _, n in ipairs(q and membres or {}) do
    if n.classe and not dans(q.classes, n.classe) or n.race and not dans(q.races, n.race) then return true end
  end
  return false
end

function ns.calculer(membres, maintenant, ecartees, base, zone, appris)
  base = base or {}
  local quetes, aPart, niveau, foyer, recent, pierre = {}, {}, nil, nil, 0, 0
  local tenue, prise, perso = {}, {}, {} -- [id] = combien de membres l'ont en cours ; [id] = true : un membre l'a prise
  -- après son entrée ; [id] = true : personnelle (#7)
  for _, m in ipairs(membres) do
    if m.niveau and (not niveau or m.niveau < niveau) then niveau = m.niveau end -- un membre jamais entendu : sans niveau
    if m.auberge and (m.liaison or 0) > recent then foyer, recent = m.auberge, m.liaison end
    if m.finRecharge then pierre = math.max(pierre, m.finRecharge - maintenant) end
    for id, q in pairs(m.quetes or {}) do
      tenue[id] = (tenue[id] or 0) + 1
      if not (m.avant and m.avant[id]) then prise[id] = true end
      if q.personnelle or interdite(base[id], membres) then perso[id] = true end
    end
  end
  ecartees = ns.ecarteesEffectives(ecartees, base) -- avec les chaînes qu'elles emportent (#27)
  local function ecartee(id) return ecartees[id] ~= nil end
  local function commune(id) return not ecartee(id) and not perso[id] and (prise[id] or tenue[id] == #membres) end
  for id in pairs(tenue) do if commune(id) then quetes[id] = { objectifs = {}, aRendre = true, enAttente = {} } end end
  for _, m in ipairs(membres) do
    for id, q in pairs(m.quetes or {}) do
      if not commune(id) then
        aPart[#aPart + 1] = { quete = id, membre = m.nom, objectifs = q.objectifs or {}, aRendre = q.finie == true, zone = q.zone,
          ecartee = ecartee(id), personnelle = perso[id] }
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
  local aFaire, aControler = ns.ecarts(membres, foyer, quetes, ecartees, base, zone, appris)
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
--   - niveau insuffisant (#7) : un membre qui ne l'a ni en cours ni rendue n'a pas le niveau requis (base des quêtes, ou
--     appris quand un partage a échoué : le plus haut des deux) : chez chaque membre qui l'a, « au niveau 10 pour toute
--     la Compagnie », à la place de « Partager » ; résorbé quand ce membre a le niveau (un membre sans niveau : jamais
--     entendu, il ne retient pas).
--   - foyer différent : un membre lié à une autre auberge que le foyer (sans quête : en tête de liste).
--   - quête à prendre soi-même (#6) : un membre l'a, non partageable (partageable = false), d'autres ne l'ont ni en
--     cours ni rendue : chez chacun d'eux, avec l'endroit. Lancée par un objet (base : objet), l'objet, où un membre l'a
--     ramassé (son origine relevée) et d'où il vient d'après la base ; sinon le PNJ : relevé par un membre, sinon le
--     donneur de la base (le PNJ que personne n'a vu) ; ni l'un ni l'autre : sans endroit. Résorbée quand il l'a.
--   - prérequis manquant (#27) : sur la zone de la Compagnie, chez chaque membre qui ne l'a pas fait : la quête
--     débloquée, le prérequis et sa chaîne (ns.chaine), sa zone, le donneur de la première quête, les membres à qui il
--     manque (tous : « toute la Compagnie »), ceux à contrôler ; résorbé quand le membre l'a fait, ou que la quête
--     débloquée ou le prérequis est écarté (la chaîne d'une quête écartée l'est avec elle).
-- Une quête à part (d'avant, #20 : communes = les quêtes de la Compagnie) ne crée aucun écart ; seule une remise vue
-- après l'entrée (rendues, pas renduesAvant) fait une quête en avance.
-- Rend aussi les membres à contrôler (#27) : ceux dont l'état ne couvre pas la zone de la Compagnie (absent depuis le
-- choix, jamais entendu) ; on ne sait pas ce qui leur manque, on ne leur prête rien.
-- Objets à donner : pour un objectif d'objet échangeable (stock : ce que le membre en a dans ses sacs, envoyé seulement
-- au-delà du total), quand la Compagnie en a assez pour que tous finissent, qui donne combien à qui : un « donner » chez
-- celui qui en a de trop, un « recevoir » chez celui à qui il en manque. ont : les membres qui ont la quête (tous ceux
-- qui ne l'ont pas rendue). ponytail: rien quand il n'y en a pas assez pour tous ; un partage partiel viendra si on le demande.
local function aDonner(t, id, ont)
  local n = 0
  for _, x in ipairs(ont) do n = math.max(n, #(x.q.objectifs or {})) end
  for i = 1, n do
    local donneurs, receveurs, surplus, besoin = {}, {}, 0, 0
    for _, x in ipairs(ont) do
      local o = x.q.objectifs and x.q.objectifs[i]
      if not o then besoin = math.huge -- objectif pas encore chargé chez lui : on ne sait pas
      elseif o.fait < o.total then
        receveurs[#receveurs + 1] = { nom = x.nom, n = o.total - o.fait, texte = o.texte }
        besoin = besoin + o.total - o.fait
      elseif (o.stock or 0) > o.total then
        donneurs[#donneurs + 1] = { nom = x.nom, n = o.stock - o.total, texte = o.texte }
        surplus = surplus + o.stock - o.total
      end
    end
    if besoin > 0 and surplus >= besoin then
      local d = 1
      for _, r in ipairs(receveurs) do
        while r.n > 0 do
          local g = donneurs[d]
          local k = math.min(g.n, r.n)
          local texte = g.texte or r.texte
          t[#t + 1] = { type = "donner", membre = g.nom, quete = id, texte = texte, nombre = k, a = r.nom }
          t[#t + 1] = { type = "recevoir", membre = r.nom, quete = id, texte = texte, nombre = k, de = g.nom }
          g.n, r.n = g.n - k, r.n - k
          if g.n == 0 then d = d + 1 end
        end
      end
    end
  end
end

function ns.ecarts(membres, foyer, communes, ecartees, base, zone, appris)
  local t, rendues, aPrendre = {}, {}, {} -- aPrendre : [id] = la première origine relevée, ou false
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
        local requis = math.max(base[id] and base[id].niveau_requis or 0, appris and appris[id] or 0)
        local manquants, bas = {}, false
        for _, n in ipairs(membres) do
          if not (n.quetes and n.quetes[id] or rendue(n, id)) then
            manquants[#manquants + 1] = n.nom
            bas = bas or (n.niveau or requis) < requis
          end
        end
        if bas then t[#t + 1] = { type = "niveau", membre = m.nom, quete = id, niveau = requis }
        elseif q.partageable and #manquants > 0 then
          t[#t + 1] = { type = "partager", membre = m.nom, quete = id, manquants = manquants }
        elseif q.partageable == false and #manquants > 0 then aPrendre[id] = aPrendre[id] or q.origine or false
        end
      end
    end
  end
  for id, r in pairs(aPrendre) do
    local b = base[id] or {}
    local o = b.origine or {}
    local objet = b.objet and { id = b.objet, nom = o.nom, pnjs = o.pnjs, objets = o.objets, ramasse = r and r.carte and r or nil }
    local donneur = not objet and (r and r.nom and r or b.donneur) or nil
    for _, n in ipairs(membres) do
      if not (n.quetes and n.quetes[id] or rendue(n, id)) then
        t[#t + 1] = { type = "prendre", membre = n.nom, quete = id, donneur = donneur, objet = objet }
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
  for id in pairs(communes) do
    local ont, tous = {}, true
    for _, m in ipairs(membres) do
      local q = m.quetes and m.quetes[id]
      if q then ont[#ont + 1] = { nom = m.nom, q = q } elseif not rendue(m, id) then tous = false end
    end
    if tous then aDonner(t, id, ont) end
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

-- Les quêtes de l'arbre des chaînes d'une zone (#34) : celles de la zone, et le prérequis hors de la zone qui ouvre l'une
-- d'elles (le début hors zone d'une chaîne ; pas une amorce, qui ne relie pas). Chaque membre envoie celles qu'il a
-- rendues (Etats.lua, renduesZone). Rend { [id] = true }.
local function amorce(base, id, p) return dans(base[id].amorces or {}, p) end
function ns.quetesDeLaZone(base, zone)
  local t = {}
  for id, q in pairs(base) do
    if q.zone == zone then
      t[id] = true
      for _, p in ipairs(prerequisDe(q)) do if base[p] and not amorce(base, id, p) then t[p] = true end end
    end
  end
  return t
end

-- L'arbre des chaînes (#33, #34) : les quêtes de la zone de la Compagnie, une bande par chaîne, pour l'Arbre du socle
-- (AzerothCommune.PlacerArbre : cases, liens, bandes). membres, ecartees (les décisions), base, zone : comme ns.calculer
-- (un absent compte avec son dernier état connu ; chaque membre porte ses quêtes rendues de la zone, renduesZone =
-- { zone, quetes }) ; deplies : { [bande] = true }, les chaînes repliées que j'ai dépliées (local, jamais envoyé).
-- Chaîne : les quêtes reliées par leurs prérequis (tous, ou « un seul parmi plusieurs ») et leurs suites, d'après la
-- base ; une amorce ne relie pas. Une quête sans lien : quête seule, dans la dernière bande. Une quête qu'aucun membre ne
-- peut prendre (races, classes ; une race ou une classe inconnue peut : rien n'est deviné) n'y est pas ; seuls les
-- membres qui peuvent la prendre comptent pour son état. Le début hors zone d'une chaîne : une seule case, le prérequis
-- hors de la zone qui ouvre une quête de la zone (horsZone = sa zone), pas la chaîne étrangère.
-- États d'un membre, du plus avancé au moins avancé : faite (rendue), aRendre, enCours, disponible (les prérequis faits,
-- le niveau), verrouillee (un prérequis manque ; un début hors zone pas fait l'est toujours : sa chaîne étrangère n'est pas
-- connue), niveau. Le membre le moins avancé l'emporte ; ecartee l'emporte sur tout ; une quête qu'un membre a dans son
-- journal est en cours pour celui qui pourrait la prendre (l'avancement commun le compte à 0). Un membre dont l'état ne
-- couvre pas la zone est à contrôler : sans la quête dans son journal, ni rendue connue, ni niveau trop bas, il ne compte
-- pas (on ne lui prête rien). Inégale : les membres diffèrent (faite, prise ou rien).
-- Repli : une chaîne dont toutes les quêtes sont faites ou écartées tient en une case (key « C » .. bande, repliee, n =
-- ses quêtes de la zone, quete = sa première, etat faite, ou ecartee si toutes le sont), sauf dépliée (ses cases :
-- repliable).
-- Rend { cases = { { key = "Q" .. id (texte : l'Arbre trie les clés avec ses relais « R… »), band, index (rang d'une
--   racine), quete = id, niveau, horsZone, etat, objectifs (avancement commun, ns.calculer), requis, inegale = { faites,
--   prises } (noms), bloque = { { membre, niveau } ou { membre, prerequis = { id… } } }, repliee, n, repliable } },
--   liens = { { from, to, hidden } }, bandes = { { key, seules, personnelle = nom du seul membre qui peut la prendre,
--   niveau, premiere, repliee } }, aControler = { noms } } ; bandes rangées par niveau de leur première quête (puis son
--   id : toujours le même ordre), les seules à la fin.
local RANG = { niveau = 1, verrouillee = 2, disponible = 3, enCours = 4, aRendre = 5, faite = 6 }
local NOM_RANG = {}
for k, v in pairs(RANG) do NOM_RANG[v] = k end
local PAR_RANGEE = 5 -- ponytail: les quêtes seules, en rangées de 5 (liens cachés) plutôt qu'en une colonne interminable
local function peut(q, m) return (not m.race or dans(q.races, m.race)) and (not m.classe or dans(q.classes, m.classe)) end
function ns.arbreDesChaines(membres, ecartees, base, zone, deplies)
  deplies = deplies or {}
  local calc = ns.calculer(membres, 0, ecartees, base, zone)
  local eff = ns.ecarteesEffectives(ecartees, base)
  local function couvre(m) return m.renduesZone and m.renduesZone.zone == zone end
  local function faite(m, id) return rendue(m, id) or couvre(m) and m.renduesZone.quetes[id] end
  local aControler = {}
  for _, m in ipairs(membres) do if not couvre(m) then aControler[#aControler + 1] = m.nom end end
  local function preneurs(id)
    local t = {}
    for _, m in ipairs(membres) do if peut(base[id], m) then t[#t + 1] = m end end
    return #t > 0 and t or nil
  end
  local cases, parId, liens, vus = {}, {}, {}, {}
  local function case(id, hors)
    if not parId[id] then
      local q = base[id]
      parId[id] = { key = (hors and "H" or "Q") .. id, quete = id, niveau = q.niveau or 0, horsZone = hors and q.zone or nil,
        preneurs = preneurs(id) }
      cases[#cases + 1] = parId[id]
    end
    return parId[id]
  end
  local function lier(a, b)
    if vus[a.key .. ">" .. b.key] then return end
    vus[a.key .. ">" .. b.key] = true
    liens[#liens + 1] = { from = a, to = b }
  end
  local ids = {}
  for id, q in pairs(base) do if q.zone == zone and preneurs(id) then ids[#ids + 1] = id end end
  table.sort(ids)
  for _, id in ipairs(ids) do case(id) end
  for _, id in ipairs(ids) do
    for _, p in ipairs(prerequisDe(base[id])) do
      local q = base[p]
      if q and not amorce(base, id, p) and preneurs(p) then lier(case(p, q.zone ~= zone), parId[id]) end
    end
    for _, s in ipairs(base[id].suites or {}) do
      if parId[s] and not parId[s].horsZone and not amorce(base, s, id) then lier(parId[id], parId[s]) end
    end
  end
  -- États : chaque membre qui peut la prendre ; le moins avancé l'emporte.
  local function manque(m, id) -- ses prérequis que m n'a pas faits (« un seul parmi plusieurs » : tous, si aucun)
    local q, t, un, ok = base[id], {}, {}, false
    for _, p in ipairs(q.prerequis or {}) do if base[p] and not amorce(base, id, p) and not faite(m, p) then t[#t + 1] = p end end
    for _, p in ipairs(q.prerequis_un or {}) do
      if base[p] and not amorce(base, id, p) then if faite(m, p) then ok = true else un[#un + 1] = p end end
    end
    if not ok then for _, p in ipairs(un) do t[#t + 1] = p end end
    return t
  end
  for _, c in ipairs(cases) do
    local id, rangs, tenue = c.quete, {}, false
    local requis = base[id].niveau_requis or 0
    local faites, prises, rien, bloque = {}, {}, {}, {}
    for _, m in ipairs(c.preneurs) do
      local q, r = m.quetes and m.quetes[id], nil
      if q then r, tenue = q.finie and RANG.aRendre or RANG.enCours, true; prises[#prises + 1] = m.nom
      elseif faite(m, id) then r = RANG.faite; faites[#faites + 1] = m.nom
      elseif m.niveau and m.niveau < requis then r = RANG.niveau; bloque[#bloque + 1] = { membre = m.nom, niveau = requis }
      elseif couvre(m) then
        local t = not c.horsZone and manque(m, id) or {}
        r = (c.horsZone or #t > 0) and RANG.verrouillee or RANG.disponible
        if #t > 0 then bloque[#bloque + 1] = { membre = m.nom, prerequis = t } end
      else r = false end -- à contrôler, rien de connu : seulement compté à 0 quand un autre l'a prise
      if r ~= nil then rangs[#rangs + 1] = r end
      if r and r < RANG.enCours then rien[#rien + 1] = m.nom end
    end
    local rang = 99
    for _, r in ipairs(rangs) do
      if tenue and (r == false or r == RANG.disponible) then r = RANG.enCours end
      if r then rang = math.min(rang, r) end
    end
    c.etat = eff[id] and "ecartee" or NOM_RANG[rang] or "verrouillee" -- ponytail: personne de connu (tous à contrôler) : terne
    c.requis = c.etat == "niveau" and requis or nil
    c.objectifs = (c.etat == "enCours" or c.etat == "aRendre") and calc.quetes[id] and calc.quetes[id].objectifs or nil
    local sortes = (#faites > 0 and 1 or 0) + (#prises > 0 and 1 or 0) + (#rien > 0 and 1 or 0)
    c.inegale = sortes > 1 and { faites = faites, prises = prises } or nil
    c.bloque = #bloque > 0 and bloque or nil
  end
  -- Les chaînes : les composantes reliées (union de proche en proche).
  local chef = {}
  local function racine(c) while chef[c] ~= c do c = chef[c] end return c end
  for _, c in ipairs(cases) do chef[c] = c end
  for _, l in ipairs(liens) do chef[racine(l.from)] = racine(l.to) end
  local avant = function(a, b) if a.niveau ~= b.niveau then return a.niveau < b.niveau end return a.quete < b.quete end
  local parChaine, bandes, seules, aParent, relie = {}, {}, {}, {}, {}
  for _, l in ipairs(liens) do aParent[l.to], relie[l.to], relie[l.from] = true, true, true end
  for _, c in ipairs(cases) do
    if not relie[c] then seules[#seules + 1] = c
    else
      local r = racine(c)
      parChaine[r] = parChaine[r] or {}
      table.insert(parChaine[r], c)
    end
  end
  for _, membresDe in pairs(parChaine) do
    local premiere, qui, n, finie, toutEcartee = nil, {}, 0, true, true
    for _, c in ipairs(membresDe) do
      if not c.horsZone then
        n = n + 1
        if not premiere or avant(c, premiere) then premiere = c end
      end
      for _, m in ipairs(c.preneurs) do qui[m.nom] = true end
      finie = finie and (c.etat == "faite" or c.etat == "ecartee")
      toutEcartee = toutEcartee and c.etat == "ecartee"
    end
    local seul, key = next(qui), "B" .. premiere.quete
    local b = { key = key, niveau = premiere.niveau, premiere = premiere.quete, cases = membresDe,
      personnelle = next(qui, seul) == nil and #membres > 1 and seul or nil, repliee = finie and not deplies[key] }
    if b.repliee then
      b.cases = { { key = "C" .. key, quete = premiere.quete, niveau = premiere.niveau, repliee = true, n = n,
        etat = toutEcartee and "ecartee" or "faite" } }
      for _, c in ipairs(membresDe) do c.plie = true end
    elseif finie then for _, c in ipairs(membresDe) do c.repliable = true end end
    bandes[#bandes + 1] = b
  end
  table.sort(bandes, function(a, b) if a.niveau ~= b.niveau then return a.niveau < b.niveau end return a.premiere < b.premiere end)
  table.sort(seules, avant)
  if #seules > 0 then bandes[#bandes + 1] = { key = "seules", seules = true, cases = seules } end
  local visibles, liensVisibles = {}, {}
  for _, l in ipairs(liens) do if not l.from.plie then liensVisibles[#liensVisibles + 1] = l end end
  for _, b in ipairs(bandes) do
    local racines = {}
    for _, c in ipairs(b.cases) do
      c.band, c.preneurs, visibles[#visibles + 1] = b.key, nil, c
      if not aParent[c] then racines[#racines + 1] = c end
    end
    table.sort(racines, avant)
    for i, c in ipairs(racines) do
      if b.seules and (i - 1) % PAR_RANGEE ~= 0 then liensVisibles[#liensVisibles + 1] = { from = racines[i - 1], to = c, hidden = true }
      else c.index = i end
    end
    b.cases = nil
  end
  return { cases = visibles, liens = liensVisibles, bandes = bandes, aControler = aControler }
end
