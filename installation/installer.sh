#!/bin/bash
# Installation complète du projet sur un nouveau poste Ubuntu / Debian (ou WSL Ubuntu) :
# outils de compilation, Jenkins configuré (plugins, sécurité, SSH, jobs), serveur git
# local avec son hook, dossier de production, puis un premier build de chaque job.
#
# Usage (depuis la racine du dépôt) :
#   sudo bash installation/installer.sh [cle_publique_dev.pub ...]
#
# Les clés passées en argument pourront pousser sur le serveur git local
# (sous WSL, la clé Windows est dans /mnt/c/Users/<nom>/.ssh/id_ed25519.pub).
# Le script peut être relancé : il ne refait que ce qui manque.

set -eo pipefail

GITHUB_URL="${GITHUB_URL:-https://github.com/humariu506/test_jenkins.git}"
BRANCHE="${BRANCHE:-main}"
JH=/var/lib/jenkins
URL=http://localhost:8080
DOSSIER="$(cd "$(dirname "$0")" && pwd)"
RACINE="$(dirname "$DOSSIER")"
CLI_JAR=/var/lib/jenkins-cli.jar
PLUGINS="workflow-aggregator git credentials ssh-credentials ws-cleanup sshd pipeline-graph-view"

if [ "$(id -u)" -ne 0 ]; then
    echo "À lancer avec sudo." >&2
    exit 1
fi

etape() { echo; echo "==> $*"; }

attendre_jenkins() {
    for _ in $(seq 100); do
        [ "$(curl -s -o /dev/null -w '%{http_code}' $URL/login)" = "200" ] && return 0
        sleep 3
    done
    echo "Jenkins ne répond pas sur $URL" >&2
    exit 1
}

cli() {
    java -jar "$CLI_JAR" -s "$URL" -auth "admin:$(cat $JH/admin_password.txt)" "$@"
}

etape "Paquets : Java 21, outils de compilation et de profilage"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg fontconfig openjdk-21-jre-headless \
    gcc make valgrind libc6-dbg binutils file git openssh-server >/dev/null

etape "Jenkins (dépôt officiel pkg.jenkins.io)"
if ! dpkg -s jenkins >/dev/null 2>&1; then
    install -d /etc/apt/keyrings
    for cle in jenkins.io-2026.key jenkins.io-2023.key; do
        curl -fsSL "https://pkg.jenkins.io/debian-stable/$cle" -o /etc/apt/keyrings/jenkins-keyring.asc && break
    done
    echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
        > /etc/apt/sources.list.d/jenkins.list
    apt-get update -qq
    apt-get install -y -qq jenkins >/dev/null
fi
dpkg -s jenkins | grep '^Version'

etape "Compte admin et assistant d'installation désactivé"
systemctl stop jenkins
mkdir -p /etc/systemd/system/jenkins.service.d
cat > /etc/systemd/system/jenkins.service.d/override.conf <<'EOF'
[Service]
Environment="JAVA_OPTS=-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false"
EOF
if [ ! -s $JH/admin_password.txt ]; then
    head -c 32 /dev/urandom | base64 | tr -dc A-Za-z0-9 | head -c 16 > $JH/admin_password.txt
fi
chown jenkins:jenkins $JH/admin_password.txt
chmod 600 $JH/admin_password.txt
# Script exécuté au démarrage de Jenkins, supprimé à la fin de l'installation
install -d -o jenkins -g jenkins $JH/init.groovy.d
install -m 644 -o jenkins -g jenkins "$DOSSIER/init_admin.groovy" $JH/init.groovy.d/01-admin.groovy
systemctl daemon-reload
systemctl enable --now jenkins
systemctl restart jenkins
attendre_jenkins
curl -fsS -o "$CLI_JAR" $URL/jnlpJars/jenkins-cli.jar
cli who-am-i | head -1

etape "Plugins : $PLUGINS"
cli install-plugin $PLUGINS -deploy | grep -v "^Installing" || true
systemctl restart jenkins
attendre_jenkins

etape "Serveur git local"
JENKINS_HOME=$JH GITHUB_URL="$GITHUB_URL" bash "$RACINE/serveur_git/installer_serveur_git.sh" "$@" | sed -n '/^==>/p;/clé ajoutée/p'

etape "Configuration de Jenkins : serveur SSH, utilisateur git-hook, identifiant, vérification d'hôte"
cli groovy = "$(cat /home/git/.ssh/id_ed25519.pub)" < "$DOSSIER/configurer_jenkins.groovy"

etape "Jobs"
creer_job() { # nom url identifiant jenkinsfile description
    local cred=""
    [ -n "$3" ] && cred="<credentialsId>$3</credentialsId>"
    sed -e "s|__URL__|$2|" -e "s|__CRED__|$cred|" -e "s|__SCRIPT__|$4|" \
        -e "s|__DESC__|$5|" -e "s|__BRANCHE__|$BRANCHE|" "$DOSSIER/job.xml" > /tmp/job_$1.xml
    if cli get-job "$1" >/dev/null 2>&1; then
        cli update-job "$1" < /tmp/job_$1.xml
    else
        cli create-job "$1" < /tmp/job_$1.xml
    fi
    rm -f /tmp/job_$1.xml
    echo "    $1"
}
creer_job tri-dev       "$GITHUB_URL"                          ""                  Jenkinsfile.dev     "Dev/Tests depuis GitHub (scrutation)"
creer_job tri-dev-local "git@localhost:/srv/git/tri_bulles.git" serveur-git-local Jenkinsfile.dev     "Dev/Tests depuis le serveur git local (hook post-receive en SSH)"
creer_job tri-preprod   "$GITHUB_URL"                          ""                  Jenkinsfile.preprod "Pré-production : tests et profilage valgrind/gprof"
creer_job tri-prod      "$GITHUB_URL"                          ""                  Jenkinsfile.prod    "Production : make clean, strip, make install"

etape "Dossier de production /var/www/app_tri"
install -d -o jenkins -g jenkins /var/www/app_tri

etape "Vérification : le hook peut joindre Jenkins en SSH"
for _ in $(seq 20); do
    sudo -u git ssh -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=accept-new git-hook@localhost who-am-i 2>/dev/null \
        | head -1 && break
    sleep 3
done

etape "Premier build de chaque job (enregistre le paramètre COMMIT et les déclencheurs pollSCM)"
echo "    (pré-prod : profilage valgrind, compter quelques minutes)"
# Pré-prod et prod d'abord : tri-dev leur passe le paramètre COMMIT, qu'elles doivent déjà connaître
for job in tri-preprod tri-prod tri-dev-local tri-dev; do
    echo "    $(cli build "$job" -s 2>&1 | tail -1)"
done
echo "    tri-dev vert : la chaîne tri-preprod puis tri-prod continue en arrière-plan"

# Le mot de passe admin reste celui du fichier ; on peut le changer ensuite dans Jenkins
rm -f $JH/init.groovy.d/01-admin.groovy

cat <<EOF

Installation terminée.
  Jenkins         : $URL   (utilisateur admin)
  Mot de passe    : sudo cat $JH/admin_password.txt
  Serveur git     : git@localhost:/srv/git/tri_bulles.git
  Production      : /var/www/app_tri/bin/tri_bulles

Pousser vers GitHub et le serveur local en une commande : voir README.md, étape 4.
EOF
