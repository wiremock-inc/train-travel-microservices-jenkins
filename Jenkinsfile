// Runs the Postman collection against the gateway, with its downstream services mocked in a WireMock Cloud environment
// that the WireMock Cloud Jenkins plugin creates for the build from .wiremock/ and deletes afterwards.
pipeline {
    agent any
    stages {
        stage('Build') {
            steps {
                sh './gradlew --no-daemon -q bootJar'
            }
        }
        stage('Postman') {
            steps {
                // The template turns the environment's mock API URLs into the gateway's config
                wiremockEnvironment(templates: [[source: 'ci/application.yml.hbs', target: 'config/application.yml']]) {
                    sh 'ci/postman.sh'
                }
            }
            post {
                always {
                    junit allowEmptyResults: true, testResults: 'build/newman/*.xml'
                }
            }
        }
    }
}
