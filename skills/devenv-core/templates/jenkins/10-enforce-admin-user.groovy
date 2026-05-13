import hudson.model.User
import hudson.security.FullControlOnceLoggedInAuthorizationStrategy
import hudson.security.HudsonPrivateSecurityRealm
import jenkins.model.Jenkins

def env = System.getenv()
def adminUser = env.getOrDefault("JENKINS_ADMIN_USER", "admin")
def adminPassword = env.get("JENKINS_ADMIN_PASSWORD")

if (adminPassword == null || adminPassword.trim().isEmpty()) {
  println("[devenv-init] JENKINS_ADMIN_PASSWORD is empty; skip enforcement")
  return
}

def jenkins = Jenkins.get()
def realm = jenkins.getSecurityRealm()
if (!(realm instanceof HudsonPrivateSecurityRealm)) {
  realm = new HudsonPrivateSecurityRealm(false)
  jenkins.setSecurityRealm(realm)
  println("[devenv-init] securityRealm replaced with HudsonPrivateSecurityRealm")
}

def existing = User.getById(adminUser, false)
if (existing == null) {
  realm.createAccount(adminUser, adminPassword)
  println("[devenv-init] admin user created: ${adminUser}")
} else {
  existing.addProperty(HudsonPrivateSecurityRealm.Details.fromPlainPassword(adminPassword))
  existing.save()
  println("[devenv-init] admin password synchronized: ${adminUser}")
}

def auth = jenkins.getAuthorizationStrategy()
if (!(auth instanceof FullControlOnceLoggedInAuthorizationStrategy)) {
  def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
  strategy.setAllowAnonymousRead(false)
  jenkins.setAuthorizationStrategy(strategy)
  println("[devenv-init] authorization strategy set to authenticated-only")
}

jenkins.save()
println("[devenv-init] Jenkins admin enforcement done")
