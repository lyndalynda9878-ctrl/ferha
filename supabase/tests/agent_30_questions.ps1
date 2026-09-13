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
# CE FICHIER EST EN ASCII PUR. Les questions arabes sont lues depuis le document
# de reference en UTF-8, jamais ecrites ici : un .ps1 accentue lu dans le mauvais
# encodage par Windows PowerShell 5.1 ne s'analyse pas.
# =============================================================================

param(
  [string]$supabaseUrl = "https://rpcrkpklrqejahztfjvu.supabase.co",
  [string]$questions   = "..\..\Claude outputs\questions-reference-ferha.md",
  [int[]]$seulement    = @(),
  [switch]$detail,
  [int]$pauseMs = 1500
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

# --- la boucle ---------------------------------------------------------------
$aJouer = if ($seulement.Count) { $seulement } else { $liste.Keys | Sort-Object }
$resultats = @()

Write-Host ""
Write-Host ("  {0,-3} {1,-7} {2,-28} {3,-30} {4}" -f "N", "statut", "criteres", "salles proposees", "verifications")
Write-Host ("  " + ("-" * 116))

foreach ($n in $aJouer) {
  $q = $liste[[int]$n]
  $corps = @{ question = $q } | ConvertTo-Json -Compress
  $octets = [Text.Encoding]::UTF8.GetBytes($corps)

  $r = $null; $erreur = $null
  try {
    $r = Invoke-RestMethod "$supabaseUrl/functions/v1/ai-chat" -Method Post `
         -Headers $entetes -ContentType "application/json; charset=utf-8" `
         -Body $octets -TimeoutSec 180
  } catch {
    $e = $_.Exception.Response
    $erreur = if ($e) { "HTTP $([int]$e.StatusCode)" } else { $_.Exception.Message }
  }

  if ($erreur) {
    Write-Host ("  {0,-3} {1}" -f $n, $erreur) -ForegroundColor Red
    $resultats += [pscustomobject]@{ n=$n; statut="ECHEC"; c1=$false; c2=$false; c3=$false; note=$erreur }
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
    if ($c -and $reste.Contains($c)) {
      $citees += $v.name
      $reste = $reste.Replace($c, " ")
    }
  }
  $horsContexte = @($citees | Where-Object {
    $nom = $_; -not ($nomsContexte | Where-Object { (Aplatir $_) -eq (Aplatir $nom) })
  })
  $c1 = ($horsContexte.Count -eq 0)

  # --- verification 2 : aucune salle non publiee ----------------------------
  $platTexte = Aplatir $texte
  $fuites = @($nonPubliees | Where-Object { $platTexte.Contains((Coeur $_)) })
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

  # --- affichage ------------------------------------------------------------
  $resumeCrit = @()
  if ($crit.wilaya_code)    { $resumeCrit += "w=$($crit.wilaya_code)" }
  if ($crit.commune)        { $resumeCrit += "c=$($crit.commune)" }
  if ($crit.invites)        { $resumeCrit += "$($crit.invites)p" }
  if ($crit.date)           { $resumeCrit += $crit.date }
  if ($crit.creneau)        { $resumeCrit += $crit.creneau }
  if ($crit.budget_max)     { $resumeCrit += "<=$($crit.budget_max)" }
  if ($crit.type_evenement) { $resumeCrit += $crit.type_evenement }
  if ($crit.equipements -and @($crit.equipements).Count) {
    $resumeCrit += (@($crit.equipements) -join "+")
  }
  $txtCrit = if ($resumeCrit.Count) { $resumeCrit -join " " } else { "(aucun)" }
  if ($txtCrit.Length -gt 28) { $txtCrit = $txtCrit.Substring(0, 25) + "..." }

  $txtSalles = if ($citees.Count) { ($citees -join ", ") } else { "(aucune)" }
  if ($txtSalles.Length -gt 30) { $txtSalles = $txtSalles.Substring(0, 27) + "..." }

  $marques = ""
  $marques += if ($c1) { "id+" } else { "id-" }
  $marques += if ($c2) { " pub+" } else { " pub-" }
  $marques += if ($c3) { " prix+" } else { " prix-" }
  $couleur = if ($c1 -and $c2 -and $c3) { "Green" } else { "Red" }

  Write-Host ("  {0,-3} {1,-7} {2,-28} {3,-30} {4}" -f $n, $statut, $txtCrit, $txtSalles, $marques) -ForegroundColor $couleur
  if (-not $c1) { Write-Host ("       hors contexte : " + ($horsContexte -join ", ")) -ForegroundColor Red }
  if (-not $c2) { Write-Host ("       NON PUBLIEE   : " + ($fuites -join ", ")) -ForegroundColor Red }
  if (-not $c3) { Write-Host ("       prix inconnus : " + ($inventes -join ", ")) -ForegroundColor Red }
  if ($detail)  { Write-Host ("       > " + ($texte -replace "\s+", " ")) -ForegroundColor DarkGray }

  $resultats += [pscustomobject]@{ n=$n; statut=$statut; c1=$c1; c2=$c2; c3=$c3; note="" }
  Start-Sleep -Milliseconds $pauseMs
}

# --- le compte, sans arrondi -------------------------------------------------
$total = $resultats.Count
$ok    = @($resultats | Where-Object { $_.c1 -and $_.c2 -and $_.c3 }).Count
Write-Host ""
Write-Host ("  " + ("=" * 116))
Write-Host ("  Questions jouees                      : {0}" -f $total)
Write-Host ("  Aucun identifiant hors contexte       : {0} / {1}" -f @($resultats | Where-Object c1).Count, $total)
Write-Host ("  Aucune salle non publiee              : {0} / {1}" -f @($resultats | Where-Object c2).Count, $total)
Write-Host ("  Aucun prix absent de la base          : {0} / {1}" -f @($resultats | Where-Object c3).Count, $total)
Write-Host ("  LES TROIS A LA FOIS                   : {0} / {1}  ({2:N1} %)" -f $ok, $total, (100.0 * $ok / [Math]::Max(1,$total)))
Write-Host ""
$parStatut = $resultats | Group-Object statut | Sort-Object Count -Descending
Write-Host ("  Par statut : " + (($parStatut | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join "  "))
Write-Host ""
if ($ok -lt $total) {
  Write-Host ("  A revoir : " + ((@($resultats | Where-Object { -not ($_.c1 -and $_.c2 -and $_.c3) }) | ForEach-Object { $_.n }) -join ", ")) -ForegroundColor Red
  Write-Host ""
  exit 1
}
exit 0
