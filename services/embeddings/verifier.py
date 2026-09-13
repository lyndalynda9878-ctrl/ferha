"""Vérifie le service sans le déployer — à lancer avant de pousser.

    python verifier.py

CE QU'IL CONTRÔLE, ET POURQUOI CHACUN :

  1. La surface HTTP. `/health` doit répondre SANS jeton — c'est le réveil de
     Render ; `/embed` doit refuser sans jeton, et refuser un mauvais jeton.
     Une erreur ici ouvre le service au premier passant.

  2. La forme des vecteurs : 384 nombres, de longueur 1. Le J19 déclarera
     `vector(384)` à pgvector, et un vecteur non normalisé ferait du produit
     scalaire autre chose qu'un cosinus.

  3. Le déterminisme. Deux appels, le même texte, le même vecteur — au bit
     près. Sans cela, réindexer les salles changerait leur place dans les
     résultats sans que rien n'ait bougé.

  4. Les deux préfixes donnent bien deux vecteurs différents. S'ils donnaient
     le même, c'est qu'ils ne seraient pas posés, et personne ne le verrait
     avant de lire des résultats « à peu près bons ».

  5. LE MULTILINGUE, qui est la raison d'être de ce service. Une question en
     français doit être plus proche de la même salle décrite en arabe que
     d'une salle sans rapport. C'est ce que la commande PowerShell du J18
     prouve sur le service déployé ; ici on le prouve en local.

  6. La mémoire, pas à pas. Render offre 512 Mo.
"""

from __future__ import annotations

import gc
import os
import sys
import time

# Un jeton de test, posé avant l'import : `app.py` le lit au chargement.
os.environ.setdefault("EMBED_TOKEN", "jeton-de-test-local")
JETON = os.environ["EMBED_TOKEN"]


def memoire_mo() -> float | None:
    """La mémoire résidente du processus, ou None si on ne sait pas la lire.

    On n'ajoute pas `psutil` pour ça : il ne servirait qu'ici, et il n'a rien à
    faire dans les dépendances d'un service qui tourne sur 512 Mo.
    """
    if sys.platform.startswith("linux"):
        # /proc/self/statm : la deuxième valeur est la RSS, en pages.
        with open("/proc/self/statm", encoding="ascii") as f:
            pages = int(f.read().split()[1])
        return pages * os.sysconf("SC_PAGE_SIZE") / 1e6

    if sys.platform == "win32":
        import ctypes
        from ctypes import wintypes

        taille = ctypes.c_size_t

        class PMC(ctypes.Structure):
            _fields_ = [
                ("cb", wintypes.DWORD),
                ("PageFaultCount", wintypes.DWORD),
                ("PeakWorkingSetSize", taille),
                ("WorkingSetSize", taille),
                ("QuotaPeakPagedPoolUsage", taille),
                ("QuotaPagedPoolUsage", taille),
                ("QuotaPeakNonPagedPoolUsage", taille),
                ("QuotaNonPagedPoolUsage", taille),
                ("PagefileUsage", taille),
                ("PeakPagefileUsage", taille),
            ]

        k32 = ctypes.WinDLL("kernel32", use_last_error=True)
        fn = k32.K32GetProcessMemoryInfo
        fn.argtypes = [wintypes.HANDLE, ctypes.POINTER(PMC), wintypes.DWORD]
        fn.restype = wintypes.BOOL
        k32.GetCurrentProcess.restype = wintypes.HANDLE

        c = PMC()
        c.cb = ctypes.sizeof(PMC)
        fn(k32.GetCurrentProcess(), ctypes.byref(c), c.cb)
        return c.WorkingSetSize / 1e6

    return None


def dire_memoire(etape: str) -> None:
    m = memoire_mo()
    print(f"   {etape:<44} {m:7.1f} Mo" if m else f"   {etape}")


echecs: list[str] = []


def verifier(condition: bool, quoi: str, detail: str = "") -> None:
    if condition:
        print(f"   ok    {quoi}")
    else:
        echecs.append(quoi)
        print(f"   ÉCHEC {quoi}   {detail}")


def main() -> int:
    print("=== MÉMOIRE, PAS À PAS ===")
    dire_memoire("python nu")

    import numpy as np
    from fastapi.testclient import TestClient

    import app as A

    dire_memoire("+ imports (onnxruntime, numpy, fastapi)")

    t0 = time.time()
    with TestClient(A.app) as client:
        charge = time.time() - t0
        gc.collect()
        dire_memoire("+ modèle chargé (sentencepiece + ONNX)")
        print(f"   {'chargement':<44} {charge:7.1f} s")

        # ------------------------------------------------------------------
        print("\n=== 1. LA SURFACE HTTP ===")
        r = client.get("/health")
        verifier(r.status_code == 200, "/health répond sans jeton", str(r.status_code))
        verifier(
            r.json().get("charge") is True,
            "/health dit que le modèle est chargé",
            r.text[:120],
        )

        corps = {"textes": ["essai"], "nature": "question"}
        verifier(
            client.post("/embed", json=corps).status_code == 401,
            "/embed sans jeton → 401",
        )
        verifier(
            client.post(
                "/embed", json=corps, headers={"Authorization": "Bearer faux"}
            ).status_code
            == 401,
            "/embed avec un mauvais jeton → 401",
        )
        verifier(
            client.post(
                "/embed", json=corps, headers={"Authorization": JETON}
            ).status_code
            == 401,
            "/embed sans le préfixe « Bearer » → 401",
        )

        entete = {"Authorization": f"Bearer {JETON}"}
        r = client.post("/embed", json=corps, headers=entete)
        verifier(r.status_code == 200, "/embed avec le bon jeton → 200", r.text[:200])

        verifier(
            client.post(
                "/embed",
                json={"textes": ["   "], "nature": "salle"},
                headers=entete,
            ).status_code
            == 400,
            "un texte vide → 400",
        )
        verifier(
            client.post(
                "/embed",
                json={"textes": ["x"] * (A.LOT_MAX + 1), "nature": "salle"},
                headers=entete,
            ).status_code
            == 422,
            f"plus de {A.LOT_MAX} textes → 422",
        )
        verifier(
            client.post(
                "/embed",
                json={"textes": ["x"], "nature": "autre chose"},
                headers=entete,
            ).status_code
            == 422,
            "une nature inconnue → 422",
        )

        # ------------------------------------------------------------------
        print("\n=== 2. LA FORME DES VECTEURS ===")

        def empreintes(textes: list[str], nature: str) -> np.ndarray:
            rep = client.post(
                "/embed",
                json={"textes": textes, "nature": nature},
                headers=entete,
            )
            rep.raise_for_status()
            return np.array(rep.json()["vecteurs"], dtype=np.float64)

        v = empreintes(["salle des fêtes à Oran"], "question")
        verifier(v.shape == (1, 384), "384 dimensions", str(v.shape))
        verifier(
            abs(float(np.linalg.norm(v[0])) - 1.0) < 1e-5,
            "vecteur de longueur 1",
            f"norme = {float(np.linalg.norm(v[0])):.6f}",
        )

        print("\n=== 3. DÉTERMINISME ===")
        a = empreintes(["Salle El Bahia, Oran, 450 couverts"], "salle")
        b = empreintes(["Salle El Bahia, Oran, 450 couverts"], "salle")
        verifier(
            float(np.abs(a - b).max()) == 0.0,
            "deux appels identiques donnent le même vecteur",
            f"écart max = {float(np.abs(a - b).max()):.2e}",
        )

        # Et l'ordre du lot ne change rien à ce que chacun reçoit.
        seuls = empreintes(["premier texte", "deuxième texte"], "salle")
        lot = empreintes(["deuxième texte", "premier texte"], "salle")
        verifier(
            float(np.abs(seuls[0] - lot[1]).max()) < 1e-6,
            "la place dans le lot ne change pas l'empreinte",
            f"écart max = {float(np.abs(seuls[0] - lot[1]).max()):.2e}",
        )

        print("\n=== 4. LES DEUX PRÉFIXES ===")
        q = empreintes(["salle des fêtes à Oran"], "question")
        p = empreintes(["salle des fêtes à Oran"], "salle")
        ecart = float(np.dot(q[0], p[0]))
        verifier(ecart < 0.999, "« query: » et « passage: » ne donnent pas le "
                 "même vecteur", f"cosinus = {ecart:.4f}")

        # ------------------------------------------------------------------
        print("\n=== 5. LE MULTILINGUE ===")
        question = "salle des fêtes à Oran pour un mariage"
        salles = [
            ("arabe standard", "قاعة أفراح في وهران"),
            ("français", "salle de mariage à Oran"),
            ("franco-arabe", "kayen salle f wahran l3ors"),
            ("HORS SUJET fr", "réparation de moteur diesel à Tamanrasset"),
            ("HORS SUJET ar", "إصلاح محرك السيارة"),
            ("HORS SUJET dz", "واش راه الطقس غدوة"),
        ]
        vq = empreintes([question], "question")[0]
        vs = empreintes([t for _, t in salles], "salle")

        scores = {}
        for (nom, txt), vec in zip(salles, vs):
            s = float(np.dot(vq, vec))
            scores[nom] = s
            print(f"   {s:.4f}  {nom:<14}  {txt}")

        pertinents = [s for n, s in scores.items() if not n.startswith("HORS")]
        hors = [s for n, s in scores.items() if n.startswith("HORS")]
        marge = min(pertinents) - max(hors)
        print(f"\n   pire pertinent {min(pertinents):.4f}   "
              f"meilleur hors-sujet {max(hors):.4f}   marge {marge:+.4f}")
        verifier(
            marge > 0,
            "toute salle pertinente passe devant tout hors-sujet",
            f"marge = {marge:+.4f}",
        )
        verifier(
            scores["arabe standard"] > max(hors),
            "l'arabe est compris comme le français",
            f"{scores['arabe standard']:.4f} contre {max(hors):.4f}",
        )

        # ------------------------------------------------------------------
        print("\n=== 6. LE TEMPS, ET LA MÉMOIRE SOUS CHARGE ===")
        t0 = time.time()
        empreintes(["une question courte"], "question")
        print(f"   {'une question courte':<44} {time.time() - t0:7.3f} s")

        quinze = [
            "Salle des fêtes climatisée à Oran, 400 couverts, parking fermé, "
            "cuisine équipée, chambre de la mariée, sono et DJ inclus, "
            "espace femmes séparé, jardin clos, groupe électrogène. " * 4
        ] * 15
        t0 = time.time()
        empreintes(quinze, "salle")
        print(f"   {'les 15 salles du J19, en un lot':<44} {time.time() - t0:7.3f} s")

        gros = quinze * 4 + quinze[:4]  # 64, le plafond
        t0 = time.time()
        empreintes(gros, "salle")
        print(f"   {'le plafond : 64 textes longs':<44} {time.time() - t0:7.3f} s")

        gc.collect()
        dire_memoire("APRÈS CHARGE")

    print()
    if echecs:
        print(f"### {len(echecs)} ÉCHEC(S) : " + " ; ".join(echecs))
        return 1
    print("### Tout est vert.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
