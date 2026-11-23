# Compagnie

Add-on de quêtes en groupe : une Compagnie fait toute l'aventure ensemble, l'add-on garde les journaux de quêtes alignés. Repo `azeroth-commune/Compagnie` (public depuis le 23/11, publié sur CurseForge). Espace de travail parent : `../` (outils, recherche, captures — pas dans ce repo).
Déploiement : lien symbolique depuis le dossier AddOns du jeu, `/reload` suffit. Requiert le socle Azeroth Commune (ADR 0002).
Vérifier : `luajit Compagnie/check.lua` depuis le dossier des add-ons (calcul, membres et états, purs : aucune API du jeu),
puis `tools/sim.sh test Compagnie` dans l'atelier (`tests/`, jamais dans la TOC).

## Agent skills

### Issue tracker

GitHub Issues de `azeroth-commune/Compagnie`, toujours avec `-R azeroth-commune/Compagnie` ; PR externes : non. See `docs/agents/issue-tracker.md`.

### Triage labels

Labels par défaut (needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix) + `prd`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context : `CONTEXT.md` + `docs/adr/` à la racine, créés au besoin. See `docs/agents/domain.md`.
