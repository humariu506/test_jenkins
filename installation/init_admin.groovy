// Exécuté au démarrage de Jenkins pendant l'installation (installation/installer.sh) :
// compte admin dont le mot de passe est lu dans admin_password.txt, accès réservé aux
// utilisateurs connectés, URL de Jenkins renseignée (obligatoire pour la CLI).
import jenkins.model.*
import hudson.security.*

def j = Jenkins.get()
def mdp = new File(j.rootDir, "admin_password.txt").text.trim()

def realm = j.getSecurityRealm() instanceof HudsonPrivateSecurityRealm ?
    j.getSecurityRealm() : new HudsonPrivateSecurityRealm(false)
def admin = realm.getUser("admin")
if (admin == null) {
    realm.createAccount("admin", mdp)
} else {
    admin.addProperty(HudsonPrivateSecurityRealm.Details.fromPlainPassword(mdp))
    admin.save()
}
j.setSecurityRealm(realm)

def auth = new FullControlOnceLoggedInAuthorizationStrategy()
auth.setAllowAnonymousRead(false)
j.setAuthorizationStrategy(auth)

j.setInstallState(jenkins.install.InstallState.INITIAL_SETUP_COMPLETED)
JenkinsLocationConfiguration.get().setUrl("http://localhost:8080/")
j.save()
