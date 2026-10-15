# Postmortem — Déploiement de TaskFlow 2.1.0

**Lab J3 matin — 15 octobre 2026**  
**Binôme : Boulaye DOUCOURE et Darry KANYEP**

## Ce qui s’est passé

Nous avons déployé la version `2.1.0` pour vérifier que notre test de charge pouvait bloquer automatiquement une version défectueuse.

Le déploiement a commencé en Canary, avec un pod sur la nouvelle version et trois pods sur la version stable `2.0.0`. Au palier de 25 %, Argo Rollouts a lancé l’analyse k6 sur le service `taskflow-canary`.

Le test a dépassé les deux seuils que nous avions définis :

- **30,10 % d’erreurs**, pour un seuil inférieur à 2 % ;
- **313,22 ms de p95**, pour un seuil inférieur à 250 ms.

L’analyse est passée en `Failed` et Argo Rollouts a abandonné le déploiement. Nous n’avons pas lancé de commande manuelle d’abandon.

Après le retour sur les pods stables, nous avons fait un revert par PR pour remettre aussi `2.0.0` dans Git. Nous avons ensuite déployé `2.2.0`, qui a réussi le test et atteint 100 %.

## Impact et durée

Le problème concernait l’API TaskFlow, plus précisément les requêtes sur `/tasks` utilisées dans le test.

Au moment de l’analyse, la nouvelle version représentait un pod sur quatre. Le taux de 30,10 % d’erreurs a été mesuré sur cette version seule, via `taskflow-canary`. Nous n’avons pas mesuré le taux global d’erreurs du service principal pendant cette période.

Le palier de 25 % correspond ici à la proportion de pods. Sans routeur de trafic dédié, cela ne garantit pas que chaque série de requêtes soit répartie exactement à 25 % sur le Canary.

L’analyse en échec a duré **37 secondes**, de **11:28:13 à 11:28:50**. Nous n’avons pas relevé précisément le début et la fin de l’exposition au défaut : ces 37 secondes ne représentent donc pas toute la durée de l’incident.

Après l’abandon et la stabilisation, notre contrôle du service principal a donné :

```text
100 version=2.0.0 http=200
```

La version défectueuse n’a pas atteint les paliers suivants.

![Le service répond de nouveau en 2.0.0 après l’abandon](docs/j3-matin-09-service-apres-abort.png)

## Déroulement

Les heures sont en **heure de Paris, UTC+02:00**. Nous avons repris les heures de fusion dans GitHub et les timestamps des AnalysisRun dans Kubernetes.

| Heure | Ce que nous avons fait ou observé |
| --- | --- |
| 11:12:42 | Fusion de la [PR #13](https://github.com/Darkbd11/taskflow-gitops/pull/13) pour ajouter l’analyse automatique. L’image reste en `2.0.0`. |
| Avant la PR #14 | Test de référence sur `2.0.0` : 728 requêtes, aucune erreur et un p95 de 8,32 ms. |
| 11:26:31 | Fusion de la [PR #14](https://github.com/Darkbd11/taskflow-gitops/pull/14) pour passer en `2.1.0`. |
| 11:28:13 | Démarrage de l’analyse `taskflow-df976ccb5-6-2`. |
| 11:28:44 | k6 signale le dépassement des deux seuils. |
| 11:28:50 | L’analyse se termine en `Failed`, après 37 secondes. |
| Après l’échec | Argo Rollouts abandonne la mise à jour, réduit le Canary à zéro et rétablit quatre pods stables. |
| Après stabilisation | Nous obtenons 100 réponses en `2.0.0`, HTTP 200. Argo CD affiche encore `Synced / Degraded`. |
| 11:41:43 | Fusion de la [PR #15](https://github.com/Darkbd11/taskflow-gitops/pull/15) pour remettre `2.0.0` dans Git. |
| À partir de 11:43:23 | Nous vérifions le retour à un Rollout `Healthy` et à un Argo CD `Synced / Healthy`. |
| 11:50:09 | Fusion de la [PR #16](https://github.com/Darkbd11/taskflow-gitops/pull/16) pour déployer `2.2.0`. |
| 11:52:02 | Démarrage de l’analyse `taskflow-7ddd57d788-8-2`. |
| 11:52:39 | L’analyse se termine en `Successful`, après 37 secondes. |
| À partir de 11:55:00 | Nous vérifions que `2.2.0` est stable à 100 %, avec quatre pods prêts et 100 réponses HTTP 200. |

Il s’est écoulé **2 min 19 s entre la fusion de la PR #14 et l’échec de l’analyse**. Ce délai comprend notamment la prise en compte du changement et le démarrage du Canary. Nous ne l’utilisons pas comme durée exacte d’exposition au défaut.

Les événements conservés affichent des âges relatifs. Ils nous permettent de retrouver l’ordre des actions, mais pas de donner une heure absolue précise à chaque événement.

## Pourquoi la version 2.1.0 échouait

Le défaut était prévu dans le scénario du cours.

En regardant le [workflow de publication des images](https://github.com/9m7fjfpv9k-cyber/cicd-fil-rouge/blob/main/.github/workflows/publish-images.yml), nous retrouvons ces paramètres pour `2.1.0` :

```text
FAILURE_RATE=0.3
LATENCY_MS=300
```

Le [Dockerfile](https://github.com/9m7fjfpv9k-cyber/cicd-fil-rouge/blob/main/Dockerfile) transmet ces valeurs à l’environnement de l’application.

Dans [app/main.py](https://github.com/9m7fjfpv9k-cyber/cicd-fil-rouge/blob/main/app/main.py), le middleware `inject_faults` ajoute le délai et peut renvoyer un HTTP 500 sur les routes autres que `/health`.

Cela explique ce que nous avons mesuré sur `/tasks` : environ 300 ms par requête et environ 30 % d’erreurs.

Le Job k6 avait donc bien fonctionné. Il a exécuté 299 requêtes et terminé en erreur parce que les seuils étaient dépassés.

### Pourquoi le pod était quand même Ready

Les probes de readiness et de liveness utilisent `/health`. Cette route est exclue de l’injection de pannes.

Le contrôle de santé pouvait donc passer alors que les requêtes sur `/tasks` étaient lentes et renvoyaient des erreurs. Nous avons ainsi pu avoir un pod `Ready` qui ne rendait pas correctement le service attendu.

Les événements montrent aussi quelques refus de connexion des probes au démarrage de certains pods. C’est un point distinct : pendant l’analyse, le pod Canary était prêt, mais les résultats k6 restaient mauvais.

## Comment le déploiement a été arrêté

Au palier de 25 %, le Rollout attend 20 secondes puis lance l’AnalysisTemplate `robustesse-k6`.

Le Job k6 envoie des requêtes pendant 30 secondes, avec cinq utilisateurs virtuels, vers :

```text
http://taskflow-canary/tasks
```

Nos seuils sont les suivants :

```text
http_req_failed : rate<0.02
http_req_duration : p(95)<250
```

Comme les deux seuils ont été dépassés, k6 a terminé avec un code d’erreur. Le Job a échoué, puis l’AnalysisRun est passé en `Failed`.

Le message du Rollout donne la raison de l’abandon :

```text
Metric "test-de-charge-k6" assessed Failed due to failed (1) > failureLimit (0)
```

Une mesure en échec suffisait donc à arrêter la mise à jour. Nous avons laissé le mécanisme agir sans utiliser de commande manuelle de promotion ou d’abandon.

![L’analyse de 2.1.0 passe en Failed](docs/j3-matin-07-analysisrun-2.1.0-echec.png)

## Les preuves que nous avons gardées

Nous avons conservé les quatre éléments nécessaires pour expliquer l’échec.

| Élément vérifié | Preuve |
| --- | --- |
| Révision et état du déploiement | [Sortie du Rollout](../../docs/j3-matin-08-rollout-2.1.0.txt) : révision 6, `RolloutAborted`, Canary à zéro et version stable `2.0.0`. |
| Résultat de l’analyse | [Détail de l’AnalysisRun](../../docs/j3-matin-08-analysisrun-2.1.0.txt) et [export des analyses](../../docs/j3-matin-15-analysisruns.yaml). |
| Résultats du test de charge | [Logs k6 de 2.1.0](../../docs/j3-matin-08-logs-k6-2.1.0.txt) : 90 échecs sur 299 requêtes et p95 de 313,22 ms. |
| Ordre des actions dans Kubernetes | [Événements conservés](../../docs/j3-matin-15-evenements-final.txt). |

Les captures montrent les statuts. Les fichiers texte permettent de relire les messages, les noms des ressources et les mesures.

## Pourquoi nous avons aussi fait un revert

Après l’abandon, le service répondait de nouveau en `2.0.0`, mais Git demandait encore `2.1.0`. Le retour arrière n’était donc pas terminé du point de vue de la configuration.

Argo CD affichait `Synced / Degraded` : le manifeste correspondait à Git, mais le déploiement demandé avait été abandonné.

Nous avons fait un revert par la PR #15 pour remettre `2.0.0` dans le dépôt.

![La PR de revert est approuvée et fusionnée](docs/j3-matin-10-pr-revert-2.1.0.png)

Après synchronisation, nous avons vérifié :

- le Rollout en `Healthy` ;
- Argo CD en `Synced / Healthy` ;
- le service en `2.0.0`, avec 100 réponses HTTP 200.

![Contrôle du service et du cluster après le revert](docs/j3-matin-11-retour-stable-2.0.0.png)

## Vérification avec la version 2.2.0

Nous avons ensuite proposé `2.2.0` dans la PR #16. Cette version utilise des paramètres de panne à zéro dans le workflow de publication du cours.

Nous avons laissé le même contrôle automatique s’exécuter. Cette fois, les seuils ont été respectés :

```text
725 requêtes
0 % d’erreurs
p95 HTTP : 13,85 ms
```

L’AnalysisRun est passé en `Successful`.

![L’analyse de 2.2.0 réussit](docs/j3-matin-13-analysisrun-2.2.0-succes.png)

Le déploiement a ensuite continué jusqu’à 100 %, sans promotion manuelle. Notre dernier contrôle montre quatre pods prêts en `2.2.0`, un Rollout `Healthy`, Argo CD `Synced / Healthy` et 100 réponses HTTP 200.

![Vérification finale de TaskFlow en 2.2.0](docs/j3-matin-14-deploiement-2.2.0-final.png)

### Résultats des trois tests

| Version | Test effectué | Requêtes | Erreurs | p95 HTTP | Résultat |
| --- | --- | ---: | ---: | ---: | --- |
| 2.0.0 | Référence manuelle sur le service principal | 728 | 0 % | 8,32 ms | Seuils respectés |
| 2.1.0 | Analyse automatique sur le Canary | 299 | 30,10 % | 313,22 ms | Déploiement abandonné |
| 2.2.0 | Analyse automatique sur le Canary | 725 | 0 % | 13,85 ms | Déploiement poursuivi |

Nous avons utilisé cinq utilisateurs virtuels pendant 30 secondes pour chaque test. Le service principal et le service Canary ne ciblaient toutefois pas le même nombre de pods. Ces mesures permettent de vérifier les seuils du lab ; elles ne suffisent pas à comparer précisément la capacité des versions.

Nous avons bien retenu le p95 de `http_req_duration`. La durée d’une itération comprend aussi l’attente du script et ne correspond pas au seuil HTTP de 250 ms.

## Actions réalisées et améliorations proposées

Nous avons préparé les changements et fait relire les PR dans notre binôme. Les trois premières actions sont terminées. Les deux dernières restent des propositions à valider et à répartir entre nous.

| Action | Responsable | Date ou échéance | État |
| --- | --- | --- | --- |
| Ajouter l’analyse k6 au déploiement Canary | Notre binôme | 15/10/2026 | Réalisé, PR #13 |
| Remettre la version stable dans Git | Notre binôme | 15/10/2026 | Réalisé, PR #15 |
| Vérifier le déploiement de 2.2.0 avec les mêmes seuils | Notre binôme | 15/10/2026 | Réalisé, PR #16 |
| Automatiser la sauvegarde des logs et des événements avec leurs timestamps absolus | Notre binôme, répartition à confirmer | 16/10/2026 | Proposition |
| Remplacer `grafana/k6:latest` par une version ou un digest fixe | Notre binôme, répartition à confirmer | 16/10/2026 | Proposition |

## Ce que nous retenons

Le point le plus parlant du lab est qu’un pod peut être `Ready` alors que l’application répond mal sur un parcours utilisateur. Ici, `/health` passait, mais `/tasks` était lent et renvoyait des erreurs.

Le test k6 nous a permis de vérifier autre chose que le simple démarrage du conteneur. Ses résultats ont arrêté la version défectueuse et laissé passer la version saine.

Nous avons aussi mieux compris la différence entre l’abandon du déploiement et le revert : le premier rétablit le service sur la version stable, tandis que le second remet la version souhaitée dans Git.
