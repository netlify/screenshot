pipeline {
  agent any

  options {
    timestamps()
  }

  environment {
    CI = 'true'
  }

  stages {
    stage("Test and build") {
      parallel {
        stage("Build Docker images") {
          steps {
            sh "kubernetes/build-image.sh"
          }
        }
      }
    }
    stage("Publish K8S artifacts") {
      steps {
        withCredentials([file(credentialsId: 'google-container-registry-push', variable: 'GCLOUD_SECRET_FILE')]) {
          sh "kubernetes/publish.sh"
        }
      }
    }
  }

  post {
    failure {
      slackSend color: "danger", message: "Build failed - ${env.JOB_NAME} ${env.BUILD_NUMBER} (<${env.RUN_DISPLAY_URL}|Open>)"
    }
    success {
      slackSend color: "good", message: "Build succeeded - ${env.JOB_NAME} ${env.BUILD_NUMBER} (<${env.RUN_DISPLAY_URL}|Open>)"
    }
    always {
      junit 'test-reports/**/*.xml'
    }
  }
}
