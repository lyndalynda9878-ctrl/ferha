# =============================================================================
# Ferha - la liste des libelles arabes de la base, a faire relire
#
#   .\libelles_arabes.ps1              ecrit docs/notes/libelles-arabes-a-relire.md
#   .\libelles_arabes.ps1 -sortie X.md ailleurs
#
# LA CLE VIENT DE L'ENVIRONNEMENT, jamais d'un fichier versionne :
#   $env:FERHA_SUPABASE_ANON_KEY = "..."   (SUPABASE_ANON_KEY de env.json)
#
# POURQUOI UN SCRIPT PLUTOT QU'UNE LISTE ECRITE A LA MAIN
#
# Parce que la liste doit dire ce que la base porte AUJOURD'HUI, et non ce
# qu'elle portait le jour ou quelqu'un l'a recopiee. Les libelles arabes des
# migrations 003, 009 et 010 sont marques "A RELIRE" : ils ont ete ecrits sans
# relecture par un locuteur natif, et ils attendent la votre. Entre le moment ou
# la liste part et celui ou les corrections reviennent, la seule chose qui fasse
# foi est la table.
#
# ON RELIT PAR LA CLE ANONYME, et c'est voulu : ces trois tables sont des
# donnees de reference, lisibles par un visiteur non connecte. Si ce script
# cesse un jour de fonctionner avec cette cle, c'est que la RLS a change - et
# c'est une information, pas une panne a contourner avec une cle de service.
#
# CE FICHIER EST EN ASCII PUR, comme le banc des 30 questions : un .ps1 accentue
# lu dans le mauvais encodage par Windows PowerShell 5.1 ne s'analyse pas. Les
# libelles arabes, eux, ne sont jamais ecrits ici - ils sont lus de la base et
# ecrits en UTF-8 dans le document produit.
# =============================================================================

param(
  [string]$supabaseUrl = "https://rpcrkpklrqejahztfjvu.supabase.co",
  [string]$sortie      = "..\..\docs\notes\libelles-arabes-a-relire.md"
)

$ErrorActionPreference = "Stop"
try {
  [Console]::OutputEncoding = [Text.Encoding]::UTF8
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

$entetes = @{ apikey = $cleAnon; Authorization = "Bearer $cleAnon" }

# LE DECODAGE EST EXPLICITE, ET C'EST OBLIGATOIRE ICI - meme raison qu'au banc
# des 30 questions. JSON est toujours de l'UTF-8 (RFC 8259) et PostgREST n'a
# aucune raison d'annoncer un charset ; Windows PowerShell 5.1, faute de
# charset, decode en ISO-8859-1. Sur une liste de libelles ARABES, cela ne
# donnerait pas "RA(c)sidence" mais une bouillie complete.
function Lire([string]$chemin) {
  $r = Invoke-WebRequest "$supabaseUrl/rest/v1/$chemin" -Headers $entetes `
       -UseBasicParsing -TimeoutSec 60
  $octets = $r.RawContentStream.ToArray()
  return [Text.Encoding]::UTF8.GetString($octets) | ConvertFrom-Json
}

$amenities = Lire "amenities?select=code,label_fr,label_ar,category,position&order=category,position"
$types     = Lire "event_types?select=code,label_fr,label_ar,position&order=position"
$wilayas   = Lire "wilayas?select=code,name_fr,name_ar&order=code"

$total = $amenities.Count + $types.Count + $wilayas.Count

$lignes = New-Object Collections.Generic.List[string]
function Ajouter([string]$t) { $lignes.Add($t) }

Ajouter "# Les libelles arabes de la base, a relire"
Ajouter ""
Ajouter "**$total libelles**, lus de la base le $(Get-Date -Format 'yyyy-MM-dd')."
Ajouter "Genere par ``supabase/outils/libelles_arabes.ps1`` - ne pas modifier a la main"
Ajouter "la colonne *arabe actuel* : elle dit ce que la table porte."
Ajouter ""
Ajouter "## Comment annoter"
Ajouter ""
Ajouter "Ecrivez votre version dans la colonne **correction**, et laissez-la vide"
Ajouter "quand le libelle actuel vous convient. Une case vide veut donc dire"
Ajouter "*bon*, pas *pas encore regarde* - si vous vous arretez en chemin, dites-le"
Ajouter "moi, je ne retirerai la mention que sur ce qui a ete relu."
Ajouter ""
Ajouter "Ces libelles sont **de l'arabe standard**, pas de la darja : ce sont des"
Ajouter "etiquettes d'interface, pas une conversation. Le meme choix qu'aux six"
Ajouter "ecrans traduits avant eux."
Ajouter ""
Ajouter "## Ce qui arrive ensuite"
Ajouter ""
Ajouter "Vos corrections partent dans une migration qui met les tables a jour **et**"
Ajouter "retire la mention ``-- A RELIRE`` des migrations 003, 009 et 010. Tant que"
Ajouter "la mention est la, elle dit la verite : personne n'a relu."
Ajouter ""

Ajouter "---"
Ajouter ""
Ajouter "## Equipements (``amenities``, migration 003) - $($amenities.Count) libelles"
Ajouter ""
Ajouter "| code | categorie | francais | arabe actuel | correction |"
Ajouter "|---|---|---|---|---|"
foreach ($a in $amenities) {
  Ajouter ("| ``{0}`` | {1} | {2} | {3} | |" -f $a.code, $a.category, $a.label_fr, $a.label_ar)
}
Ajouter ""

Ajouter "---"
Ajouter ""
Ajouter "## Types d'evenement (``event_types``, migration 010) - $($types.Count) libelles"
Ajouter ""
Ajouter "| code | francais | arabe actuel | correction |"
Ajouter "|---|---|---|---|"
foreach ($t in $types) {
  Ajouter ("| ``{0}`` | {1} | {2} | |" -f $t.code, $t.label_fr, $t.label_ar)
}
Ajouter ""

Ajouter "---"
Ajouter ""
Ajouter "## Wilayas (``wilayas``, migration 009) - $($wilayas.Count) libelles"
Ajouter ""
Ajouter "Les 58 wilayas, dans l'ordre de leur code. Ce sont des NOMS PROPRES : leur"
Ajouter "forme arabe est celle de l'usage officiel, et c'est la seule des trois"
Ajouter "listes ou une erreur rend un lieu introuvable plutot qu'un mot maladroit."
Ajouter ""
Ajouter "| code | francais | arabe actuel | correction |"
Ajouter "|---|---|---|---|"
foreach ($w in $wilayas) {
  Ajouter ("| {0} | {1} | {2} | |" -f $w.code, $w.name_fr, $w.name_ar)
}
Ajouter ""

$chemin = if ([IO.Path]::IsPathRooted($sortie)) { $sortie }
          else { Join-Path $PSScriptRoot $sortie }

# SANS BOM, parce que le fichier est lu par git, par un editeur et par moi.
$sansBom = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($chemin, ($lignes -join "`r`n") + "`r`n", $sansBom)

Write-Host ""
Write-Host ("  {0} libelles ecrits dans {1}" -f $total, (Resolve-Path $chemin))
Write-Host ("    equipements       : {0}" -f $amenities.Count)
Write-Host ("    types d'evenement : {0}" -f $types.Count)
Write-Host ("    wilayas           : {0}" -f $wilayas.Count)
Write-Host ""
