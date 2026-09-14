# =============================================================================
# Ferha - les 30 questions de reference contre l'agent deploye (J20)
#
#   .\agent_30_questions.ps1              les 30 questions
#   .\agent_30_questions.ps1 -seulement 11,12,13
#   .\agent_30_questions.ps1 -detail      montre aussi la reponse redigee
#
# LA CLE VIENT DE L'ENVIRONNEMENT, jamais d'un fichier versionne :
#   $env:FERHA_SUPABASE_ANON_KEY = "..."   (SUPABASE_ANON_KEY de env.json)
#
# CE QU'IL VERIFIE, ET POURQUOI CES TROIS-LA (section 8.5)
#
#   1. AUCUN IDENTIFIANT HORS CONTEXTE. C'est le garde-fou central : l'agent ne
#      doit parler que des salles qu'on lui a donnees. On ne se fie pas a ce que
#      la fonction declare - on relit sa prose et on y cherche TOUS les noms du
#      catalogue.
#
#   2. AUCUNE SALLE NON PUBLIEE. Deux salles de demonstration ne sont pas
#      publiees. Un compte anonyme ne peut pas les lister - c'est precisement la
#      regle - donc leurs noms sont ecrits ici, tires du document de reference.
#
#   3. AUCUN PRIX ABSENT DE LA BASE. Tout nombre d'au moins cinq chiffres dans
#      la reponse doit etre un prix du contexte, ou le budget que l'utilisateur
#      a lui-meme annonce. Un montant qui ne vient ni de l'un ni de l'autre a
#      ete invente.
#
#   4. AUCUN NOM PROPRE COUPE ENTRE DEUX ECRITURES. Une reponse en arabe avait
#      ecrit Blida moitie en arabe, moitie en latin, dans un seul mot. Un nom
#      propre s'ecrit en latin comme la base le porte, ou entierement en arabe
#      quand la base en donne la forme - wilayas.name_ar. Jamais une moitie de
#      chaque.
#
# CE FICHIER EST EN ASCII PUR. Les questions arabes sont lues depuis le document
# de reference en UTF-8, jamais ecrites ici : un .ps1 accentue lu dans le mauvais
# encodage par Windows PowerShell 5.1 ne s'analyse pas.
# =============================================================================

param(
  [string]$supabaseUrl = "https://rpcrkpklrqejahztfjvu.supabase.co",
  [string]$questions   = "..\..\docs\questions-reference.md",
  [int[]]$seulement    = @(),
  [switch]$detail,
  # DEUX APPELS AU MODELE PAR QUESTION - extraction puis redaction. Le palier
  # gratuit se compte en requetes par minute, et 1,5 s d'intervalle suffit a le
  # saturer : les questions refusees ne verifient plus rien.
  [int]$pauseMs = 6000
)

$ErrorActionPreference = "Stop"
try {
  [Console]::OutputEncoding = [Text.Encoding]::UTF8
  [Console]::InputEncoding  = [Text.Encoding]::UTF8
} catch { }

$cleAnon = $env:FERHA_SUPABASE_ANON_KEY
if (-not $cleAnon) {
  Write-Host ""
  Write-Host '  $env:FERHA_SUPABASE_ANON_KEY manquant.' -ForegroundColor Red
  Write-Host '  Posez-le pour la session, puis relancez :' -ForegroundColor DarkGray
  Write-Host '    $env:FERHA_SUPABASE_ANON_KEY = "..."' -ForegroundColor DarkGray
  Write-Host ""
  exit 2
}

$chemin = if ([IO.Path]::IsPathRooted($questions)) { $questions }
          else { Join-Path $PSScriptRoot $questions }
if (-not (Test-Path $chemin)) { throw "Document de reference introuvable : $chemin" }

# --- les 30 questions, lues telles quelles ----------------------------------
$doc = Get-Content $chemin -Raw -Encoding UTF8
# UNE TABLE DE HACHAGE ORDINAIRE, ET SURTOUT PAS [ordered]@{} : un dictionnaire
# ordonne indexe par un ENTIER fait de l'acces PAR POSITION, pas par cle.
# $liste[30] y cherche le trente-et-unieme element et leve "index hors limites".
$liste = @{}
foreach ($m in [regex]::Matches($doc, '(?m)^\*\*(\d+)\.\*\*\s+(.+?)\s*$')) {
  $liste[[int]$m.Groups[1].Value] = $m.Groups[2].Value
}
if ($liste.Count -ne 30) { throw "$($liste.Count) questions lues, 30 attendues." }

# --- le catalogue publie, vu comme un visiteur le voit ----------------------
$entetes = @{ apikey = $cleAnon; Authorization = "Bearer $cleAnon" }
$publiees = Invoke-RestMethod "$supabaseUrl/rest/v1/venues?select=id,name&status=eq.published" `
            -Headers $entetes -TimeoutSec 60

# LES DEUX NON PUBLIEES. Un compte anonyme ne peut pas les lire - c'est la
# regle qu'on teste - donc on les nomme ici, d'apres le document de reference.
$nonPubliees = @("Espace Nour El Houda", "Salle El Wiam")

# LE DECODAGE EST EXPLICITE, ET C'EST OBLIGATOIRE ICI.
#
# JSON est toujours de l'UTF-8 (RFC 8259) : une reponse "application/json" n'a
# aucune raison de porter un charset, et ai-chat a raison de ne pas en mettre.
# Mais Windows PowerShell 5.1, faute de charset, decode en ISO-8859-1 : on
# recoit "RA(c)sidence" au lieu de "Residence".
#
# CE N'EST PAS QU'UN PROBLEME D'AFFICHAGE. Le nom propre du catalogue ne
# correspondrait plus au nom abime de la prose, et le banc accuserait l'agent
# d'avoir cite une salle hors contexte alors qu'il a bien fait son travail.
function Appeler([string]$url, [hashtable]$entetes, [byte[]]$corps) {
  $r = Invoke-WebRequest $url -Method Post -UseBasicParsing -TimeoutSec 180 `
       -Headers $entetes -ContentType "application/json; charset=utf-8" -Body $corps
  $octets = $r.RawContentStream.ToArray()
  return [Text.Encoding]::UTF8.GetString($octets) | ConvertFrom-Json
}

function Aplatir([string]$t) {
  if (-not $t) { return "" }
  $s = $t.Normalize([Text.NormalizationForm]::FormD)
  $sb = New-Object Text.StringBuilder
  foreach ($c in $s.ToCharArray()) {
    if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne
        [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($c) }
  }
  ($sb.ToString().ToLowerInvariant() -replace "[\u2019']", " " -replace "\s+", " ").Trim()
}

# Le coeur distinctif d'un nom : "Salle El Bahia" -> "el bahia". Le modele omet
# souvent le mot generique, et une salle citee sans son prefixe reste citee.
function Coeur([string]$nom) {
  (Aplatir $nom) -replace '^(salle|palais|residence|complexe|espace)\s+', ''
}

# UNE SALLE QUI S'APPELLE "salle" NE SE DISTINGUE PAS DU NOM COMMUN, et le
# catalogue en contient une. Sans ce garde-fou, le banc verrait une salle citee
# hors contexte dans toute phrase francaise parlant de salles. Aucune
# comparaison de chaines ne peut trancher : le mot est le meme. On renonce donc
# au controle PAR LE NOM pour ces salles-la - le meme choix que dans ai-chat.
$MotsCommuns = @('salle','salles','palais','residence','complexe','espace',
                 'espaces','jardin','mariage','mariages','fete','fetes',
                 'reve','reves')

function CoeurUtilisable([string]$c) {
  if (-not $c -or $c.Length -lt 5) { return $false }
  foreach ($mot in ($c -split ' ')) {
    if ($MotsCommuns -notcontains $mot) { return $true }
  }
  return $false
}

# Aux frontieres de mot : "el feth" ne doit pas se trouver au milieu d'un mot.
function Motif([string]$c) { '\b' + [regex]::Escape($c) + '\b' }

# UN NOM PROPRE COUPE ENTRE DEUX ECRITURES.
#
# Le J21 avait vu passer Blida ecrit avec son article en ARABE puis sa fin en
# LATIN, dans un seul mot - quatre lettres arabes, trois latines, sans espace.
# Illisible dans les deux alphabets, et introuvable pour qui le cherche. Le meme
# defaut avait coupe "Ibn Khaldoun" au J20.
#
# CE FICHIER RESTE EN ASCII PUR : les plages d'alphabet s'ecrivent donc en
# echappements \uXXXX, que .NET comprend dans une expression reguliere.
#   \u0600-\u06ff  l'arabe
#   \u0648 \u0641 \u0628 \u0644 \u0643  les monolitteres : et, alors, par, pour, comme
#   \u0627\u0644  l'article defini
#
# UN CLITIQUE ARABE COLLE A UN MOT LATIN N'EST PAS UNE COUPURE, et c'est toute
# la difficulte du controle. L'arabe attache ses monolitteres au mot suivant :
# une reponse qui ecrit la conjonction "et" devant "Palais Dar El Feth" colle un
# caractere arabe a un nom latin INTACT. Le signaler serait accuser une reponse
# correcte.
#
# On retire donc, au plus, deux monolitteres puis l'article, et ce qui RESTE
# doit tenir dans un seul alphabet. L'article ne peut pas manger le debut d'un
# nom arabe : sur le Blida coupe il ne prend que l'article, le reste est encore
# a cheval, et la coupure se voit.
$Clitiques = '^[\u0648\u0641\u0628\u0644\u0643]{0,2}(?:\u0627\u0644)?'
$Latines   = '[A-Za-z\u00c0-\u024f]'
$Arabes    = '[\u0600-\u06ff]'

function NomsCoupes([string]$t) {
  $coupes = @()
  if (-not $t) { return $coupes }
  foreach ($m in [regex]::Matches($t, '[\p{L}]+')) {
    $mot = $m.Value
    if (-not (($mot -match $Latines) -and ($mot -match $Arabes))) { continue }
    $noyau = [regex]::Replace($mot, $Clitiques, '')
    if (($noyau -match $Latines) -and ($noyau -match $Arabes)) { $coupes += $mot }
  }
  return $coupes
}

# --- la boucle ---------------------------------------------------------------
$aJouer = if ($seulement.Count) { $seulement } else { $liste.Keys | Sort-Object }
$resultats = @()

Write-Host ""
Write-Host ("  {0,-3} {1,-7} {2,-36} {3,-30} {4}" -f "N", "statut", "criteres", "salles proposees", "verifications")
Write-Host ("  " + ("-" * 124))

foreach ($n in $aJouer) {
  $q = $liste[[int]$n]
  $corps = @{ question = $q } | ConvertTo-Json -Compress
  $octets = [Text.Encoding]::UTF8.GetBytes($corps)

  $r = $null; $erreur = $null
  try {
    $r = Appeler "$supabaseUrl/functions/v1/ai-chat" $entetes $octets
  } catch {
    $e = $_.Exception.Response
    $erreur = if ($e) { "HTTP $([int]$e.StatusCode)" } else { $_.Exception.Message }
  }

  if ($erreur) {
    Write-Host ("  {0,-3} {1}" -f $n, $erreur) -ForegroundColor Red
    $resultats += [pscustomobject]@{ n=$n; statut="ECHEC"; c1=$false; c2=$false; c3=$false; c4=$false; note=$erreur }
    Start-Sleep -Milliseconds $pauseMs
    continue
  }

  $texte   = [string]$r.reponse
  $ctx     = @($r.salles)
  $crit    = $r.criteres
  $statut  = [string]$r.statut

  # --- verification 1 : aucun identifiant hors contexte ---------------------
  # On relit la PROSE et on y cherche chaque nom du catalogue, du plus long au
  # plus court en effacant ce qui est reconnu : sans cela "Palais Dar El Feth"
  # contient "El Feth" et l'on accuserait l'agent a tort.
  $nomsContexte = @($ctx | ForEach-Object { $_.nom })
  $reste = Aplatir $texte
  $citees = @()
  foreach ($v in ($publiees | Sort-Object { (Coeur $_.name).Length } -Descending)) {
    $c = Coeur $v.name
    if (-not (CoeurUtilisable $c)) { continue }
    $m = Motif $c
    if ([regex]::IsMatch($reste, $m)) {
      $citees += $v.name
      $reste = [regex]::Replace($reste, $m, " ")
    }
  }
  $horsContexte = @($citees | Where-Object {
    $nom = $_; -not ($nomsContexte | Where-Object { (Aplatir $_) -eq (Aplatir $nom) })
  })
  $c1 = ($horsContexte.Count -eq 0)

  # --- verification 2 : aucune salle non publiee ----------------------------
  $platTexte = Aplatir $texte
  $fuites = @($nonPubliees | Where-Object {
    $c = Coeur $_
    (CoeurUtilisable $c) -and [regex]::IsMatch($platTexte, (Motif $c))
  })
  $c2 = ($fuites.Count -eq 0)

  # --- verification 3 : aucun prix absent de la base ------------------------
  # On colle les groupes de chiffres separes par une espace ou une espace
  # insecable ("342 812" -> "342812"), sinon chaque tranche compterait pour un
  # nombre a part.
  $recolle = $texte -replace '(\d)[\s\u00a0\u202f](?=\d{3}\b)', '$1'
  $prixContexte = @($ctx | ForEach-Object { [double]$_.prix_da } | Where-Object { $_ })
  $budget = if ($crit -and $crit.budget_max) { [double]$crit.budget_max } else { 0 }
  $inventes = @()
  foreach ($m in [regex]::Matches($recolle, '\d{5,}')) {
    $val = [double]$m.Value
    $connu = ($prixContexte | Where-Object { [Math]::Abs($_ - $val) -le 1 }).Count -gt 0
    if (-not $connu -and [Math]::Abs($budget - $val) -gt 1) { $inventes += $m.Value }
  }
  $c3 = ($inventes.Count -eq 0)

  # --- verification 4 : aucun nom propre coupe entre deux ecritures ---------
  $coupes = @(NomsCoupes $texte)
  $c4 = ($coupes.Count -eq 0)

  # --- affichage ------------------------------------------------------------
  $resumeCrit = @()
  if ($crit.wilaya_code)    { $resumeCrit += "w=$($crit.wilaya_code)" }
  if ($crit.commune)        { $resumeCrit += "c=$($crit.commune)" }
  if ($crit.invites)        { $resumeCrit += "$($crit.invites)p" }
  if ($crit.date)           { $resumeCrit += $crit.date }
  if ($crit.creneau)        { $resumeCrit += $crit.creneau }
  if ($crit.jour_semaine)   { $resumeCrit += $crit.jour_semaine }
  if ($crit.budget_max)     { $resumeCrit += "<=$($crit.budget_max)" }
  if ($crit.type_evenement) { $resumeCrit += $crit.type_evenement }
  if ($crit.equipements -and @($crit.equipements).Count) {
    $resumeCrit += (@($crit.equipements) -join "+")
  }
  # LES TROIS CRITERES DU J21. Sans eux, on voit l'ordre des salles changer
  # sans voir POURQUOI : le banc montrerait un resultat sans sa cause.
  if ($crit.parking_min)    { $resumeCrit += "park>=$($crit.parking_min)" }
  if ($crit.parking_flou)   { $resumeCrit += "park-bzaf" }
  if ($crit.prix_bas)       { $resumeCrit += "pas-cher" }
  $txtCrit = if ($resumeCrit.Count) { $resumeCrit -join " " } else { "(aucun)" }
  if ($txtCrit.Length -gt 36) { $txtCrit = $txtCrit.Substring(0, 33) + "..." }

  $txtSalles = if ($citees.Count) { ($citees -join ", ") } else { "(aucune)" }
  if ($txtSalles.Length -gt 30) { $txtSalles = $txtSalles.Substring(0, 27) + "..." }

  $marques = ""
  $marques += if ($c1) { "id+" } else { "id-" }
  $marques += if ($c2) { " pub+" } else { " pub-" }
  $marques += if ($c3) { " prix+" } else { " prix-" }
  $marques += if ($c4) { " nom+" } else { " nom-" }
  $couleur = if ($c1 -and $c2 -and $c3 -and $c4) { "Green" } else { "Red" }

  Write-Host ("  {0,-3} {1,-7} {2,-36} {3,-30} {4}" -f $n, $statut, $txtCrit, $txtSalles, $marques) -ForegroundColor $couleur
  if (-not $c1) { Write-Host ("       hors contexte : " + ($horsContexte -join ", ")) -ForegroundColor Red }
  if (-not $c2) { Write-Host ("       NON PUBLIEE   : " + ($fuites -join ", ")) -ForegroundColor Red }
  if (-not $c3) { Write-Host ("       prix inconnus : " + ($inventes -join ", ")) -ForegroundColor Red }
  if (-not $c4) { Write-Host ("       NOMS COUPES   : " + ($coupes -join ", ")) -ForegroundColor Red }
  if ($detail)  { Write-Host ("       > " + ($texte -replace "\s+", " ")) -ForegroundColor DarkGray }

  $resultats += [pscustomobject]@{ n=$n; statut=$statut; c1=$c1; c2=$c2; c3=$c3; c4=$c4; note="" }
  Start-Sleep -Milliseconds $pauseMs
}

# --- le compte, sans arrondi -------------------------------------------------
#
# UNE QUESTION REFUSEE PAR LE QUOTA N'EST PAS UNE REUSSITE. Elle n'a jamais
# atteint le modele : pas de prose, pas de salle, pas de prix, donc les trois
# controles passent A VIDE. Les compter gonflerait le taux sans que rien n'ait
# ete verifie. On les sort du denominateur et on les annonce a part.
$NonAbouti = @('quota', 'erreur', 'ECHEC')

$total  = $resultats.Count
$joues  = @($resultats | Where-Object { $NonAbouti -notcontains $_.statut })
$rates  = @($resultats | Where-Object { $NonAbouti -contains $_.statut })
$n      = $joues.Count
$ok     = @($joues | Where-Object { $_.c1 -and $_.c2 -and $_.c3 -and $_.c4 }).Count

Write-Host ""
Write-Host ("  " + ("=" * 124))
Write-Host ("  Questions envoyees                    : {0}" -f $total)
Write-Host ("  Dont refusees avant le modele         : {0}   (quota ou panne - rien n'a ete verifie)" -f $rates.Count)
Write-Host ("  REELLEMENT JOUEES                     : {0}" -f $n)
Write-Host ""
if ($n -gt 0) {
  Write-Host ("  Aucun identifiant hors contexte       : {0} / {1}" -f @($joues | Where-Object c1).Count, $n)
  Write-Host ("  Aucune salle non publiee              : {0} / {1}" -f @($joues | Where-Object c2).Count, $n)
  Write-Host ("  Aucun prix absent de la base          : {0} / {1}" -f @($joues | Where-Object c3).Count, $n)
  Write-Host ("  Aucun nom coupe entre deux ecritures  : {0} / {1}" -f @($joues | Where-Object c4).Count, $n)
  Write-Host ("  LES QUATRE A LA FOIS                  : {0} / {1}  ({2:N1} %)" -f $ok, $n, (100.0 * $ok / $n))
}
Write-Host ""
$parStatut = $resultats | Group-Object statut | Sort-Object Count -Descending
Write-Host ("  Par statut : " + (($parStatut | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join "  "))
Write-Host ""
if ($rates.Count) {
  Write-Host ("  A REJOUER (jamais parvenues au modele) : " + (($rates | ForEach-Object { $_.n }) -join ", ")) -ForegroundColor Yellow
  Write-Host ("  Relancez-les avec un intervalle plus long :") -ForegroundColor DarkGray
  Write-Host ("    .gent_30_questions.ps1 -seulement " + (($rates | ForEach-Object { $_.n }) -join ",") + " -pauseMs 8000") -ForegroundColor DarkGray
  Write-Host ""
}
if ($ok -lt $n) {
  Write-Host ("  A REVOIR (controle en echec) : " + ((@($joues | Where-Object { -not ($_.c1 -and $_.c2 -and $_.c3 -and $_.c4) }) | ForEach-Object { $_.n }) -join ", ")) -ForegroundColor Red
  Write-Host ""
  exit 1
}
if ($rates.Count) { exit 3 }
exit 0
