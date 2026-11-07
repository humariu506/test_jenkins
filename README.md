# Chaîne CI/CD avec Jenkins : tri à bulles en C

Projet BUT3 Qualité de développement (IUT Gustave Eiffel, L. Tran).
Un programme C de tri à bulles passe par quatre pipelines Jenkins : Dev/Tests,
Pré-prod (profilage Valgrind et gprof) et Prod (strip et `make install`). Ils sont
déclenchés par GitHub et par notre propre serveur git, joint directement en SSH.
Le tronc commun et les deux options du sujet sont réalisés.

```
poste de dev ── git push ──┬──> GitHub ──(scrutation 5 min)──> tri-dev, tri-preprod, tri-prod
                           └──> serveur git local ──(hook en SSH)──> tri-dev-local
                                                       tri-prod ──> /var/www/app_tri
```

## Démarrage rapide sur un nouveau PC

Tout s'installe dans Ubuntu : un PC Linux, ou WSL 2 sous Windows. Compter 10 à 15 minutes.

### 1. Ubuntu (Windows seulement)

Dans PowerShell **en administrateur**, puis redémarrer et créer l'utilisateur Ubuntu demandé :

```powershell
wsl --install -d Ubuntu
```

### 2. Récupérer le dépôt et une clé SSH

Sous Windows (Git Bash ou PowerShell), ou directement dans Ubuntu sur un PC Linux :

```bash
git clone https://github.com/humariu506/test_jenkins.git
ssh-keygen -t ed25519      # seulement s'il n'existe pas déjà ~/.ssh/id_ed25519
```

### 3. Tout installer

Dans un terminal **Ubuntu**, depuis le dossier du dépôt :

```bash
# Sous WSL, le disque Windows est dans /mnt/c (adapter le chemin et <nom>)
cd "/mnt/c/Users/<nom>/Desktop/project tran/test_jenkins"
sudo bash installation/installer.sh /mnt/c/Users/<nom>/.ssh/id_ed25519.pub

# Sur un PC Linux :
sudo bash installation/installer.sh ~/.ssh/id_ed25519.pub
```

La clé passée en argument est celle du poste qui poussera sur le serveur git local.
Le script peut être relancé sans risque. Il installe et configure :

| Élément | Détail |
|---|---|
| Outils | Java 21, gcc, make, valgrind, libc6-dbg, gprof, strip, git, OpenSSH |
| Jenkins | assistant désactivé, compte `admin`, plugins (Pipeline, Git, SSH server, Workspace Cleanup) |
| Serveur git | utilisateur `git` (git-shell), dépôt nu `/srv/git/tri_bulles.git`, hook `post-receive` |
| SSH | clé de `jenkins` (clonage), clé de `git` (appel de Jenkins), serveur SSH de Jenkins sur le port 2222, utilisateur `git-hook`, identifiant `serveur-git-local` |
| Jobs | `tri-dev`, `tri-dev-local`, `tri-preprod`, `tri-prod`, chacun lancé une première fois |
| Production | dossier `/var/www/app_tri` accessible en écriture à `jenkins` |

À la fin, ouvrir http://localhost:8080 et se connecter en `admin`. Le mot de passe :

```bash
sudo cat /var/lib/jenkins/admin_password.txt
```

### 4. Pousser vers GitHub et le serveur local en une commande

Dans le clone de travail (celui de l'étape 2) :

```bash
git remote set-url --add --push origin https://github.com/humariu506/test_jenkins.git
git remote set-url --add --push origin git@localhost:/srv/git/tri_bulles.git
git remote -v    # deux lignes (push) attendues
```

Ensuite, chaque `git push` sur `main` :

- lance tout de suite `tri-dev-local` : le serveur répond `remote: Pipeline 'tri-dev-local' lancé.` ;
- lance `tri-dev`, `tri-preprod` et `tri-prod` dans les 5 minutes (scrutation de GitHub).

Pour pousser sur GitHub, le compte doit être collaborateur du dépôt.

### 5. Sous WSL : garder Ubuntu allumé

WSL arrête Ubuntu quelques secondes après la fermeture du dernier terminal, ce qui coupe
Jenkins et le serveur git. Garder un terminal Ubuntu ouvert pendant le travail. Au
redémarrage, Jenkins met environ 30 secondes à revenir.

## Contenu du dépôt

| Fichier | Rôle |
|---|---|
| `tri_bulles.c`, `tri.h` | Fonction de tri à bulles |
| `main.c` | Programme : `tri_bulles 5 2 8 1 3` ou `tri_bulles -r N` (N entiers aléatoires) |
| `test_tri.c` | Tests unitaires |
| `Makefile` | `all`, `test`, `strip`, `install`, `clean`, `distclean`, `debug`, `memcheck`, `callgrind`, `massif`, `gprof` |
| `Jenkinsfile.dev` | Compilation et tests (jobs `tri-dev` et `tri-dev-local`) |
| `Jenkinsfile.preprod` | Build debug, tests, Valgrind (memcheck, callgrind, massif), gprof, benchmark ; rapports archivés |
| `Jenkinsfile.prod` | Build release, tests, `make clean`, `strip`, `make install` dans `/var/www/app_tri` |
| `installation/` | Installation complète du poste (`installer.sh`) et configuration de Jenkins |
| `serveur_git/` | Serveur git local : script d'installation, hook `post-receive`, documentation détaillée |
| `docs/` | Présentation du projet |

Fonctionnement détaillé du serveur git et dépannage : [serveur_git/README.md](serveur_git/README.md).

## Utilisation sans Jenkins

```bash
make            # compile tri_bulles
make test       # compile et lance les tests
./tri_bulles 5 2 8 1 3
make install PREFIX=$HOME/app_tri
```
