# Option 2 : serveur git local relié à Jenkins en SSH

Un dépôt nu `/srv/git/tri_bulles.git` est hébergé sur la machine par un utilisateur
`git` et servi par `sshd`. Jenkins clone ce dépôt en SSH, et le hook `post-receive`
du dépôt lance le pipeline Dev à chaque push, lui aussi en SSH (CLI SSH intégrée à
Jenkins). Aucun service tiers n'intervient.

```
poste de dev ──git push (ssh)──> git@localhost:/srv/git/tri_bulles.git
                                        │ hook post-receive
                                        └──ssh -p 2222──> Jenkins : build tri-dev-local
Jenkins (job tri-dev-local) ──git clone (ssh, clé jenkins)──> dépôt nu
```

Fichiers :

| Fichier | Rôle |
|---|---|
| `installer_serveur_git.sh` | Crée l'utilisateur `git`, le dépôt nu, les clés SSH, installe le hook et démarre `sshd` |
| `post-receive` | Hook copié dans `/srv/git/tri_bulles.git/hooks/` ; déclenche Jenkins sur un push vers `main` |

Les commandes ci-dessous sont à lancer dans Ubuntu (machine Linux ou WSL).

> `installation/installer.sh` fait automatiquement les étapes 1 à 3 ci-dessous
> (voir le [README principal](../README.md)). Elles sont détaillées ici pour comprendre
> le montage ou le refaire à la main.

## 1. Prérequis : Jenkins et outils de compilation

Installer Jenkins en suivant https://www.jenkins.io/doc/book/installing/linux/
(paquet Debian/Ubuntu, Java 21), puis les outils utilisés par les pipelines :

```bash
sudo apt-get install -y gcc make valgrind libc6-dbg binutils file git
# Dossier d'installation du pipeline Prod
sudo mkdir -p /var/www/app_tri && sudo chown jenkins:jenkins /var/www/app_tri
```

Plugins Jenkins nécessaires (installés avec les plugins suggérés) : Git, Pipeline,
Credentials, SSH Server, Workspace Cleanup.

## 2. Installer le serveur git

Depuis la racine du dépôt, en passant la clé publique du poste qui va pousser :

```bash
# Sous WSL, la clé Windows est visible dans /mnt/c/Users/<nom>/.ssh/
sudo bash serveur_git/installer_serveur_git.sh ~/.ssh/id_ed25519.pub
```

Pas de clé ? `ssh-keygen -t ed25519` d'abord. Le script :

- installe `openssh-server` et `git` ;
- crée l'utilisateur `git` avec `git-shell` comme shell (il ne peut lancer que des
  commandes git, pas ouvrir de session) ;
- crée `/srv/git/tri_bulles.git` à partir de l'historique GitHub et y installe le hook ;
- génère une clé pour `jenkins` (clonage) et une pour `git` (appel de Jenkins par le hook) ;
- autorise la clé de `jenkins` et les clés passées en argument dans `~git/.ssh/authorized_keys` ;
- ajoute l'empreinte du serveur dans `known_hosts` de `jenkins` ;
- affiche à la fin la clé publique de `git` à coller dans Jenkins (étape 3).

Vérification : `ssh git@localhost` doit répondre
`fatal: Interactive git shell is not enabled.` (la connexion fonctionne, le shell est restreint).

## 3. Configurer Jenkins

1. **Serveur SSH de Jenkins** : *Administrer Jenkins > Sécurité > Serveur SSH* :
   port fixe `2222`.
2. **Utilisateur du hook** : *Administrer Jenkins > Utilisateurs > Créer* `git-hook`,
   puis dans *git-hook > Security > SSH Public Keys*, coller la clé affichée par le
   script (`sudo cat /home/git/.ssh/id_ed25519.pub`). Il lui faut au moins les droits
   *Overall/Read*, *Job/Read* et *Job/Build*.
3. **Identifiant de clonage** : *Administrer Jenkins > Credentials > System > Global >
   Add Credentials* :
   - Kind : *SSH Username with private key*
   - ID : `serveur-git-local`
   - Username : `git`
   - Private Key : contenu de `sudo cat /var/lib/jenkins/.ssh/id_ed25519`
4. **Vérification de l'hôte** : *Administrer Jenkins > Sécurité > Git Host Key
   Verification Configuration* : *Known hosts file* (rempli par le script).
5. **Jobs** (type *Pipeline*, *Pipeline script from SCM*, branche `*/main`) :

| Job | Dépôt | Identifiant | Script Path |
|---|---|---|---|
| `tri-dev` | `https://github.com/humariu506/test_jenkins.git` | aucun | `Jenkinsfile.dev` |
| `tri-dev-local` | `git@localhost:/srv/git/tri_bulles.git` | `serveur-git-local` | `Jenkinsfile.dev` |
| `tri-preprod` | `https://github.com/humariu506/test_jenkins.git` | aucun | `Jenkinsfile.preprod` |
| `tri-prod` | `https://github.com/humariu506/test_jenkins.git` | aucun | `Jenkinsfile.prod` |

Lancer chaque job **une fois à la main** : c'est ce premier build qui enregistre le
bloc `triggers { pollSCM(...) }` des Jenkinsfiles.

Test du hook sans pousser :

```bash
sudo -u git ssh -p 2222 git-hook@localhost who-am-i   # doit afficher "Authenticated as: git-hook"
```

## 4. Pousser vers GitHub et le serveur local en une commande

Dans le clone de travail, on donne deux adresses de push à `origin` (la première
remplace l'adresse par défaut, il faut donc remettre GitHub) :

```bash
git remote set-url --add --push origin https://github.com/humariu506/test_jenkins.git
git remote set-url --add --push origin git@localhost:/srv/git/tri_bulles.git
git remote -v
```

Ensuite, un simple `git push` met à jour les deux dépôts :

- le serveur local répond aussitôt `remote: Pipeline 'tri-dev-local' lancé.` ;
- `tri-dev` part dans les 5 minutes (scrutation GitHub), puis `tri-preprod` et `tri-prod`
  s'enchaînent si chaque étape est verte.

## Méthode alternative : notification HTTP

Si on ne veut pas activer le serveur SSH de Jenkins, créer
`/srv/git/tri_bulles.git/hooks/jenkins.env` contenant :

```bash
METHODE="curl"
```

Le hook appelle alors `http://localhost:8080/git/notifyCommit?url=...` (plugin Git)
et Jenkins relance tout job dont l'URL de dépôt correspond et qui a la scrutation
activée. Les autres variables du hook (`JENKINS_HOST`, `JENKINS_JOB`, `BRANCHE`...)
se surchargent dans ce même fichier.

## Dépannage

| Symptôme | Cause probable |
|---|---|
| `Permission denied (publickey)` au push | clé du poste absente de `/home/git/.ssh/authorized_keys` : relancer le script avec la clé |
| `remote: ATTENTION : impossible de joindre Jenkins (code 255)` | serveur SSH de Jenkins désactivé, mauvais port, ou clé de `git` non collée dans l'utilisateur `git-hook` |
| Job `tri-dev-local` en échec au checkout | identifiant `serveur-git-local` absent ou `known_hosts` de `jenkins` vide (relancer le script) |
| WSL : `Connection refused` sur le port 22 ou 2222 | WSL arrête Ubuntu quelques secondes après la fermeture du dernier terminal. Garder un terminal Ubuntu ouvert ; au redémarrage, Jenkins met ~30 s à rouvrir le port 2222 |
