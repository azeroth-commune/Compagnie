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
-- ecartees : les décisions de la Compagnie (#21), { [idQuête] = { ecartee = true (false : remise), date, par = "Léo" } }.
-- Sortie : { niveau = 9, foyer = "Comté-de-l'Or", pierre = 2400 (secondes avant qu'elle soit prête ; 0 : prête),
--           quetes = { [idQuête] = { objectifs = { … }, aRendre = false, enAttente = { "Léo" }, zone = … } },
--           aPart = { { quete = id, membre = "Léo", objectifs = { … }, aRendre = true, zone = …, ecartee = true } },
--           aFaire = { { type = "partager", membre = "Virgile", quete = id, manquants = { "Léo" } },
--                      { type = "ecartee", membre = "Léo", quete = id, par = "Virgile" },
--                      { type = "avance", membre = "Léo", quete = id, par = { "Virgile" } },
--                      { type = "foyer", membre = "Léo", auberge = "Comté-de-l'Or" } } }
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

function ns.calculer(membres, maintenant, ecartees)
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
  ecartees = ecartees or {}
  local function ecartee(id) return ecartees[id] and ecartees[id].ecartee end
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
  return { niveau = niveau, foyer = foyer, pierre = pierre, quetes = quetes, aPart = aPart,
    aFaire = ns.ecarts(membres, foyer, quetes, ecartees) }
end

-- La liste À faire : les écarts, chacun avec le membre visé (celui qui agit) et l'action ; triée par quête.
--   - quête écartée (#21) : la Compagnie ne la fait pas, un membre l'a encore : chez lui, « Abandonner aussi » (par = qui
--     l'a écartée) ; résorbée quand il l'a abandonnée. Elle n'est jamais à partager ni en avance ;
--   - quête à partager : un membre l'a, partageable, d'autres ne l'ont ni en cours, ni rendue : chez lui, « Partager » ;
--     résorbée quand tous l'ont.
--   - quête en avance : un membre l'a rendue pendant qu'un autre l'a encore, pas finie : chez celui-ci, l'écart dit ce
--     qui s'est passé (par = qui l'a rendue, jamais affiché) ; résorbée quand il l'a finie.
--   - foyer différent : un membre lié à une autre auberge que le foyer (sans quête : en tête de liste).
-- Une quête à part (d'avant, #20 : communes = les quêtes de la Compagnie) ne crée aucun écart ; seule une remise vue
-- après l'entrée (rendues, pas renduesAvant) fait une quête en avance.
function ns.ecarts(membres, foyer, communes, ecartees)
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
  table.sort(t, function(a, b)
    if a.quete ~= b.quete then return (a.quete or 0) < (b.quete or 0) end
    if a.type ~= b.type then return a.type < b.type end
    return tostring(a.membre) < tostring(b.membre)
  end)
  return t
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
