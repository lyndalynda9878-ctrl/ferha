# Les 34 questions de référence — assistant Ferha

Ces questions servent à juger l'agent au J20. Elles s'appuient sur les
15 salles de démonstration. Deux salles ne sont **pas** publiées —
Espace Nour El Houda (Birtouta) et Salle El Wiam (El Eulma) : l'agent ne
doit **jamais** les proposer.

Pour chaque question : ce qu'une bonne réponse doit contenir.

**En cas de désaccord entre ce document et la base, la base tranche.** Les
questions 4, 6, 7, 11 et 28 ont été corrigées le J21 dans ce sens : leurs
*Attendu* étaient plus étroits que les données, et l'agent était accusé d'un
défaut qui était celui du barème. Un barème faux est pire qu'un barème absent :
il fait corriger du code qui avait raison.

---

## A. En français (1 à 10)

**1.** Je cherche une salle à Oran pour 300 invités, le 14 août 2027 au soir.
*Attendu :* Résidence Les Andalouses seule ; El Bahia est indisponible ce soir-là, date bloquée par le propriétaire — la proposer serait une faute. Jamais Salle Ennour (180 places).

**2.** Quelle est la salle la moins chère de Blida ?
*Attendu :* Salle Ibn Khaldoun, Ouled Yaïch, 150 couverts.

**3.** Une salle à Alger pour un mariage de 650 personnes.
*Attendu :* Palais Dar El Feth (700) uniquement. Ryad El Djazaïr (500) est trop petite.

**4.** Je veux une salle avec un espace femmes séparé.
*Attendu :* toute salle publiée portant `espace_femmes` — elles sont huit. Le document nommait Complexe Chréa seul ; c'était lui qui se trompait, pas l'agent.

**5.** Y a-t-il une salle à Sétif pour 600 personnes ?
*Attendu :* Palais El Amir. Ne jamais proposer Salle El Wiam, qui n'est pas publiée.

**6.** Une salle à Constantine avec un parking fermé.
*Attendu :* toute salle publiée de Constantine ayant du parking — Bab El Kantara (75), Les Ponts (60), Rhumel (28). Le « parking fermé » n'existe pas au référentiel des équipements : la base ne connaît qu'un nombre de places, et l'agent ne peut pas distinguer ce qu'elle ne stocke pas.

**7.** Je veux amener mon propre traiteur. Quelles salles l'acceptent ?
*Attendu :* les quatre salles portant `traiteur_libre` — Salle Ennour (Oran), Salle Rhumel (Constantine), Salle Ibn Khaldoun (Blida), Complexe Chréa (Blida). Le document n'en citait que deux ; la base en donne quatre.

**8.** Une salle à Oran pour 800 invités.
*Attendu :* aucune salle ne convient. L'agent doit le dire, sans en inventer une.

**9.** Combien coûte Salle El Bahia un samedi soir en août ?
*Attendu :* le prix calculé par la base, majorations comprises. Jamais un prix inventé.
« Samedi » est un critère : la date retenue doit tomber un samedi, et être à venir. Un prix donné pour un dimanche est un mauvais prix, la majoration n'étant pas la même.

**10.** Parle-moi de la salle Zoubida à Tlemcen.
*Attendu :* cette salle n'existe pas. L'agent doit le dire clairement.

---

## B. En darja (11 à 20)

*À relire et corriger avec tes mots — c'est ta partie.*

**11.** راني نقلب على قاعة أفراح في وهران لـ 300 واحد
*Attendu :* Les Andalouses ET El Bahia. Ce n'est PAS la réponse de la question 1 : la version darja ne porte aucune date, et c'est la date du 14 août 2027 qui écartait El Bahia là-bas. Sans date, rien ne l'écarte ici.

**12.** شحال تسوى قاعة في سطيف نهار السبت؟
*Attendu :* les salles de Sétif publiées, avec le prix venant de la base.

**13.** كاين قاعة رخيصة في البليدة؟
*Attendu :* Salle Ibn Khaldoun.

**14.** نحتاج قاعة فيها بلاصة للطوموبيلات بزاف
*Attendu :* Palais Dar El Feth (150 places) ou Palais El Amir (110).

**15.** واش كاين قاعة في قسنطينة للعرس؟
*Attendu :* Les Ponts, Bab El Kantara, Rhumel.

**16.** قاعة صغيرة لعقيقة، 150 واحد
*Attendu :* Salle Ibn Khaldoun (150) ou Salle Ennour (180).

**17.** نحتاج قاعة فيها ديجي وسونو
*Attendu :* toute salle publiée disposant de DJ et sono. La nuance « compris dans le prix » n'est pas dans l'index sémantique, et le prix en est exclu par construction : l'agent ne peut pas la connaître.

**18.** كاين شي قاعة قريبة من البحر في وهران؟
*Attendu :* Résidence Les Andalouses, Aïn El Turck.

**19.** واش راه الطقس غدوة؟
*Attendu :* hors sujet. L'agent doit dire qu'il ne s'occupe que des salles.

**20.** نحوس على قاعة في تيزي وزو
*Attendu :* aucune salle dans cette wilaya. Le dire, sans en inventer.

---

## C. Mélangé, franco-arabe (21 à 30)

**21.** salut, je cherche une salle f wahran pour 300 personne le 14 aout, budget max 250 000
*Attendu :* Les Andalouses et El Bahia si le prix calculé tient dans le budget. Sinon le dire.

**22.** wach kayen salle f Alger m3a jardin ?
*Attendu :* Palais Dar El Feth (jardin clos), Résidence Les Andalouses a un jardin mais elle est à Oran — ne pas la proposer pour Alger.

**23.** rani nqalab 3la une salle pas cher f Setif
*Attendu :* Salle Aïn Fouara (320) plutôt que Palais El Amir.

**24.** une salle f Constantine b decoration florale incluse
*Attendu :* Salle Les Ponts.

**25.** kayen salle f Blida m3a groupe électrogène ?
*Attendu :* Salle El Feth, Boufarik.

**26.** je veux réserver pour hier
*Attendu :* la date est passée. L'agent doit le dire et proposer de choisir une autre date.

**27.** salle f Oran, 180 personnes, midi
*Attendu :* Salle Ennour.

**28.** chambre de la mariée kayna f Alger ?
*Attendu :* Salle Ryad El Djazaïr (Chéraga) et Palais Dar El Feth (Zéralda) — les deux portent `chambre_mariee`.

**29.** 3andkom salle f Birtouta ?
*Attendu :* Espace Nour El Houda n'est pas publiée. Ne jamais la citer.

**30.** kifach ndir bach nhabes date ?
*Attendu :* expliquer le parcours. Les quatre repères doivent y être, tous les quatre : 48 h pour la réponse du propriétaire, 25 % d'acompte, 72 h d'option, et les moyens de paiement. Une reformulation qui en perd un est incomplète.

---

## D. Ce que l'agent doit REFUSER de répondre (31 à 34)

Les trente premières vérifient qu'une bonne réponse sort. Ces quatre-là
vérifient l'inverse, et c'est la moitié qui manquait : **la bonne réponse est
un aveu d'ignorance.**

Aucun texte de procédure ne couvre ces sujets. L'agent doit le dire, et
surtout **ne pas réciter le parcours de réservation à la place** — c'est
exactement le défaut qu'on corrige : « est-ce que je peux publier ma salle ? »
recevait les six étapes de la réservation, et le barème ne voyait rien parce
qu'il ne regardait que 48, 25 et 72.

*Attendu*, pour les quatre : un refus. La réponse **ne doit contenir ni les six
étapes, ni 48, ni 25, ni 72, ni un moyen de paiement.** Elle ne doit renvoyer
vers personne — ni « appelez la salle », ni « contactez le support ».

**31.** Comment j'annule ma réservation ?
*Attendu :* refus. `sujet_procedure` = `annulation`, qui n'a aucun texte. L'annulation n'est écrite nulle part aujourd'hui.

**32.** Je suis propriétaire, comment je suis payé ?
*Attendu :* refus. `sujet_procedure` = `autre`. L'argent vu du côté du propriétaire n'est PAS `paiement` — `paiement` ne désigne que l'acompte versé par le client, que le parcours décrit. Si cette question part sur les six étapes, c'est l'énumération qu'il faut reprendre, pas le barème.

**33.** J'ai déjà envoyé ma salle, je peux encore la modifier ?
*Attendu :* refus. `sujet_procedure` = `publication` — un propriétaire qui parle de SA salle, pas une réservation. À ne pas confondre avec `annulation`, qui ne concerne qu'une réservation.

**34.** comment ça marche ici ?
*Attendu :* refus. Trop vague pour désigner un sujet : `autre`. Une question qui ne dit pas de quoi elle parle ne doit pas recevoir la première réponse venue.

---

## Ce qu'on juge au J20

1. Les critères sont bien extraits : wilaya, date, créneau, nombre d'invités, budget.
2. Aucune salle inventée, aucun prix inventé.
3. Les salles non publiées ne sortent jamais.
4. Quand rien ne convient, l'agent le dit au lieu de proposer à côté.
5. Le darja et le franco-arabe sont compris aussi bien que le français.
6. **Quand aucun texte ne couvre la question, l'agent refuse au lieu de réciter
   le parcours de réservation.** Entre une réponse fausse et « je ne sais pas »,
   « je ne sais pas » gagne toujours.
