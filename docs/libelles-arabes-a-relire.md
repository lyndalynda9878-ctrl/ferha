# Les libelles arabes de la base, a relire

**73 libelles**, lus de la base le 2026-09-14.
Genere par `supabase/outils/libelles_arabes.ps1` - ne pas modifier a la main
la colonne *arabe actuel* : elle dit ce que la table porte.

## Comment annoter

Ecrivez votre version dans la colonne **correction**, et laissez-la vide
quand le libelle actuel vous convient. Une case vide veut donc dire
*bon*, pas *pas encore regarde* - si vous vous arretez en chemin, dites-le
moi, je ne retirerai la mention que sur ce qui a ete relu.

Ces libelles sont **de l'arabe standard**, pas de la darja : ce sont des
etiquettes d'interface, pas une conversation. Le meme choix qu'aux six
ecrans traduits au J22.

## Ce qui arrive ensuite

Vos corrections partent dans une migration qui met les tables a jour **et**
retire la mention `-- A RELIRE` des migrations 003, 009 et 010. Tant que
la mention est la, elle dit la verite : personne n'a relu.

---

## Equipements (`amenities`, migration 003) - 10 libelles

| code | categorie | francais | arabe actuel | correction |
|---|---|---|---|---|
| `climatisation` | confort | Climatisation | تكييف | |
| `espace_femmes` | espaces | Espace femmes | فضاء خاص بالنساء | |
| `chambre_mariee` | espaces | Chambre de la mariée | غرفة العروس | |
| `cuisine_equipee` | espaces | Cuisine équipée | مطبخ مجهز | |
| `jardin` | espaces | Jardin | حديقة | |
| `groupe_electrogene` | logistique | Groupe électrogène | مولد كهربائي | |
| `traiteur_libre` | services | Traiteur libre | حرية اختيار المطعم | |
| `sono` | services | Sono | نظام صوتي | |
| `dj` | services | DJ | دي جي | |
| `decoration_florale` | services | Décoration florale | تزيين بالورود | |

---

## Types d'evenement (`event_types`, migration 010) - 5 libelles

| code | francais | arabe actuel | correction |
|---|---|---|---|
| `mariage` | Mariage | زفاف | |
| `fiancailles` | Fiançailles | خطوبة | |
| `henne` | Henné | حنة | |
| `circoncision` | Circoncision | ختان | |
| `anniversaire` | Anniversaire | عيد ميلاد | |

---

## Wilayas (`wilayas`, migration 009) - 58 libelles

Les 58 wilayas, dans l'ordre de leur code. Ce sont des NOMS PROPRES : leur
forme arabe est celle de l'usage officiel, et c'est la seule des trois
listes ou une erreur rend un lieu introuvable plutot qu'un mot maladroit.

| code | francais | arabe actuel | correction |
|---|---|---|---|
| 01 | Adrar | أدرار | |
| 02 | Chlef | الشلف | |
| 03 | Laghouat | الأغواط | |
| 04 | Oum El Bouaghi | أم البواقي | |
| 05 | Batna | باتنة | |
| 06 | Béjaïa | بجاية | |
| 07 | Biskra | بسكرة | |
| 08 | Béchar | بشار | |
| 09 | Blida | البليدة | |
| 10 | Bouira | البويرة | |
| 11 | Tamanrasset | تمنراست | |
| 12 | Tébessa | تبسة | |
| 13 | Tlemcen | تلمسان | |
| 14 | Tiaret | تيارت | |
| 15 | Tizi Ouzou | تيزي وزو | |
| 16 | Alger | الجزائر | |
| 17 | Djelfa | الجلفة | |
| 18 | Jijel | جيجل | |
| 19 | Sétif | سطيف | |
| 20 | Saïda | سعيدة | |
| 21 | Skikda | سكيكدة | |
| 22 | Sidi Bel Abbès | سيدي بلعباس | |
| 23 | Annaba | عنابة | |
| 24 | Guelma | قالمة | |
| 25 | Constantine | قسنطينة | |
| 26 | Médéa | المدية | |
| 27 | Mostaganem | مستغانم | |
| 28 | M'Sila | المسيلة | |
| 29 | Mascara | معسكر | |
| 30 | Ouargla | ورقلة | |
| 31 | Oran | وهران | |
| 32 | El Bayadh | البيض | |
| 33 | Illizi | إليزي | |
| 34 | Bordj Bou Arreridj | برج بوعريريج | |
| 35 | Boumerdès | بومرداس | |
| 36 | El Tarf | الطارف | |
| 37 | Tindouf | تندوف | |
| 38 | Tissemsilt | تيسمسيلت | |
| 39 | El Oued | الوادي | |
| 40 | Khenchela | خنشلة | |
| 41 | Souk Ahras | سوق أهراس | |
| 42 | Tipaza | تيبازة | |
| 43 | Mila | ميلة | |
| 44 | Aïn Defla | عين الدفلى | |
| 45 | Naâma | النعامة | |
| 46 | Aïn Témouchent | عين تموشنت | |
| 47 | Ghardaïa | غرداية | |
| 48 | Relizane | غليزان | |
| 49 | Timimoun | تيميمون | |
| 50 | Bordj Badji Mokhtar | برج باجي مختار | |
| 51 | Ouled Djellal | أولاد جلال | |
| 52 | Béni Abbès | بني عباس | |
| 53 | In Salah | عين صالح | |
| 54 | In Guezzam | عين قزام | |
| 55 | Touggourt | تقرت | |
| 56 | Djanet | جانت | |
| 57 | El M'Ghair | المغير | |
| 58 | El Meniaa | المنيعة | |

