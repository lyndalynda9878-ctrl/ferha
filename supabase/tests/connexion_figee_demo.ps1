<#
.SYNOPSIS
  Joue le visiteur qui veut fermer les comptes de demonstration, par l'API
  d'authentification, et verifie que les boutons « Entrer comme... » marchent
  encore.

.DESCRIPTION
  La moitie de la migration 041 qu'aucun test SQL ne peut prouver : le
  declencheur ne mord que sous le role de GoTrue, et postgres ne peut pas
  l'endosser. Ce script passe donc par la vraie porte, comme le ferait un
  visiteur connecte : PUT /auth/v1/user, avec la cle publique.

  Pour Amina puis Karim :
    1. connexion avec demo1234                          -> 200 attendu ;
    2. PUT password (un mot de passe temporaire)         -> 200, sans effet ;
    3. PUT data (un nom barbouille)                     -> 200, sans effet ;
    4. connexion avec demo1234                          -> 200 attendu ;
    5. connexion avec le mot de passe temporaire        -> 400 attendu.

    6. POST /factors (inscription TOTP)                 -> 422 attendu,
                                                           mfa_totp_enroll_not_enabled.

  SI LA SERRURE A LACHE (etape 5 en 200), le script remet demo1234 lui-meme
  par l'API, puis echoue. Il ne laisse jamais les boutons casses.

  L'ETAPE 6 PROUVE UN REGLAGE, PAS UNE MIGRATION. Un visiteur pouvait inscrire
  et verifier un facteur TOTP sur Amina ; un visiteur suivant ne pouvait plus
  le retirer (422 insufficient_aal), et le menage ne touche pas
  auth.mfa_factors. La fermeture est dans le tableau de bord - Authentication
  > Multi-Factor > TOTP : Disabled -, et donc nulle part dans le depot. Voir
  supabase/README.md, « Ce qu'un visiteur ne peut pas leur faire ». Si le
  reglage est perdu, l'etape 6 echoue ; et si un facteur a ete cree, le
  script le retire aussitot (un facteur non verifie se retire en aal1).

  NI L'ADRESSE NI LE TELEPHONE ne sont essayes ici : GoTrue refuse avant toute
  ecriture (adresse @demo.ferha.dz sans serveur de courrier ; aucun fournisseur
  SMS), et chaque essai d'adresse consomme le quota d'envoi du projet. Le
  declencheur les fige quand meme ; c'est le test du 3 octobre 2026 qui l'a
  constate, voir l'en-tete de 041.

  La cle lue est la cle PUBLIQUE de l'application, dans env.json, a la racine
  du depot - non versionne. Rien n'est affiche de son contenu.

.EXAMPLE
  .\supabase\tests\connexion_figee_demo.ps1
#>

[CmdletBinding()]
param(
    [string]$EnvJson
)

$ErrorActionPreference = 'Stop'

# Pas dans le param() : sous PowerShell 5.1, $PSScriptRoot y est parfois vide.
if (-not $EnvJson) {
    $ici = Split-Path -Parent $MyInvocation.MyCommand.Path
    $EnvJson = Join-Path $ici '..\..\env.json'
}

if (-not (Test-Path $EnvJson)) {
    Write-Host "env.json introuvable ($EnvJson)." -ForegroundColor Red
    exit 1
}

$env_ = Get-Content $EnvJson -Raw | ConvertFrom-Json
$base = $env_.SUPABASE_URL.TrimEnd('/') + '/auth/v1'
$cle  = $env_.SUPABASE_ANON_KEY

$demo  = 'demo1234'
$temp  = 'test-serrure-' + [guid]::NewGuid().ToString('N').Substring(0, 8)

function Appel([string]$Methode, [string]$Chemin, $Corps, [string]$Jeton) {
    $entetes = @{ apikey = $cle }
    if ($Jeton) { $entetes['Authorization'] = "Bearer $Jeton" }
    try {
        $r = Invoke-WebRequest -Uri ($base + $Chemin) -Method $Methode -Headers $entetes `
                -ContentType 'application/json' -Body ($Corps | ConvertTo-Json -Compress) `
                -UseBasicParsing
        return @{ Statut = [int]$r.StatusCode; Corps = ($r.Content | ConvertFrom-Json) }
    } catch [System.Net.WebException] {
        $rep = $_.Exception.Response
        if (-not $rep) { throw }
        return @{ Statut = [int]$rep.StatusCode; Corps = $null }
    }
}

function Connexion([string]$Email, [string]$Mdp) {
    Appel 'POST' '/token?grant_type=password' @{ email = $Email; password = $Mdp } $null
}

$echecs = 0
function Verifie([string]$Libelle, [int]$Obtenu, [int]$Attendu) {
    if ($Obtenu -eq $Attendu) {
        Write-Host ("  OK     {0} : {1}" -f $Libelle, $Obtenu) -ForegroundColor Green
    } else {
        Write-Host ("  ECHEC  {0} : {1} (attendu {2})" -f $Libelle, $Obtenu, $Attendu) -ForegroundColor Red
        $script:echecs++
    }
}

foreach ($email in @('amina@demo.ferha.dz', 'karim.belhadj@demo.ferha.dz')) {
    Write-Host ''
    Write-Host "== $email"

    $c = Connexion $email $demo
    Verifie 'connexion demo1234' $c.Statut 200
    if ($c.Statut -ne 200) { continue }
    $jeton = $c.Corps.access_token

    Verifie 'PUT password (sans effet attendu)' (Appel 'PUT' '/user' @{ password = $temp } $jeton).Statut 200
    Verifie 'PUT data (sans effet attendu)' (Appel 'PUT' '/user' @{ data = @{ full_name = 'Nom barbouille' } } $jeton).Statut 200

    Verifie 'connexion demo1234 apres' (Connexion $email $demo).Statut 200

    $t = Connexion $email $temp
    Verifie 'connexion mot de passe temporaire refusee' $t.Statut 400

    if ($t.Statut -eq 200) {
        Write-Host '  LA SERRURE A LACHE - remise de demo1234 par l''API.' -ForegroundColor Red
        $remise = Appel 'PUT' '/user' @{ password = $demo } $t.Corps.access_token
        Write-Host ("  remise : {0}" -f $remise.Statut) -ForegroundColor Yellow
    }

    $f = Appel 'POST' '/factors' @{ factor_type = 'totp'; friendly_name = $temp } $jeton
    Verifie 'inscription TOTP refusee (reglage du tableau de bord)' $f.Statut 422

    if ($f.Statut -eq 200 -and $f.Corps.id) {
        Write-Host '  LE REGLAGE TOTP EST PERDU - facteur retire aussitot.' -ForegroundColor Red
        $retrait = Appel 'DELETE' "/factors/$($f.Corps.id)" $null $jeton
        Write-Host ("  retrait : {0}" -f $retrait.Statut) -ForegroundColor Yellow
    }
}

Write-Host ''
if ($echecs -eq 0) {
    Write-Host '--- La serrure tient : les deux boutons marchent, rien n''a bouge. ---' -ForegroundColor Green
    exit 0
} else {
    Write-Host "--- $echecs echec(s). ---" -ForegroundColor Red
    exit 1
}
