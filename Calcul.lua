-- Compagnie, le calcul de la Compagnie : une fonction pure, sans aucun appel à l'API du jeu (vérifié par check.lua).
-- Entrée : la liste des membres, chacun avec son état (dernier état connu pour un absent) :
--   { nom = "Léo", niveau = 10, absent = true,
--     quetes = { [idQuête] = { finie = false, objectifs = { { texte = "Patte de loup", fait = 5, total = 8 }, … } } },
--     rendues = { [idQuête] = true }, abandonnees = { [idQuête] = true } }
--     (une quête peut porter sa zone : zone = "Forêt d'Elwynn", et partageable = true : seulement dans mon journal, lu
--     en direct, le jeu ne le dit que pour mes quêtes)
-- Sortie : { niveau = 9, quetes = { [idQuête] = { objectifs = { … }, aRendre = false, enAttente = { "Léo" }, zone = … } },
--           aFaire = { { type = "partager", membre = "Virgile", quete = id, manquants = { "Léo" } },
--                      { type = "abandonnee", membre = "Léo", quete = id, par = { "Virgile" } },
--                      { type = "avance", membre = "Léo", quete = id, par = { "Virgile" } } } }
-- Les quêtes de la Compagnie sont celles qu'au moins un membre a en cours. Pour chacune, membre par membre :
--   - en cours : son avancement compte, objectif par objectif (le moins avancé l'emporte) ;
--   - déjà rendue : il ne retient plus la Compagnie ;
--   - ni l'un ni l'autre : il compte à 0 et la Compagnie l'attend (jamais à rendre sans lui).
-- Le texte d'un objectif (affichage seulement) est pris chez le membre qui l'a, quel que soit son avancement.
-- Un absent compte comme les autres, avec son dernier état connu : le calcul ne lit donc pas « absent ».
local _, ns = ...

function ns.calculer(membres)
  local quetes, niveau = {}, nil
  for _, m in ipairs(membres) do
    if m.niveau and (not niveau or m.niveau < niveau) then niveau = m.niveau end -- un membre jamais entendu : sans niveau
    for id in pairs(m.quetes or {}) do quetes[id] = { objectifs = {}, aRendre = true, enAttente = {} } end
  end
  for id, commune in pairs(quetes) do
    for _, m in ipairs(membres) do
      local q = m.quetes and m.quetes[id]
      for i, o in ipairs(q and q.objectifs or {}) do
        local c = commune.objectifs[i]
        if not c or o.fait < c.fait then commune.objectifs[i] = { texte = o.texte or c and c.texte, fait = o.fait, total = o.total }
        elseif not c.texte then c.texte = o.texte end -- le texte ne vient que de mon journal (Etats.lua) : pris chez qui l'a
      end
      commune.zone = commune.zone or q and q.zone -- la zone (affichage seulement) : prise chez qui l'a
      if not (q and q.finie or m.rendues and m.rendues[id]) then
        commune.aRendre = false
        commune.enAttente[#commune.enAttente + 1] = m.nom
      end
    end
    -- Un objectif absent du journal d'un membre (quête pas encore chargée, ou pas de quête du tout) compte à 0.
    -- ponytail: sans la quête, un membre compte à 0 ; l'écart (à partager, abandonnée) dit quoi faire.
    for _, m in ipairs(membres) do
      local q = m.quetes and m.quetes[id]
      if q or not (m.rendues and m.rendues[id]) then
        for i, c in ipairs(commune.objectifs) do
          if not (q and q.objectifs and q.objectifs[i]) then c.fait = 0 end
        end
      end
    end
  end
  return { niveau = niveau, quetes = quetes, aFaire = ns.ecarts(membres) }
end

-- La liste À faire : les écarts, chacun avec le membre visé (celui qui agit) et l'action ; triée par quête.
--   - quête abandonnée : un membre l'a abandonnée (« la Compagnie ne fait pas celle-là »), un autre l'a encore : chez
--     celui-ci, « Abandonner aussi » ; résorbée quand plus personne ne l'a ;
--   - quête à partager : un membre l'a, partageable, d'autres ne l'ont ni en cours, ni rendue : chez lui, « Partager » ;
--     résorbée quand tous l'ont. Une quête abandonnée par un membre n'est jamais à partager.
--   - quête en avance : un membre l'a rendue pendant qu'un autre l'a encore, pas finie : chez celui-ci, l'écart dit ce
--     qui s'est passé (par = qui l'a rendue, jamais affiché) ; résorbée quand il l'a finie.
function ns.ecarts(membres)
  local t, abandons, rendues = {}, {}, {}
  for _, m in ipairs(membres) do
    for id in pairs(m.abandonnees or {}) do abandons[id] = abandons[id] or {}; table.insert(abandons[id], m.nom) end
    for id in pairs(m.rendues or {}) do rendues[id] = rendues[id] or {}; table.insert(rendues[id], m.nom) end
  end
  for _, m in ipairs(membres) do
    for id, q in pairs(m.quetes or {}) do
      if rendues[id] and not q.finie then t[#t + 1] = { type = "avance", membre = m.nom, quete = id, par = rendues[id] } end
      local par = {}
      for _, nom in ipairs(abandons[id] or {}) do if nom ~= m.nom then par[#par + 1] = nom end end
      if #par > 0 then t[#t + 1] = { type = "abandonnee", membre = m.nom, quete = id, par = par }
      elseif q.partageable and not abandons[id] then
        local manquants = {}
        for _, n in ipairs(membres) do
          if not (n.quetes and n.quetes[id] or n.rendues and n.rendues[id]) then manquants[#manquants + 1] = n.nom end
        end
        if #manquants > 0 then t[#t + 1] = { type = "partager", membre = m.nom, quete = id, manquants = manquants } end
      end
    end
  end
  table.sort(t, function(a, b)
    if a.quete ~= b.quete then return a.quete < b.quete end
    if a.type ~= b.type then return a.type < b.type end
    return tostring(a.membre) < tostring(b.membre)
  end)
  return t
end
