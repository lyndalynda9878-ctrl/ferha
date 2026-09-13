# =============================================================================
# Ferha - chercher une salle par le SENS (J19, section 8.4)
#
# On tape une question en francais, en arabe ou en franco-arabe ; le service
# d'empreintes la transforme en 384 nombres, la base classe les salles par
# proximite, et les cinq premieres s'affichent.
#
#   .\chercher.ps1 "une salle a Oran pour 300 invites"
#   .\chercher.ps1                      (il demande la question)
#
# LES JETONS VIENNENT DE L'ENVIRONNEMENT, JAMAIS D'UN FICHIER VERSIONNE.
# Pour la session courante :
#
#   $env:FERHA_EMBED_TOKEN       = "..."   le jeton du service d'empreintes
#   $env:FERHA_SUPABASE_ANON_KEY = "..."   la cle anon de Supabase
#
# La cle anon est celle de env.json, a la racine du projet. Elle est publique
# par nature - elle est compilee dans l'application - mais elle n'a pas sa
# place dans un fichier suivi par git, et ce script n'en garde aucune trace.
#
# CE FICHIER EST EN ASCII PUR, et l'arabe des exemples est ecrit en points de
# code. Un .ps1 contenant des caracteres accentues lu dans le mauvais encodage
# par Windows PowerShell 5.1 ne s'analyse tout simplement pas.
# =============================================================================

param(
  [Parameter(Position = 0)]
  [string]$question,

  [string]$embeddingsUrl = "https://ferha-embeddings.onrender.com",
  [string]$supabaseUrl   = "https://rpcrkpklrqejahztfjvu.supabase.co",
  [int]$combien = 5
)

$ErrorActionPreference = "Stop"

# La console doit parler UTF-8 dans les deux sens, sinon une question tapee en
# arabe arrive en points d'interrogation et l'on mesure la distance a du vide.
try {
  [Console]::OutputEncoding = [Text.Encoding]::UTF8
  [Console]::InputEncoding  = [Text.Encoding]::UTF8
} catch { }

$jetonEmbed = $env:FERHA_EMBED_TOKEN
$cleAnon    = $env:FERHA_SUPABASE_ANON_KEY

if (-not $jetonEmbed -or -not $cleAnon) {
  Write-Host ""
  Write-Host "  Il manque un jeton." -ForegroundColor Red
  if (-not $jetonEmbed) { Write-Host '    $env:FERHA_EMBED_TOKEN       manquant  (jeton du service d empreintes)' }
  if (-not $cleAnon)    { Write-Host '    $env:FERHA_SUPABASE_ANON_KEY manquant  (SUPABASE_ANON_KEY de env.json)' }
  Write-Host ""
  Write-Host "  Posez-les pour la session, puis relancez :" -ForegroundColor DarkGray
  Write-Host '    $env:FERHA_EMBED_TOKEN       = "..."' -ForegroundColor DarkGray
  Write-Host '    $env:FERHA_SUPABASE_ANON_KEY = "..."' -ForegroundColor DarkGray
  Write-Host ""
  exit 2
}

if (-not $question) {
  Write-Host ""
  Write-Host "  Votre question - francais, arabe ou franco-arabe." -ForegroundColor DarkGray
  Write-Host "  Par exemple : une salle a Oran pour 300 invites" -ForegroundColor DarkGray
  $question = Read-Host "  > "
}

$question = $question.Trim()
if (-not $question) { Write-Host "  Rien a chercher." -ForegroundColor Red; exit 2 }

# -----------------------------------------------------------------------------
# 1. Reveiller le service, et lui demander quel modele il fait tourner.
#
# Le nom du modele n'est PAS ecrit dans ce script : c'est le service qui le dit,
# et c'est ce nom-la qu'on passe a la base. Comparer un vecteur aux empreintes
# d'un autre modele rendrait des lignes plausibles et fausses, sans erreur.
# -----------------------------------------------------------------------------

Write-Host ""
Write-Host "  Reveil du service (jusqu'a une minute s'il dormait) ..." -ForegroundColor DarkGray
$sante = Invoke-RestMethod "$embeddingsUrl/health" -TimeoutSec 180
$modele = $sante.modele
Write-Host ("  {0}, {1} dimensions" -f $modele, $sante.dimensions) -ForegroundColor DarkGray

# -----------------------------------------------------------------------------
# 2. La question devient 384 nombres.
#
# nature = "question" pose le prefixe "query:" cote service. Les documents de
# salle, eux, ont ete vectorises avec "passage:" par embed-venue. Intervertir
# les deux ne leve aucune erreur et degrade tout, silencieusement.
# -----------------------------------------------------------------------------

$corps  = @{ textes = @($question); nature = "question" } | ConvertTo-Json -Depth 3 -Compress
$octets = [Text.Encoding]::UTF8.GetBytes($corps)

$reponse = Invoke-RestMethod "$embeddingsUrl/embed" -Method Post `
  -Headers @{ Authorization = "Bearer $jetonEmbed" } `
  -ContentType "application/json; charset=utf-8" -Body $octets -TimeoutSec 180

# PAS DE VIRGULE ICI, ET C'EST L'INVERSE DE preuve-multilingue.ps1.
#
# La virgule en tete ne sert qu'au RETOUR D'UNE FONCTION : c'est la que
# PowerShell deroule un tableau de tableaux en une seule liste plate. Elle est
# donc indispensable dans preuve-multilingue.ps1, ou les vecteurs passent par
# une fonction.
#
# Invoke-RestMethod, lui, ne deroule rien : $reponse.vecteurs EST deja le
# tableau des vecteurs. Y ajouter une virgule emballe le tout une fois de plus,
# et [0] rend alors le tableau entier au lieu de son premier element - 1 objet
# la ou l'on attend 384 nombres. Le remede appliquer au mauvais endroit fait
# exactement le mal qu'il previent ailleurs.
$v = $reponse.vecteurs[0]

if ($v.Count -ne 384) {
  throw "Le service a rendu $($v.Count) nombres, 384 attendus."
}

# -----------------------------------------------------------------------------
# 3. La base classe.
#
# pgvector lit le litteral "[0.1,0.2,...]". InvariantCulture est OBLIGATOIRE :
# sur un Windows francais, "0.1".ToString() rend "0,1", et le vecteur entier
# devient illisible pour Postgres - avec une erreur qui parlera de syntaxe, pas
# de virgule decimale.
# -----------------------------------------------------------------------------

# LE [double] N'EST PAS DECORATIF. ConvertFrom-Json, sous Windows PowerShell 5.1,
# rend un Decimal pour les nombres qui y tiennent et un Double pour les autres -
# donc un melange des deux dans le meme vecteur. Or "R" (aller-retour exact)
# n'existe PAS comme format de Decimal : sans la conversion, on tombe sur
# "Specificateur de format non valide", et seulement sur certaines questions,
# selon les valeurs rendues.
$ic = [Globalization.CultureInfo]::InvariantCulture
$litteral = "[" + (($v | ForEach-Object { ([double]$_).ToString("R", $ic) }) -join ",") + "]"

$corpsRpc = @{
  p_embedding = $litteral
  p_model     = $modele
  p_limit     = $combien
} | ConvertTo-Json -Depth 3 -Compress

$salles = Invoke-RestMethod "$supabaseUrl/rest/v1/rpc/recherche_semantique" `
  -Method Post `
  -Headers @{ apikey = $cleAnon; Authorization = "Bearer $cleAnon" } `
  -ContentType "application/json" `
  -Body ([Text.Encoding]::UTF8.GetBytes($corpsRpc)) -TimeoutSec 60

# -----------------------------------------------------------------------------
# 4. Ce qui sort.
# -----------------------------------------------------------------------------

Write-Host ""
Write-Host "  $question" -ForegroundColor White
Write-Host ""

if (-not $salles -or $salles.Count -eq 0) {
  Write-Host "  Aucune salle indexee." -ForegroundColor Yellow
  Write-Host ""
  Write-Host "  L'index est vide tant qu'embed-venue n'a pas tourne une fois." -ForegroundColor DarkGray
  Write-Host "  Voir supabase/functions/embed-venue/index.ts pour les secrets." -ForegroundColor DarkGray
  exit 1
}

$rang = 1
foreach ($s in $salles) {
  $note = if ($s.review_count -gt 0) { "{0:N1}/5 ({1} avis)" -f $s.rating, $s.review_count }
          else { "pas encore d'avis" }
  Write-Host ("  {0}. {1,-28} {2,-16} {3,4} places   {4}" -f `
    $rang, $s.name, "$($s.commune), $($s.wilaya_name)", $s.capacity_seated, $note)
  Write-Host ("      proximite {0:N4}" -f $s.proximite) -ForegroundColor DarkGray
  $rang++
}

Write-Host ""
# CE QUI EST CLASSE N'EST PAS CE QUI CONVIENT. La recherche par le sens propose
# des candidats ; elle ne verifie ni la wilaya, ni la capacite, ni la date. Ce
# tri-la est le travail de l'agent du J20, sur des criteres verifiables - et
# c'est pour cela qu'aucun seuil de proximite n'est applique ici.
Write-Host "  Classement par proximite seule : ni wilaya, ni capacite, ni date" -ForegroundColor DarkGray
Write-Host "  ne sont verifiees. C'est le travail de l'agent, au J20." -ForegroundColor DarkGray
Write-Host ""
