# Journal des déploiements — J3 matin

**15 octobre 2026 · Boulaye DOUCOURE et Darry KANYEP**

Les heures sont en **heure de Paris, UTC+02:00**. Une heure de fusion GitHub ne représente pas l’heure de fin du déploiement. Les timestamps des AnalysisRun viennent de l’export Kubernetes.

| Heure | Changement ou contrôle | Résultat | Preuve |
| --- | --- | --- | --- |
| 11:12:42 | [PR #13](https://github.com/Darkbd11/taskflow-gitops/pull/13), commit `8a67c35` : analyse automatique ajoutée | Image maintenue en `2.0.0` ; AnalysisTemplate, ConfigMap et service Canary déployés | [Ressources](j3-matin-05-ressources-analyse-auto.png) |
| Avant la PR #14 | Test k6 de référence sur `2.0.0` | 728 requêtes, 0 % d’erreurs, p95 de 8,32 ms | [Logs](j3-matin-02-charge-2.0.0.txt) |
| 11:26:31 | [PR #14](https://github.com/Darkbd11/taskflow-gitops/pull/14), commit `bfb6e1b` : image `2.1.0` | Révision 6, Canary limité au premier palier | [Analyse en cours](j3-matin-07-analyse-2.1.0-en-cours.png) |
| 11:28:13 | Début de `taskflow-df976ccb5-6-2` | Job k6 sur `taskflow-canary` | [Export](j3-matin-15-analysisruns.yaml) |
| 11:28:44 | k6 termine avec ses seuils dépassés | 30,10 % d’erreurs ; p95 de 313,22 ms | [Logs k6](j3-matin-08-logs-k6-2.1.0.txt) |
| 11:28:50 | Analyse terminée en `Failed`, après 37 s | Échec du contrôle de déploiement | [AnalysisRun](j3-matin-08-analysisrun-2.1.0.txt) |
| Après l’échec | Abandon automatique | Canary à zéro, groupe stable rétabli en `2.0.0` | [Rollout](j3-matin-08-rollout-2.1.0.txt), [événements](j3-matin-15-evenements-final.txt) |
| Après stabilisation | Observation du service | 100 réponses en `2.0.0`, HTTP 200 ; Argo CD `Synced / Degraded` | [Capture](j3-matin-09-service-apres-abort.png) |
| 11:41:43 | [PR #15](https://github.com/Darkbd11/taskflow-gitops/pull/15), commit `197b0f0` : revert vers `2.0.0` | État voulu corrigé dans Git | [PR fusionnée](j3-matin-10-pr-revert-2.1.0.png) |
| À partir de 11:43:23 | Vérification après revert | Rollout `Healthy`, Argo CD `Synced / Healthy`, HTTP 200 | [Capture](j3-matin-11-retour-stable-2.0.0.png) |
| 11:50:09 | [PR #16](https://github.com/Darkbd11/taskflow-gitops/pull/16), commit `d5fe1ec` : image `2.2.0` | Démarrage de la révision 8 | Historique GitHub |
| 11:52:02 | Début de `taskflow-7ddd57d788-8-2` | Nouvelle analyse k6 | [Export](j3-matin-15-analysisruns.yaml) |
| 11:52:39 | Analyse terminée en `Successful`, après 37 s | 725 requêtes, 0 % d’erreurs, p95 de 13,85 ms | [Résumé k6](j3-matin-15-k6-2.2.0-extrait.txt) |
| Après le succès | Progression des paliers sans promotion manuelle | Réplicas de la nouvelle version augmentés | [Événements](j3-matin-15-evenements-final.txt) |
| À partir de 11:55:00 | Contrôle final | `2.2.0` stable à 100 %, quatre pods prêts, Argo CD sain, 100 réponses HTTP 200 | [Capture finale](j3-matin-14-deploiement-2.2.0-final.png) |

Les événements fournis ont des âges relatifs. Le début exact d’exposition au défaut et l’instant précis de la dernière réponse en `2.1.0` ne sont pas mesurés. La durée de 37 secondes correspond à chaque AnalysisRun.

Le [postmortem](postmortem-2.1.0.md) détaille la cause, l’impact observé et les suites proposées.

