import com.cloudbees.plugins.credentials.CredentialsScope
import com.cloudbees.plugins.credentials.SystemCredentialsProvider
import com.cloudbees.plugins.credentials.domains.Domain
import com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl
import hudson.model.User
import hudson.plugins.git.BranchSpec
import hudson.plugins.git.GitSCM
import hudson.security.FullControlOnceLoggedInAuthorizationStrategy
import hudson.security.HudsonPrivateSecurityRealm
import hudson.util.Secret
import jenkins.model.Jenkins
import org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl
import org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition
import org.jenkinsci.plugins.workflow.job.WorkflowJob

def requiredEnvironment = [
  'JENKINS_ADMIN_USER',
  'JENKINS_ADMIN_PASSWORD',
  'DOCKERHUB_USERNAME',
  'DOCKERHUB_TOKEN',
  'MYSQL_ROOT_PASSWORD',
  'MYSQL_PASSWORD',
  'GITHUB_REPOSITORY_URL',
  'JENKINS_JOB_NAME'
]

def missingEnvironment = requiredEnvironment.findAll { !System.getenv(it)?.trim() }
if (missingEnvironment) {
  throw new IllegalStateException("Missing Jenkins bootstrap environment variables: ${missingEnvironment.join(', ')}")
}

def jenkins = Jenkins.get()
def adminUser = System.getenv('JENKINS_ADMIN_USER')
def adminPassword = System.getenv('JENKINS_ADMIN_PASSWORD')

if (!(jenkins.securityRealm instanceof HudsonPrivateSecurityRealm)) {
  def realm = new HudsonPrivateSecurityRealm(false, false, null)
  realm.createAccount(adminUser, adminPassword)
  jenkins.setSecurityRealm(realm)
  jenkins.setAuthorizationStrategy(new FullControlOnceLoggedInAuthorizationStrategy())
} else if (User.getById(adminUser, false) == null) {
  jenkins.securityRealm.createAccount(adminUser, adminPassword)
}

def credentialStore = SystemCredentialsProvider.getInstance().getStore()
def globalDomain = Domain.global()
def desiredCredentials = [
  new UsernamePasswordCredentialsImpl(
    CredentialsScope.GLOBAL,
    'dockerhub-creds',
    'Docker Hub image push credential',
    System.getenv('DOCKERHUB_USERNAME'),
    System.getenv('DOCKERHUB_TOKEN')
  ),
  new StringCredentialsImpl(
    CredentialsScope.GLOBAL,
    'mysql-root-password',
    'MySQL root password for deployment',
    Secret.fromString(System.getenv('MYSQL_ROOT_PASSWORD'))
  ),
  new StringCredentialsImpl(
    CredentialsScope.GLOBAL,
    'mysql-app-password',
    'MySQL application password for deployment',
    Secret.fromString(System.getenv('MYSQL_PASSWORD'))
  )
]

desiredCredentials.each { replacement ->
  def existing = credentialStore.getCredentials(globalDomain).find { it.id == replacement.id }
  if (existing == null) {
    credentialStore.addCredentials(globalDomain, replacement)
  } else {
    credentialStore.updateCredentials(globalDomain, existing, replacement)
  }
}

def jobName = System.getenv('JENKINS_JOB_NAME')
def repositoryUrl = System.getenv('GITHUB_REPOSITORY_URL')
def job = jenkins.getItem(jobName)
if (job == null) {
  job = jenkins.createProject(WorkflowJob.class, jobName)
}
if (!(job instanceof WorkflowJob)) {
  throw new IllegalStateException("Jenkins item '${jobName}' is not a Pipeline job")
}

def scm = new GitSCM(repositoryUrl)
scm.branches = [new BranchSpec('*/main')]
job.setDefinition(new CpsScmFlowDefinition(scm, 'Jenkinsfile'))
job.save()
jenkins.save()

if (job.getLastBuild() == null) {
  job.scheduleBuild2(0)
}
