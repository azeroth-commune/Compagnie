-- Compagnie, le calcul de la Compagnie : une fonction pure, sans aucun appel à l'API du jeu (vérifié par check.lua).
-- Entrée : la liste des membres, chacun avec son état (dernier état connu pour un absent) :
--   { nom = "Léo", niveau = 10, absent = true,
--     quetes = { [idQuête] = { finie = false, objectifs = { { texte = "Patte de loup", fait = 5, total = 8 }, … } } } }
-- Sortie : { quetes = { [idQuête] = { objectifs = { … }, aRendre = false, enAttente = { "Léo" } } } }
-- Un absent compte comme les autres, avec son dernier état connu : le calcul ne lit donc pas « absent ».
local _, ns = ...

function ns.calculer(membres)
  local quetes = {}
  for _, m in ipairs(membres) do
    for id, q in pairs(m.quetes or {}) do
      local commune = quetes[id]
      if not commune then
        commune = { objectifs = {}, aRendre = true, enAttente = {} }
        quetes[id] = commune
      end
      for i, o in ipairs(q.objectifs) do
        local c = commune.objectifs[i]
        if not c or o.fait < c.fait then commune.objectifs[i] = { texte = o.texte, fait = o.fait, total = o.total } end
      end
      if not q.finie then
        commune.aRendre = false
        commune.enAttente[#commune.enAttente + 1] = m.nom
      end
    end
  end
  return { quetes = quetes }
end
