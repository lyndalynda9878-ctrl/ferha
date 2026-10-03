# Les gardiens et le décor de démonstration

Retour au [README](../README.md).

## Les gardiens

Trois choses s'éteignent toutes seules dans ce projet, chacune pour une raison
différente. Trois gardiens les tiennent éveillées.

| Gardien | Rythme | Ce qu'il garde |
|---|---|---|
| `maintien-supabase.yml` (GitHub Actions) | toutes les 48 h | le projet Supabase, qu'une semaine sans activité met en pause |
| `ferha-reveil-empreintes` (pg_cron) | toutes les 5 min | le service d'empreintes sur Render, qui s'endort |
| `ferha-menage-du-decor` (pg_cron) | toutes les heures | le décor de démonstration, qu'un visiteur défait |

Le premier ne peut pas être un `pg_cron` : **un `pg_cron` ne tourne pas dans un
projet en pause**, il ne peut donc pas l'en sortir. Le réveil doit venir de
dehors. À l'inverse, les 5 minutes du second feraient plus de 8 000 exécutions
d'Actions par mois pour un simple réveil, alors qu'un `pg_cron` tourne dans la
base et ne se paie nulle part.

**Le premier gardien a besoin d'un clic après deux mois de silence.** Sur un
dépôt public, GitHub désactive les workflows planifiés d'un dépôt resté 60 jours
sans commit. `maintien-supabase.yml` s'arrêterait alors, et le projet Supabase
se mettrait en pause une semaine plus tard. GitHub prévient par e-mail : il
suffit de cliquer sur « réactiver » dans l'onglet Actions. Un commit, n'importe
lequel, remet aussi le compteur à zéro.

**Un voyant vert au-dessus d'un service mort est le défaut qu'on a rencontré
deux fois ici.** Une tâche qui dépose une requête vers une adresse morte est
enregistrée « succeeded ». Un ping HTTP réussit contre une page de maintenance.
Les deux requêtes ci-dessous ne disent pas que les gardiens se sont *exécutés* :
elles disent ce que les services ont *répondu*.

```sql
select * from public.etat_du_gardien;   -- le code HTTP et le corps rendus par le service
select * from public.etat_du_decor;     -- ce qui est sale dans la démonstration, maintenant
```

`etat_du_gardien` garde la vraie réponse — code et corps — parce que
`cron.job_run_details` ne dit que si la tâche a tourné. Le corps rendu contient
le nom du modèle et sa dimension : c'est la preuve que le service qui a répondu
est bien celui qu'on croit.

Le chiffre qui résume le travail : **le pire cas d'attente est passé de 62
secondes à 2 secondes**. 62 s, c'était le premier appel après deux heures de
silence, mesuré. 2 s, c'est la borne au-delà de laquelle l'assistant cesse
d'attendre et répond sans vecteur — et comme le gardien frappe toutes les 5
minutes, le service est chaud et répond en 85 à 573 ms.

## Le décor de démonstration

Les visiteurs entrent en un tap, comme Amina ou comme Karim. Tout ce qu'ils font
est donc fait **au nom des comptes de démonstration**, et reste après eux — y
compris ce qu'ils *défont*. Un visiteur entré comme Karim qui refuse une demande
ne crée rien : il vide la file des demandes du propriétaire. Au bout de cinq visiteurs, la
meilleure page du projet ne montre plus rien.

Le ménage distingue donc **le décor** de ce qui est arrivé après, par les
préfixes d'identifiant que les seeds posent exprès : `b0000000-` pour une
réservation du décor, `5a11e000-` pour une salle, `d0000000-` pour une personne.
Une réservation créée depuis l'application passe par `request_booking()`, donc
par un identifiant tiré au sort : elle ne peut pas porter le préfixe. Le critère
ne regarde jamais *qui* a réservé — un visiteur **est** Amina.

**Ce qui se remet en place tout seul :** les réservations du décor et leur état,
les avis, les dates bloquées, les notifications, et les personnes — nom, adresse,
langue, et le rôle de propriétaire. Une empreinte, prise au sortir du seed,
décrit l'état juste ; le ménage y ramène la base.

**Ce qu'un visiteur ne peut même pas défaire :** le nom, l'adresse et le mot de
passe des deux comptes. Depuis le 3 octobre 2026, des déclencheurs les figent
(migrations 040 et 041), une tâche horaire remet `demo1234` s'il avait bougé
(042), et l'inscription MFA est fermée dans le tableau de bord. Voir
[`supabase/README.md`](../supabase/README.md#ce-quun-visiteur-ne-peut-pas-leur-faire).

**Ce qui ne se remet pas :** une salle inscrite par un visiteur. Elle porte un
identifiant aléatoire et reste en `pending`, invisible. La vue `etat_du_decor`
la compte, et `seed/002_reset_demo.sql` l'efface en la nommant — mais rien ne le
fait à l'heure.

**L'ordre de restauration est un garde-fou, pas une préférence.** Les
réservations de visiteurs partent d'abord, sinon l'une d'elles, confirmée sur un
créneau du décor, ferait échouer la réinsertion sur l'index d'unicité. Et les
saisies d'un profil se remettent avant son rôle, parce que le déclencheur
`updated_at` rajeunit la ligne à chaque écriture : dans l'autre sens, la
condition de délai ne serait plus jamais vraie et le nom ne reviendrait jamais.

Deux horloges, enfin. Rien n'est touché avant **deux heures** — un visiteur qui
teste dix minutes garde ce qu'il vient de faire sous les yeux. Sauf le rôle de
propriétaire, qui se remet **sans délai** : l'application n'écrit jamais ce
champ, il n'y a donc aucune saisie en cours à protéger, et tant qu'il est faux
« Entrer comme Amina (cliente) » ouvre l'espace propriétaire à tout le monde.

Le détail est dans [`supabase/README.md`](../supabase/README.md), et le banc
d'essai dans `supabase/tests/018_le_decor_se_remet_en_place.sql`.

