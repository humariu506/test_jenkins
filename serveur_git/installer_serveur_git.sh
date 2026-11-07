#!/bin/bash
# Installation du serveur git local (option 2) sur Ubuntu / Debian (ou WSL Ubuntu).
#
# Usage (depuis la racine du dépôt) :
#   sudo bash serveur_git/installer_serveur_git.sh [cle_publique_dev.pub ...]
#
# Les clés publiques passées en argument sont autorisées à pousser sur le dépôt
# (ex : la clé du poste de développement). La clé de l'utilisateur jenkins est
# ajoutée automatiquement si Jenkins est installé sur la machine.
# Le script peut être relancé sans risque : il ne refait que ce qui manque.

set -e

GIT_USER="git"
GIT_HOME="/home/$GIT_USER"
DEPOT="/srv/git/tri_bulles.git"
GITHUB_URL="${GITHUB_URL:-https://github.com/humariu506/test_jenkins.git}"
JENKINS_HOME="${JENKINS_HOME:-/var/lib/jenkins}"
DOSSIER_SCRIPT="$(cd "$(dirname "$0")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
    echo "À lancer avec sudo." >&2
    exit 1
fi

echo "==> Paquets : openssh-server, git"
apt-get update -qq
apt-get install -y -qq openssh-server git curl

echo "==> Utilisateur $GIT_USER (shell git-shell : uniquement des commandes git)"
GIT_SHELL="$(command -v git-shell)"
grep -qx "$GIT_SHELL" /etc/shells || echo "$GIT_SHELL" >> /etc/shells
if ! id "$GIT_USER" >/dev/null 2>&1; then
    useradd --create-home --home-dir "$GIT_HOME" --shell "$GIT_SHELL" "$GIT_USER"
fi
install -d -m 700 -o "$GIT_USER" -g "$GIT_USER" "$GIT_HOME/.ssh"
touch "$GIT_HOME/.ssh/authorized_keys"

echo "==> Dépôt nu $DEPOT"
if [ ! -d "$DEPOT" ]; then
    mkdir -p "$(dirname "$DEPOT")"
    # On part de l'historique GitHub pour que les deux dépôts soient identiques
    git clone --bare "$GITHUB_URL" "$DEPOT" || git init --bare --initial-branch=main "$DEPOT"
fi
install -m 755 "$DOSSIER_SCRIPT/post-receive" "$DEPOT/hooks/post-receive"
chown -R "$GIT_USER:$GIT_USER" "$(dirname "$DEPOT")"

echo "==> Clé SSH de $GIT_USER (utilisée par le hook pour appeler Jenkins)"
if [ ! -f "$GIT_HOME/.ssh/id_ed25519" ]; then
    sudo -u "$GIT_USER" ssh-keygen -q -t ed25519 -N "" -C "git-hook" -f "$GIT_HOME/.ssh/id_ed25519"
fi

ajouter_cle() {
    if ! grep -qF "$(cat "$1")" "$GIT_HOME/.ssh/authorized_keys"; then
        cat "$1" >> "$GIT_HOME/.ssh/authorized_keys"
        echo "    clé ajoutée : $1"
    fi
}

if [ -d "$JENKINS_HOME" ]; then
    echo "==> Clé SSH de l'utilisateur jenkins (utilisée pour cloner le dépôt)"
    install -d -m 700 -o jenkins -g jenkins "$JENKINS_HOME/.ssh"
    if [ ! -f "$JENKINS_HOME/.ssh/id_ed25519" ]; then
        sudo -u jenkins ssh-keygen -q -t ed25519 -N "" -C "jenkins" -f "$JENKINS_HOME/.ssh/id_ed25519"
    fi
    ajouter_cle "$JENKINS_HOME/.ssh/id_ed25519.pub"
else
    echo "    $JENKINS_HOME absent : installer Jenkins puis relancer ce script."
fi

for cle in "$@"; do
    ajouter_cle "$cle"
done
chown "$GIT_USER:$GIT_USER" "$GIT_HOME/.ssh/authorized_keys"
chmod 600 "$GIT_HOME/.ssh/authorized_keys"

echo "==> Démarrage du serveur SSH"
if [ -d /run/systemd/system ]; then
    systemctl enable --now ssh
else
    service ssh start   # WSL sans systemd
fi

if [ -d "$JENKINS_HOME" ]; then
    # Empreinte du serveur connue de jenkins : pas de question au premier clone
    sudo -u jenkins bash -c "ssh-keyscan -H localhost >> $JENKINS_HOME/.ssh/known_hosts 2>/dev/null"
fi

cat <<EOF

Serveur git prêt.
  URL du dépôt : $GIT_USER@localhost:$DEPOT

À faire dans Jenkins (détail dans serveur_git/README.md) :
  1. Activer le serveur SSH de Jenkins sur le port 2222.
  2. Créer l'utilisateur Jenkins "git-hook" et lui coller cette clé publique :
     $(cat "$GIT_HOME/.ssh/id_ed25519.pub")
  3. Créer l'identifiant "serveur-git-local" (SSH Username with private key,
     utilisateur "$GIT_USER") avec la clé privée $JENKINS_HOME/.ssh/id_ed25519
EOF
