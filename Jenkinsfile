pipeline {
  agent any

  environment {
    DOCKERHUB_NAMESPACE = 'staystar'
    IMAGE_TAG = "${BUILD_NUMBER}"
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Build Images') {
      steps {
        sh 'docker build -t $DOCKERHUB_NAMESPACE/fullstack-backend:$IMAGE_TAG backend'
        sh 'docker build -t $DOCKERHUB_NAMESPACE/fullstack-frontend:$IMAGE_TAG frontend'
      }
    }

    stage('Push Images') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_TOKEN')]) {
          sh 'echo "$DOCKER_TOKEN" | docker login --username "$DOCKER_USER" --password-stdin'
          sh 'docker push $DOCKERHUB_NAMESPACE/fullstack-backend:$IMAGE_TAG'
          sh 'docker push $DOCKERHUB_NAMESPACE/fullstack-frontend:$IMAGE_TAG'
          sh 'docker logout'
        }
      }
    }

    stage('Deploy') {
      steps {
        withCredentials([
          string(credentialsId: 'mysql-root-password', variable: 'MYSQL_ROOT_PASSWORD'),
          string(credentialsId: 'mysql-app-password', variable: 'MYSQL_PASSWORD'),
          file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')
        ]) {
          sh '''
            kubectl apply -f k8s/namespace.yaml
            kubectl -n app create secret generic mysql-secret \\
              --from-literal=MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD" \\
              --from-literal=MYSQL_DATABASE=appdb \\
              --from-literal=MYSQL_USER=app \\
              --from-literal=MYSQL_PASSWORD="$MYSQL_PASSWORD" \\
              --dry-run=client -o yaml | kubectl apply -f -
            kubectl apply -f k8s/mysql-pv-pvc.yaml -f k8s/mysql.yaml
            kubectl apply -f k8s/backend.yaml -f k8s/frontend.yaml -f k8s/ingress.yaml
            kubectl -n app set image deployment/backend backend="$DOCKERHUB_NAMESPACE/fullstack-backend:$IMAGE_TAG"
            kubectl -n app set image deployment/frontend frontend="$DOCKERHUB_NAMESPACE/fullstack-frontend:$IMAGE_TAG"
            kubectl -n app rollout status deployment/mysql --timeout=180s
            kubectl -n app rollout status deployment/backend --timeout=180s
            kubectl -n app rollout status deployment/frontend --timeout=180s
          '''
        }
      }
    }
  }
}
