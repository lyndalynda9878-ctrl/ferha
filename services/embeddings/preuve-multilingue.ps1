param(
  [string]$url   = "http://127.0.0.1:8099",
  [string]$jeton = "jeton-d-essai-local"
)

$ErrorActionPreference = "Stop"
$entetes = @{ Authorization = "Bearer $jeton" }

# Le service dort au bout de 15 minutes sur l'offre gratuite : on le reveille
# par /health, qui ne demande pas de jeton, avant de chronometrer quoi que ce
# soit. Un reveil a froid prend de 30 a 60 secondes.
Write-Host "Reveil du service ..." -ForegroundColor DarkGray
$sante = Invoke-RestMethod "$url/health" -TimeoutSec 180
Write-Host ("  {0} - {1} - {2} dimensions" -f $sante.etat, $sante.modele, $sante.dimensions)

function Get-Empreintes([string[]]$textes, [string]$nature) {
  $corps = @{ textes = $textes; nature = $nature } | ConvertTo-Json -Depth 3 -Compress
  # UTF-8 EXPLICITE. Sans cela, Windows PowerShell envoie le corps dans
  # l'encodage de la console et l'arabe arrive en points d'interrogation : la
  # preuve echouerait pour une raison qui n'a rien a voir avec le modele.
  $octets = [Text.Encoding]::UTF8.GetBytes($corps)
  $r = Invoke-RestMethod "$url/embed" -Method Post -Headers $entetes `
       -ContentType "application/json; charset=utf-8" -Body $octets -TimeoutSec 180
  # LA VIRGULE EN TETE N'EST PAS UNE COQUILLE. Sans elle, PowerShell "deroule"
  # le tableau de vecteurs en sortie de fonction : on recupere 384 nombres a
  # plat au lieu d'un tableau de vecteurs, et le produit scalaire porte alors
  # sur une seule composante. Il rend ~0,000 pour tout le monde - des chiffres
  # parfaitement plausibles, et faux.
  return ,$r.vecteurs
}

# L'arabe est ecrit en points de code, et non en clair : un script .ps1 lu dans
# le mauvais encodage transformerait les lettres en charabia, et le test
# mesurerait alors la distance a du charabia.
function U([int[]]$points) { -join ($points | ForEach-Object { [char]$_ }) }

$question = "salle des fetes a Oran pour un mariage"

$candidats = [ordered]@{
  "AR   arabe standard" = U 0x642,0x627,0x639,0x629,0x20,0x623,0x641,0x631,0x627,0x62D,0x20,0x641,0x64A,0x20,0x648,0x647,0x631,0x627,0x646
  "FR   meme sens     " = "salle de mariage a Oran"
  "MIX  franco-arabe  " = "kayen salle f wahran l3ors"
  "HORS mecanique fr  " = "reparation de moteur diesel a Tamanrasset"
  "HORS mecanique ar  " = U 0x625,0x635,0x644,0x627,0x62D,0x20,0x645,0x62D,0x631,0x643,0x20,0x627,0x644,0x633,0x64A,0x627,0x631,0x629
  "HORS meteo darja   " = U 0x648,0x627,0x634,0x20,0x631,0x627,0x647,0x20,0x627,0x644,0x637,0x642,0x633
}

$vq = (Get-Empreintes @($question) "question")[0]
$vs = Get-Empreintes ([string[]]$candidats.Values) "salle"

# On verifie la FORME avant de calculer quoi que ce soit.
if ($vq.Count -ne 384 -or $vs.Count -ne $candidats.Count) {
  throw "Forme inattendue : question $($vq.Count) nombres, $($vs.Count) vecteurs de salle attendus $($candidats.Count)."
}

Write-Host ""
Write-Host "Proximite avec la question francaise : $question"
Write-Host ""

$pertinents = @(); $horsSujet = @(); $i = 0
foreach ($cle in $candidats.Keys) {
  $s = 0.0
  for ($d = 0; $d -lt $vq.Count; $d++) { $s += $vq[$d] * $vs[$i][$d] }
  if ($cle.StartsWith("HORS")) { $horsSujet += $s; $couleur = "DarkGray" }
  else                         { $pertinents += $s; $couleur = "Green" }
  Write-Host ("  {0:N4}   {1}   {2}" -f $s, $cle, $candidats[$cle]) -ForegroundColor $couleur
  $i++
}

$pire     = ($pertinents | Measure-Object -Minimum).Minimum
$meilleur = ($horsSujet  | Measure-Object -Maximum).Maximum
$marge    = $pire - $meilleur

Write-Host ""
Write-Host ("  pire pertinent {0:N4}   meilleur hors-sujet {1:N4}   marge {2:N4}" -f $pire, $meilleur, $marge)
Write-Host ""

if ($marge -gt 0) {
  Write-Host "  REUSSI : les trois facons de dire la meme chose - francais, arabe," -ForegroundColor Green
  Write-Host "  franco-arabe - passent toutes devant tous les textes sans rapport." -ForegroundColor Green
  exit 0
} else {
  Write-Host "  ECHEC : un texte sans rapport se classe devant une reformulation." -ForegroundColor Red
  exit 1
}
