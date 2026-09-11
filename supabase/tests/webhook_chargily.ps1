<#
.SYNOPSIS
  Fabrique des événements Chargily SIGNÉS et les envoie au webhook déployé.

.DESCRIPTION
  Pourquoi ce script existe : la page de paiement Chargily n'est pas joignable
  depuis toutes les connexions algériennes. Le webhook, lui, n'a besoin de rien
  d'autre qu'un corps JSON et une signature HMAC — et la signature se calcule
  avec la même clé secrète, où qu'on soit.

  Ce n'est pas une simulation au rabais : le script signe avec la VRAIE clé, la
  fonction déployée vérifie cette signature comme elle vérifiera celle de
  Chargily, et la base traite l'événement par le même chemin. La seule chose
  qu'on ne voit pas, c'est le formulaire de carte.

  LA CLÉ N'EST PAS DANS CE FICHIER, et ne doit jamais y entrer. Elle est lue
  dans la variable d'environnement CHARGILY_SECRET_KEY, posée pour la seule
  durée de la session PowerShell. Ce fichier est versionné ; la clé, non.

  L'adresse du projet est lue dans env.json, à la racine du dépôt — le même
  fichier que l'application, et lui non plus n'est pas versionné.

.PARAMETER Cas
  Le scénario à jouer. « tout » les enchaîne dans l'ordre.

.EXAMPLE
  $env:CHARGILY_SECRET_KEY = 'test_sk_...'
  .\supabase\tests\webhook_chargily.ps1 -Cas tout
#>

[CmdletBinding()]
param(
    [ValidateSet('signature-invalide', 'sans-signature', 'paid', 'rejeu',
                 'montant', 'option-expiree', 'echec', 'inconnu', 'tout')]
    [string]$Cas = 'tout',

    # Le fichier de configuration de l'application, pour y lire SUPABASE_URL.
    [string]$EnvJson = (Join-Path $PSScriptRoot '..\..\env.json')
)

$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------------
# La clé, et l'adresse
# -----------------------------------------------------------------------------

$cle = $env:CHARGILY_SECRET_KEY
if ([string]::IsNullOrWhiteSpace($cle)) {
    Write-Host ''
    Write-Host 'CHARGILY_SECRET_KEY n''est pas posee dans cette session.' -ForegroundColor Red
    Write-Host ''
    Write-Host 'Posez-la pour la duree de la session, puis relancez :' -ForegroundColor Yellow
    Write-Host '    $env:CHARGILY_SECRET_KEY = ''test_sk_votre_cle''' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Elle ne doit etre ecrite dans aucun fichier du depot.' -ForegroundColor Yellow
    exit 1
}

if (-not (Test-Path $EnvJson)) {
    Write-Host "env.json introuvable ($EnvJson)." -ForegroundColor Red
    exit 1
}

$config = Get-Content $EnvJson -Raw | ConvertFrom-Json
$url = "$($config.SUPABASE_URL)/functions/v1/chargily-webhook"

Write-Host ''
Write-Host "Webhook : $url" -ForegroundColor Cyan
Write-Host ''

# -----------------------------------------------------------------------------
# Signer et envoyer
#
# LE CORPS EST SIGNE PUIS ENVOYE OCTET POUR OCTET. On convertit une seule fois
# la chaine en octets UTF-8 : ce sont ces octets-la qu'on signe, et ces
# octets-la qu'on poste. Signer une chaine puis laisser PowerShell la reencoder
# a sa facon donnerait une signature valide pour un corps qui n'est pas celui
# qui part.
# -----------------------------------------------------------------------------

function Send-Evenement {
    param(
        [Parameter(Mandatory)] [string]$Titre,
        [Parameter(Mandatory)] [string]$Type,
        [Parameter(Mandatory)] [string]$CheckoutId,
        [int]$Montant = 50000,
        # 'juste' signe correctement, 'fausse' envoie une signature inventee,
        # 'absente' n'en envoie aucune.
        [ValidateSet('juste', 'fausse', 'absente')] [string]$Signature = 'juste',
        [string]$Attendu
    )

    $evenement = [ordered]@{
        id         = "evt_test_$([guid]::NewGuid().ToString('N').Substring(0,20))"
        entity     = 'event'
        livemode   = $false
        type       = $Type
        data       = [ordered]@{
            id       = $CheckoutId
            entity   = 'checkout'
            amount   = $Montant
            currency = 'dzd'
            status   = $(if ($Type -eq 'checkout.paid') { 'paid' }
                         elseif ($Type -eq 'checkout.canceled') { 'canceled' }
                         else { 'failed' })
            fees     = 0
            metadata = $null
        }
        created_at = [int][double]::Parse((Get-Date -UFormat %s))
        updated_at = [int][double]::Parse((Get-Date -UFormat %s))
    }

    $corps  = $evenement | ConvertTo-Json -Depth 6 -Compress
    $octets = [System.Text.Encoding]::UTF8.GetBytes($corps)

    $entetes = @{}
    if ($Signature -ne 'absente') {
        if ($Signature -eq 'juste') {
            $hmac = [System.Security.Cryptography.HMACSHA256]::new(
                [System.Text.Encoding]::UTF8.GetBytes($cle))
            try {
                $signee = ($hmac.ComputeHash($octets) |
                           ForEach-Object { $_.ToString('x2') }) -join ''
            } finally {
                $hmac.Dispose()
            }
        } else {
            # Soixante-quatre caracteres hexadecimaux, comme une vraie — c'est
            # bien le CONTENU qui doit etre refuse, pas la longueur.
            $signee = 'a' * 64
        }
        $entetes['signature'] = $signee
    }

    Write-Host "-- $Titre" -ForegroundColor White
    Write-Host "   $Type  $CheckoutId  $Montant DA  (signature : $Signature)" -ForegroundColor DarkGray

    try {
        $reponse = Invoke-WebRequest -Uri $url -Method POST -Headers $entetes `
                                     -ContentType 'application/json' -Body $octets `
                                     -UseBasicParsing
        $code = $reponse.StatusCode
        $texte = $reponse.Content
    } catch {
        $reponseHttp = $_.Exception.Response
        if ($null -ne $reponseHttp) {
            $code = [int]$reponseHttp.StatusCode
            $lecteur = New-Object System.IO.StreamReader($reponseHttp.GetResponseStream())
            $texte = $lecteur.ReadToEnd()
        } else {
            Write-Host "   RESEAU : $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ''
            return
        }
    }

    $couleur = if ($Attendu -and ($texte -notlike "*$Attendu*") -and
                   ($code -ne [int]$Attendu)) { 'Red' } else { 'Green' }

    Write-Host "   HTTP $code  $texte" -ForegroundColor $couleur
    if ($Attendu) { Write-Host "   attendu : $Attendu" -ForegroundColor DarkGray }
    Write-Host ''
}

# -----------------------------------------------------------------------------
# Les scenarios
#
# L'ORDRE COMPTE pour « tout » : « rejeu » doit suivre « paid », sinon il n'y a
# rien a rejouer.
# -----------------------------------------------------------------------------

$scenarios = [ordered]@{
    'sans-signature' = {
        Send-Evenement -Titre 'Aucune signature : rien ne doit etre ecrit' `
            -Type 'checkout.paid' -CheckoutId 'wh_paid_001' `
            -Signature 'absente' -Attendu '401'
    }
    'signature-invalide' = {
        Send-Evenement -Titre 'Signature fausse : rien ne doit etre ecrit' `
            -Type 'checkout.paid' -CheckoutId 'wh_paid_001' `
            -Signature 'fausse' -Attendu '401'
    }
    'paid' = {
        Send-Evenement -Titre 'Paiement reussi : la reservation doit se confirmer' `
            -Type 'checkout.paid' -CheckoutId 'wh_paid_001' `
            -Attendu 'confirme'
    }
    'rejeu' = {
        Send-Evenement -Titre 'Le MEME evenement, rejoue : rien ne doit changer' `
            -Type 'checkout.paid' -CheckoutId 'wh_paid_001' `
            -Attendu 'deja_traite'
    }
    'montant' = {
        Send-Evenement -Titre 'Montant qui ne correspond pas : a examiner' `
            -Type 'checkout.paid' -CheckoutId 'wh_montant_001' -Montant 49000 `
            -Attendu 'montant_different'
    }
    'option-expiree' = {
        Send-Evenement -Titre 'Option expiree avant le paiement : a rembourser' `
            -Type 'checkout.paid' -CheckoutId 'wh_expiree_001' `
            -Attendu 'option_expiree'
    }
    'echec' = {
        Send-Evenement -Titre 'Paiement refuse : l''option doit survivre' `
            -Type 'checkout.failed' -CheckoutId 'wh_echec_001' `
            -Attendu 'echec'
    }
    'inconnu' = {
        Send-Evenement -Titre 'Un checkout que nous n''avons pas ouvert' `
            -Type 'checkout.paid' -CheckoutId 'wh_jamais_vu_999' `
            -Attendu 'inconnu'
    }
}

if ($Cas -eq 'tout') {
    foreach ($nom in $scenarios.Keys) { & $scenarios[$nom] }
    Write-Host 'Tous les cas ont ete envoyes.' -ForegroundColor Cyan
    Write-Host 'Executez maintenant la SECTION 2 de 013_webhook_bac_a_sable.sql.' -ForegroundColor Cyan
} else {
    & $scenarios[$Cas]
}

Write-Host ''
