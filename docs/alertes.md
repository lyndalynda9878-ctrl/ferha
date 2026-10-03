# Les délais et les alertes

Retour au [README](../README.md).

### L'option de 72 h s'éteint toute seule

Une demande acceptée pose une option de 72 h. Sans acompte à l'échéance,
elle expire et **rend la date** — sans que personne n'appuie sur rien. C'est
`pg_cron` qui porte ce « sans personne » : `expire_options()` passe **toutes les
quinze minutes**, et une seconde tâche purge chaque nuit l'historique
d'exécutions de plus de sept jours. Les deux sont posées par une migration, pas
à la main dans le tableau de bord Supabase : un projet recréé repartirait sans
elles, avec des options qui n'expirent plus et personne pour s'en apercevoir.

**Une journée entière expire d'un bloc.** Elle occupe deux lignes de `bookings`
et n'est qu'une seule réservation : le midi libéré et le soir tenu ferait une
date invendable. Les deux parties sont prévenues — c'est aussi la date du
propriétaire qui vient de repartir à la vente — et chacune **une seule fois**.

Le détail est dans [supabase/README.md](../supabase/README.md).

### La cloche, et l'écran

Une cloche en haut de l'accueil et dans la barre du
tableau de bord propriétaire. **La même cloche**, et pas une par espace : Karim
reçoit ses demandes sur ses salles, mais il peut aussi avoir réservé ailleurs —
deux compteurs qui se partageraient les notifications donneraient deux nombres,
et aucun des deux ne serait le bon.

La pastille ne montre jamais « 0 » : elle apparaît à un, et dit « 99+ » au-delà.
Le nombre vient de la base et porte sur **toutes** les non lues, pas sur les
cinquante lignes affichées — sinon le badge rétrécirait à mesure qu'on remonte
dans l'historique.

L'écran charge la liste à l'ouverture **et** écoute le temps réel. Les deux, pas
l'un ou l'autre : le service Realtime de Supabase démarre à froid quand le
projet a dormi, et une notification déposée pendant ces deux secondes-là ne
serait annoncée à personne.

Toucher une notification fait deux choses, dans cet ordre : elle s'éteint, puis
l'écran s'ouvre — le suivi des réservations pour la famille, le détail de la
demande pour le propriétaire. L'inverse laisserait la pastille allumée le temps
de la transition, et on croirait avoir mal appuyé.

**Aucun texte de notification n'est écrit en dur.** Le titre vient du type, la
ligne de détail du payload — nom de la salle, date, créneau, invités —, et le
payload est rempli par la base au moment où la notification naît. Il est donc
aussi **figé** : une salle renommée demain ne réécrit pas l'annonce d'hier.

### Ce qui manque encore

Le push téléphone (FCM), les e-mails, les rappels J-7 et J-1, l'écran qui
recevra l'invitation à laisser un avis et le bouton WhatsApp ne sont pas
faits. Les deux types `reminder_j7` et `reminder_j1` existent en base et
personne ne les dépose encore ; `review_invitation`, elle, est déjà déposée par
`complete_booking()` et mène au suivi des réservations faute d'écran dédié.

