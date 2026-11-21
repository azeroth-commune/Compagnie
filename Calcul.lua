-- Compagnie, le calcul de la Compagnie : une fonction pure, sans aucun appel à l'API du jeu (vérifié par check.lua).
-- Entrée : la liste des membres, chacun avec son état (dernier état connu pour un absent) :
--   { nom = "Léo", niveau = 10, absent = true,
--     quetes = { [idQuête] = { finie = false, objectifs = { { texte = "Patte de loup", fait = 5, total = 8 }, … } } },
--     rendues = { [idQuête] = true } }
-- Sortie : { niveau = 9, quetes = { [idQuête] = { objectifs = { … }, aRendre = false, enAttente = { "Léo" } } } }
-- Les quêtes de la Compagnie sont celles qu'au moins un membre a en cours. Pour chacune, membre par membre :
--   - en cours : son avancement compte, objectif par objectif (le moins avancé l'emporte) ;
--   - déjà rendue : il ne retient plus la Compagnie ;
--   - ni l'un ni l'autre : il compte à 0 et la Compagnie l'attend (jamais à rendre sans lui).
-- Un absent compte comme les autres, avec son dernier état connu : le calcul ne lit donc pas « absent ».
local _, ns = ...

function ns.calculer(membres)
  local quetes, niveau = {}, nil
  for _, m in ipairs(membres) do
    if not niveau or m.niveau < niveau then niveau = m.niveau end
    for id in pairs(m.quetes or {}) do quetes[id] = { objectifs = {}, aRendre = true, enAttente = {} } end
  end
  for id, commune in pairs(quetes) do
    for _, m in ipairs(membres) do
      local q = m.quetes and m.quetes[id]
      for i, o in ipairs(q and q.objectifs or {}) do
        local c = commune.objectifs[i]
        if not c or o.fait < c.fait then commune.objectifs[i] = { texte = o.texte, fait = o.fait, total = o.total } end
      end
      if not (q and q.finie or m.rendues and m.rendues[id]) then
        commune.aRendre = false
        commune.enAttente[#commune.enAttente + 1] = m.nom
      end
    end
    -- Un objectif absent du journal d'un membre (quête pas encore chargée, ou pas de quête du tout) compte à 0.
    -- ponytail: sans la quête, un membre compte à 0 ; l'écart « quête à partager » (tranche suivante) dira quoi faire.
    for _, m in ipairs(membres) do
      local q = m.quetes and m.quetes[id]
      if q or not (m.rendues and m.rendues[id]) then
        for i, c in ipairs(commune.objectifs) do
          if not (q and q.objectifs and q.objectifs[i]) then c.fait = 0 end
        end
      end
    end
  end
  return { niveau = niveau, quetes = quetes }
end
