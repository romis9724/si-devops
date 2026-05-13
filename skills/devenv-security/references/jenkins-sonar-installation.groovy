// SonarQube Jenkins 플러그인 — SonarGlobalConfiguration + SonarInstallation (9-arg)
// 4번째 인자는 hudson.util.Secret 이므로 Groovy에서 null을 넘길 때 (Secret) null 캐스팅 필수.
// 설치 배열은 Array.newInstance 로 생성 (zsh/bash에서 복사해 scriptText로 넣을 때도 안전).

import hudson.plugins.sonar.SonarGlobalConfiguration
import hudson.plugins.sonar.SonarInstallation
import hudson.plugins.sonar.model.TriggersConfig
import hudson.util.Secret
import jenkins.model.Jenkins
import java.lang.reflect.Array

final String NAME = System.getenv("SONAR_NAME") ?: "sonarqube"
final String URL = System.getenv("SONAR_URL") ?: "http://sonarqube:9000"
final String CRED_ID = System.getenv("SONAR_CREDENTIALS_ID") ?: "sonar-token"

def descriptor = Jenkins.instance.getDescriptorByType(SonarGlobalConfiguration.class)
def triggers = new TriggersConfig()
Secret tokenArg = (Secret) null

SonarInstallation[] before = descriptor.getInstallations()
def kept = (before as List).findAll { it.getName() != NAME }

SonarInstallation[] merged = Array.newInstance(SonarInstallation, kept.size() + 1) as SonarInstallation[]
int i = 0
for (SonarInstallation s : kept) {
  merged[i++] = s
}
merged[i] = new SonarInstallation(
  NAME,
  URL,
  CRED_ID,
  tokenArg,
  "",
  "",
  "",
  "",
  triggers
)

descriptor.setInstallations(merged)
descriptor.save()
println("SonarInstallation idempotent upsert: " + NAME)

// --- Introspection (버전 불일치 시 constructor 확인용) ---
// hudson.plugins.sonar.SonarInstallation.class.getDeclaredConstructors().each {
//   println it.parameterTypes*.simpleName.join(", ")
// }
