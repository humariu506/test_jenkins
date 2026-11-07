// Lancé par installation/installer.sh via : jenkins-cli groovy = "<clé publique de git>"
import jenkins.model.*
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.domains.Domain
import com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey
import org.jenkinsci.plugins.gitclient.GitHostKeyVerificationConfiguration
import org.jenkinsci.plugins.gitclient.verifier.KnownHostsFileVerificationStrategy

def j = Jenkins.get()
def clePubHook = args[0]

// Serveur SSH intégré de Jenkins : le hook post-receive l'appelle sur ce port
def sshd = org.jenkinsci.main.modules.sshd.SSHD.get()
sshd.setPort(2222)
sshd.save()

// Utilisateur Jenkins qui porte la clé publique de l'utilisateur système "git"
def realm = j.getSecurityRealm()
def hook = realm.getUser("git-hook") ?: realm.createAccount("git-hook", UUID.randomUUID().toString())
hook.setFullName("Hook post-receive du serveur git")
hook.addProperty(new org.jenkinsci.main.modules.cli.auth.ssh.UserPropertyImpl(clePubHook))
hook.save()

// Identifiant utilisé par le job tri-dev-local pour cloner le serveur git en SSH
def store = SystemCredentialsProvider.getInstance().getStore()
def ancien = CredentialsProvider.lookupCredentialsInItemGroup(BasicSSHUserPrivateKey, j, null, null)
    .find { it.id == "serveur-git-local" }
if (ancien) store.removeCredentials(Domain.global(), ancien)
def clePrivee = new File(j.rootDir, ".ssh/id_ed25519").text
store.addCredentials(Domain.global(), new BasicSSHUserPrivateKey(
    CredentialsScope.GLOBAL, "serveur-git-local", "git",
    new BasicSSHUserPrivateKey.DirectEntryPrivateKeySource(clePrivee), null,
    "Serveur git local (clé de l'utilisateur jenkins)"))

// Empreinte du serveur vérifiée avec ~jenkins/.ssh/known_hosts
def hk = GlobalConfiguration.all().get(GitHostKeyVerificationConfiguration)
hk.setSshHostKeyVerificationStrategy(new KnownHostsFileVerificationStrategy())
hk.save()

j.save()
println "    SSH Jenkins : port ${sshd.getActualPort()}, utilisateur git-hook, identifiant serveur-git-local"
